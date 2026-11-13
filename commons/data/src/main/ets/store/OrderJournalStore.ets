import { StorageAdapter } from './StorageAdapter';
import { OrderSide } from '../model/TradeModels';

const KEY: string = 'order_journal_v1';
const MAX_ENTRIES: number = 20;

/**
 * 委托流水（M10-2 / AC-113，`order_journal_v1`）。
 *
 * 作用：**提交前**落盘 `clientOrderId`，回执/查询后更新状态。这样
 * 「提交超时 → 杀进程 → 重进页面」还能拿同一个键去 `query` 补偿，
 * 而不会因为重发产生第二笔委托。
 *
 * 约束：
 * - 只保留最近 20 条（计划 §5.5），超出按时间淘汰；
 * - 只存「键 + 委托要素 + 状态」，不存账号/金额明细（合规：日志与磁盘不落敏感信息）；
 * - 唯一存储入口仍是 `StorageAdapter`；类上没有方法依赖（纯数据），避免 JSON 还原后调不到方法。
 */

/** 一条流水（纯数据类，不要加方法）。 */
export class JournalEntry {
  clientOrderId: string;
  code: string;
  side: OrderSide;
  price: number;
  qty: number;
  /** 回执/查询后的状态：`submitted` / `accepted` / `filled` / `rejected` / `unknown`。 */
  status: string;
  ts: number;

  constructor(clientOrderId: string, code: string, side: OrderSide, price: number, qty: number,
    status: string, ts: number) {
    this.clientOrderId = clientOrderId;
    this.code = code;
    this.side = side;
    this.price = price;
    this.qty = qty;
    this.status = status;
    this.ts = ts;
  }
}

class JournalDoc {
  version: number = 1;
  entries: JournalEntry[] = [];
}

export class OrderJournalStore {
  private entries: JournalEntry[] = [];
  private loaded: boolean = false;
  private loading: Promise<void> | undefined = undefined;

  /** 读盘（幂等；重复调用复用同一 Promise）。 */
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
        const doc: JournalDoc = JSON.parse(raw) as JournalDoc;
        const items: JournalEntry[] = doc.entries !== undefined && doc.entries !== null ? doc.entries : [];
        this.entries = items.filter((item: JournalEntry): boolean =>
          item !== null && item.clientOrderId !== undefined && item.clientOrderId.length > 0);
      }
    } catch (err) {
      // 读失败回默认（空流水），不阻塞下单。
    }
    this.loaded = true;
  }

  /** 提交前写入（同键覆盖，保证重试不产生两条）。 */
  async put(entry: JournalEntry): Promise<void> {
    await this.load();
    const next: JournalEntry[] = [];
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].clientOrderId !== entry.clientOrderId) {
        next.push(this.entries[i]);
      }
    }
    next.push(entry);
    this.entries = next.length > MAX_ENTRIES ? next.slice(next.length - MAX_ENTRIES) : next;
    await this.persist();
  }

  /** 收到回执/查询结果后更新状态；不存在则忽略（幂等）。 */
  async mark(clientOrderId: string, status: string): Promise<void> {
    await this.load();
    let changed: boolean = false;
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].clientOrderId === clientOrderId) {
        this.entries[i].status = status;
        this.entries[i].ts = Date.now();
        changed = true;
      }
    }
    if (changed) {
      await this.persist();
    }
  }

  /** 取一条（补偿查询用）。 */
  get(clientOrderId: string): JournalEntry | undefined {
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].clientOrderId === clientOrderId) {
        return this.entries[i];
      }
    }
    return undefined;
  }

  /** 未终态流水（重进页面时优先补偿这些）。 */
  pending(): JournalEntry[] {
    const result: JournalEntry[] = [];
    for (let i = 0; i < this.entries.length; i++) {
      const status: string = this.entries[i].status;
      if (status !== 'filled' && status !== 'rejected' && status !== 'canceled') {
        result.push(this.entries[i]);
      }
    }
    return result;
  }

  size(): number {
    return this.entries.length;
  }

  loadedReady(): boolean {
    return this.loaded;
  }

  async clear(): Promise<void> {
    this.entries = [];
    await StorageAdapter.remove(KEY);
  }

  private async persist(): Promise<void> {
    const doc: JournalDoc = new JournalDoc();
    doc.entries = this.entries;
    await StorageAdapter.putString(KEY, JSON.stringify(doc));
  }
}
