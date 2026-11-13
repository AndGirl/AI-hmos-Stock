import { isFinalState, OrderItem, OrderPage, OrderQuery, OrderState } from '../model/TradeModels';
import { StorageAdapter } from './StorageAdapter';

const KEY: string = 'trade_orders_v1';
const WRITE_MERGE_MS: number = 200;
/** 委托列表上限（本地演示：200 条足够，超出淘汰最旧）。 */
export const TRADE_ORDERS_MAX: number = 200;

class OrderDoc {
  version: number = 1;
  items: OrderItem[] = [];
}

/**
 * 委托库（M10-4 / AC-115，`trade_orders_v1`）。
 *
 * 为什么落盘：AC-115 要求「当日委托列表」在重进页面后仍在；
 * 同时 M10-5 的撤单需要按 `orderId` 找回原委托。
 *
 * 口径：按 `createdAt` 倒序（最新在前）；`query.page` 从 0 起、`size` 默认 20；
 * 上限 200 条，超出淘汰最旧。全部走 `StorageAdapter`，200ms 合并写。
 */
export class TradeOrderStore {
  private orders: OrderItem[] = [];
  private loaded: boolean = false;
  private loading: Promise<void> | undefined = undefined;
  private writeTimer: number = -1;
  private dirty: boolean = false;

  load(): Promise<void> {
    const existing: Promise<void> | undefined = this.loading;
    if (existing !== undefined) {
      return existing;
    }
    const task: Promise<void> = this.loadInner();
    this.loading = task;
    return task;
  }

  private async loadInner(): Promise<void> {
    try {
      const raw: string = await StorageAdapter.getString(KEY, '');
      if (raw.length > 0) {
        const doc: OrderDoc = JSON.parse(raw) as OrderDoc;
        const items: OrderItem[] = doc.items !== undefined && doc.items !== null ? doc.items : [];
        this.orders = this.restore(items);
      }
    } catch (err) {
      // 读失败按空列表处理，不阻塞下单。
    }
    this.loaded = true;
  }

  private restore(items: OrderItem[]): OrderItem[] {
    const result: OrderItem[] = [];
    for (let i = 0; i < items.length; i++) {
      const item: OrderItem = items[i];
      if (item === null || item.clientOrderId === undefined) {
        continue;
      }
      result.push(new OrderItem(item.clientOrderId, item.orderId, item.accountId, item.code,
        item.name, item.side, item.price, item.qty, item.filledQty, item.state,
        item.createdAt, item.updatedAt, item.reasonCode));
    }
    result.sort((a: OrderItem, b: OrderItem): number => b.createdAt - a.createdAt);
    return result;
  }

  /** 新增或更新（按 clientOrderId 去重；终态一旦写入不再被覆盖，防并发撮合回写）。 */
  async upsert(item: OrderItem): Promise<void> {
    await this.load();
    let replaced: boolean = false;
    for (let i = 0; i < this.orders.length; i++) {
      if (this.orders[i].clientOrderId === item.clientOrderId) {
        // F1：已成/已撤/废单是终态，晚到的旧状态（如撮合线程手里的 accepted）不得冲掉它。
        if (isFinalState(this.orders[i].state)) {
          return;
        }
        this.orders[i] = item;
        replaced = true;
        break;
      }
    }
    if (!replaced) {
      this.orders.push(item);
      this.orders.sort((a: OrderItem, b: OrderItem): number => b.createdAt - a.createdAt);
      if (this.orders.length > TRADE_ORDERS_MAX) {
        this.orders = this.orders.slice(0, TRADE_ORDERS_MAX);
      }
    }
    this.markDirty();
  }

  /** 按 clientOrderId 取。 */
  get(clientOrderId: string): OrderItem | undefined {
    for (let i = 0; i < this.orders.length; i++) {
      if (this.orders[i].clientOrderId === clientOrderId) {
        return this.orders[i];
      }
    }
    return undefined;
  }

  /** 按 orderId 取（撤单入口）。 */
  getByOrderId(orderId: string): OrderItem | undefined {
    for (let i = 0; i < this.orders.length; i++) {
      if (this.orders[i].orderId === orderId) {
        return this.orders[i];
      }
    }
    return undefined;
  }

  /** 未终态委托（撮合推进用）。 */
  openOrders(): OrderItem[] {
    const result: OrderItem[] = [];
    for (let i = 0; i < this.orders.length; i++) {
      const state: OrderState = this.orders[i].state;
      if (state === 'pending' || state === 'accepted' || state === 'partial') {
        result.push(this.orders[i]);
      }
    }
    return result;
  }

  /** 分页查询：`state` 为 `all` 或具体状态；`code` 为空表示不限标的。 */
  list(query: OrderQuery): OrderPage {
    const filtered: OrderItem[] = [];
    for (let i = 0; i < this.orders.length; i++) {
      const item: OrderItem = this.orders[i];
      if (query.state !== 'all' && item.state !== query.state) {
        continue;
      }
      if (query.code.length > 0 && item.code !== query.code) {
        continue;
      }
      filtered.push(item);
    }
    const size: number = query.size > 0 ? query.size : 20;
    const start: number = query.page * size;
    const items: OrderItem[] = start >= filtered.length ? [] : filtered.slice(start, start + size);
    return new OrderPage(items, filtered.length, query.page, size, start + items.length < filtered.length);
  }

  size(): number {
    return this.orders.length;
  }

  ready(): boolean {
    return this.loaded;
  }

  async clear(): Promise<void> {
    this.orders = [];
    this.dirty = true;
    await this.flush();
  }

  async flush(): Promise<void> {
    this.clearTimer();
    if (!this.dirty) {
      return;
    }
    this.dirty = false;
    const doc: OrderDoc = new OrderDoc();
    doc.items = this.orders;
    await StorageAdapter.putString(KEY, JSON.stringify(doc));
  }

  private markDirty(): void {
    this.dirty = true;
    if (this.writeTimer !== -1) {
      return;
    }
    this.writeTimer = setTimeout((): void => {
      this.writeTimer = -1;
      this.flush().catch((): void => {
      });
    }, WRITE_MERGE_MS);
  }

  private clearTimer(): void {
    if (this.writeTimer !== -1) {
      clearTimeout(this.writeTimer);
      this.writeTimer = -1;
    }
  }
}
