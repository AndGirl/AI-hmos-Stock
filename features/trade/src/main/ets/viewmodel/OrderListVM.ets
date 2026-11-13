import {
  CancelResult,
  DataServices,
  MockFaults,
  OpenAccountResult,
  OrderItem,
  OrderPage,
  OrderQuery,
  TradeProvider
} from 'commons_data';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 列表状态：loading / content / empty / error / no_account（未开户引导）。 */
export type OrderListState = 'loading' | 'content' | 'empty' | 'error' | 'no_account';

/** 每页条数（AC-115：分页 20）。 */
export const ORDER_PAGE_SIZE: number = 20;

/** 状态筛选项（顺序即 chip 顺序）。 */
export const ORDER_FILTERS: string[] =
  ['all', 'pending', 'accepted', 'partial', 'filled', 'canceled', 'rejected'];

/**
 * 委托行 VM（M10-4）：只装原始值 + 派生布尔，文案在 View 层映射（R-07 不 import commons_data）。
 */
@ObservedV2
export class OrderRowVM {
  @Trace clientOrderId: string = '';
  @Trace orderId: string = '';
  @Trace code: string = '';
  @Trace name: string = '';
  @Trace side: string = 'buy';
  @Trace price: number = 0;
  @Trace qty: number = 0;
  @Trace filledQty: number = 0;
  @Trace state: string = 'pending';
  @Trace reasonCode: string = '';
  /** 仅可撤态为真（AC-116：不可撤不显示按钮，不是禁用）。 */
  @Trace cancelable: boolean = false;
  /** 撤单请求在途（乐观「撤单中」）。 */
  @Trace canceling: boolean = false;

  static of(item: OrderItem): OrderRowVM {
    const row: OrderRowVM = new OrderRowVM();
    row.clientOrderId = item.clientOrderId;
    row.orderId = item.orderId;
    row.code = item.code;
    row.name = item.name;
    row.side = item.side;
    row.price = item.price;
    row.qty = item.qty;
    row.filledQty = item.filledQty;
    row.state = item.state;
    row.reasonCode = item.reasonCode;
    row.cancelable = item.state === 'pending' || item.state === 'accepted' || item.state === 'partial';
    return row;
  }

  copy(item: OrderItem): void {
    this.state = item.state;
    this.filledQty = item.filledQty;
    this.reasonCode = item.reasonCode;
    this.cancelable = item.state === 'pending' || item.state === 'accepted' || item.state === 'partial';
    this.canceling = false;
  }
}

/**
 * 委托列表 VM（M10-4 / M10-5）。
 *
 * 口径：
 * - 未开户 → `no_account`（AC-112 引导，不阻塞其它页面）；
 * - 分页 20、可累加（`loadMore`）、按状态过滤；
 * - 撤单：仅可撤态显示按钮；请求在途显示「撤单中」；成功/失败都刷新列表；
 * - 只做业务编排，不碰 UI（toast 由页面按返回码决定）。
 */
@ObservedV2
export class OrderListVM {
  @Trace state: OrderListState = 'loading';
  @Trace rows: OrderRowVM[] = [];
  @Trace filter: string = 'all';
  @Trace total: number = 0;
  @Trace hasMore: boolean = false;
  @Trace busy: boolean = false;

  private page: number = 0;
  private token: number = 0;

  private provider(): TradeProvider {
    return DataServices.tradeProvider();
  }

  /** 首次进入 / 切筛选 / 刷新：回到第 0 页。 */
  async load(): Promise<void> {
    this.token++;
    const token: number = this.token;
    this.busy = true;
    if (this.state !== 'content') {
      this.state = 'loading';
    }
    try {
      const opened: boolean = await this.hasOpenedAccount();
      if (token !== this.token) {
        return;
      }
      if (!opened) {
        this.rows = [];
        this.total = 0;
        this.hasMore = false;
        this.state = 'no_account';
        return;
      }
      const page: OrderPage = await this.fetchPage(0);
      if (token !== this.token) {
        return;
      }
      this.page = 0;
      this.rows = page.items.map((item: OrderItem): OrderRowVM => OrderRowVM.of(item));
      this.total = page.total;
      this.hasMore = page.hasMore;
      this.state = this.rows.length === 0 ? 'empty' : 'content';
    } catch (err) {
      if (token === this.token) {
        this.state = 'error';
      }
      hilog.warn(0x0001, 'TradeLog', 'orders_load_failed');
    } finally {
      if (token === this.token) {
        this.busy = false;
      }
    }
  }

  /** 加载下一页（滚动到底触发）。 */
  async loadMore(): Promise<void> {
    if (!this.hasMore || this.busy) {
      return;
    }
    this.busy = true;
    const token: number = this.token;
    try {
      const next: OrderPage = await this.fetchPage(this.page + 1);
      if (token !== this.token) {
        return;
      }
      this.page = next.page;
      for (let i = 0; i < next.items.length; i++) {
        this.rows.push(OrderRowVM.of(next.items[i]));
      }
      this.total = next.total;
      this.hasMore = next.hasMore;
    } catch (err) {
      hilog.warn(0x0001, 'TradeLog', 'orders_more_failed');
    } finally {
      this.busy = false;
    }
  }

  /** 切筛选（重新加载第 0 页）。 */
  async setFilter(state: string): Promise<void> {
    if (this.filter === state) {
      return;
    }
    this.filter = state;
    this.rows = [];
    this.state = 'loading';
    await this.load();
  }

  /**
   * 撤单（M10-5）：成功返回 `canceled`；不可撤/失败返回 `cancel_failed:<reason>`。
   * 无条件刷新一次列表，保证状态与服务端一致。
   */
  async cancel(row: OrderRowVM): Promise<string> {
    if (row.canceling) {
      return '';
    }
    row.canceling = true;
    const provider: TradeProvider = this.provider();
    if (provider.cancelOrder === undefined) {
      row.canceling = false;
      return 'cancel_failed:busy';
    }
    try {
      const result: CancelResult = await provider.cancelOrder(row.orderId, row.clientOrderId);
      if (result.ok) {
        await this.load();
        return 'canceled';
      }
      row.canceling = false;
      const reason: string = result.reasonCode.length > 0 ? result.reasonCode : 'not_cancelable';
      return `cancel_failed:${reason}`;
    } catch (err) {
      row.canceling = false;
      return 'cancel_failed:unknown';
    }
  }

  /** 本地开通模拟账户（AC-112）：成功后重新加载。 */
  async openAccount(): Promise<boolean> {
    const provider: TradeProvider = this.provider();
    if (provider.openAccount === undefined) {
      return false;
    }
    try {
      const result: OpenAccountResult = await provider.openAccount();
      if (!result.ok) {
        return false;
      }
      await this.load();
      return true;
    } catch (err) {
      return false;
    }
  }

  private fetchPage(page: number): Promise<OrderPage> {
    const provider: TradeProvider = this.provider();
    if (provider.listOrders === undefined) {
      return Promise.reject(new Error('listOrders unsupported'));
    }
    return provider.listOrders(new OrderQuery(page, ORDER_PAGE_SIZE, this.filter));
  }

  /** 是否有已开通账户（未开户 → 引导页）。 */
  private async hasOpenedAccount(): Promise<boolean> {
    if (MockFaults.tradeNoAccount) {
      return false;
    }
    const store = DataServices.tradeAccount();
    await store.load();
    const infos: number = store.infos().length;
    if (infos === 0) {
      return false;
    }
    const records = store.records();
    for (let i = 0; i < records.length; i++) {
      if (records[i].opened) {
        return true;
      }
    }
    return false;
  }
}
