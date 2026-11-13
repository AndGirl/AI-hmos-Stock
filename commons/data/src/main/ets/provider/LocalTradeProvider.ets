import { ConnectionHost } from 'commons_basic';
import { QuoteProvider, QuoteSnapshot } from '../model/QuoteModels';
import {
  AccountInfo,
  CancelResult,
  isFinalState,
  OpenAccountResult,
  OrderDraft,
  OrderItem,
  OrderPage,
  OrderQuery,
  OrderResult,
  OrderSide,
  OrderState,
  OrderStatus,
  TradeContext,
  TradeError,
  TradeProvider,
  TradeSource,
  Tradable
} from '../model/TradeModels';
import { LimitPair, resolveLimits } from '../rules/LimitRules';
import {
  canCancel,
  CancelDecision,
  MatchAccount,
  MatchOrder,
  MatchOutcome,
  matchOnce,
  MatchQuote,
  round2
} from '../rules/MatchingRules';
import { TradeAccountStore, AccountRecord } from '../store/TradeAccountStore';
import { TradeOrderStore } from '../store/TradeOrderStore';
import { JournalEntry, OrderJournalStore } from '../store/OrderJournalStore';
import { buildNoAccounts, TradeAuth } from '../mock/TradeSeeds';
import { MockFaults } from '../mock/MockFaults';

const CONTEXT_LATENCY_MS: number = 80;
const SUBMIT_LATENCY_MS: number = 120;
const QUERY_LATENCY_MS: number = 80;
const LOGIN_LATENCY_MS: number = 300;
/** 待报 → 已报 的最小间隔（让列表能看见「待报」这一态）。 */
const ACCEPT_DELAY_MS: number = 1000;
/** 撮合推进节拍。 */
const TICK_MS: number = 1000;

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: (value: void) => void): void => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}

/**
 * 本地模拟交易网关（M10-2，替代原 `MockTradeProvider`）。
 *
 * 为什么单独一个实现而不是继续在 Mock 上加分支：M10 起它要做三件「有状态」的事——
 * 撮合推进、资金/持仓记账、委托落盘；与原来「一次性返回回执」的 Mock 不是同一量级。
 *
 * 口径：
 * - **无真实券商**：撮合规则见 `MatchingRules`（分阶段 + 行情联动，纯函数）；
 * - 超时语义沿用阶段一：调用方 2s 未收到回执即「结果未知」，**禁止自动重发**；
 * - 幂等：`clientOrderId` 命中已有委托直接返回原回执（不产生第二单）；
 * - 资金：买单提交即冻结、成交/撤单释放；卖出按持仓可卖校验；
 * - 落盘：委托 `trade_orders_v1`、账户/持仓 `trade_account_v1`、幂等流水 `order_journal_v1`。
 */
export class LocalTradeProvider implements TradeProvider {
  private quotes: QuoteProvider;
  private accounts: TradeAccountStore;
  private orders: TradeOrderStore;
  private journal: OrderJournalStore;
  private timer: number = -1;
  private seq: number = 0;
  /** F2：写操作串行化——提交/撮合/撤单互斥，避免撤单被在途撮合覆盖。 */
  private queue: Promise<void> = Promise.resolve();
  /** tick 防重入（队列里已有一次撮合时不再排新的一拍）。 */
  private ticking: boolean = false;
  /** F3：委托变化监听（VM 据此就地刷新行，不引入 UI 定时器）。 */
  private changeListeners: (() => void)[] = [];

  constructor(quotes: QuoteProvider, accounts: TradeAccountStore, orders: TradeOrderStore,
    journal: OrderJournalStore) {
    this.quotes = quotes;
    this.accounts = accounts;
    this.orders = orders;
    this.journal = journal;
  }

  /** 写操作入队：前一个完成后再执行，保证撤单与撮合并发安全。 */
  private enqueue<T>(task: () => Promise<T>): Promise<T> {
    const run: Promise<T> = this.queue.then(task, task);
    this.queue = run.then((): void => {
    }, (): void => {
    });
    return run;
  }

  /** 订阅委托变化（同实例多订阅者取并集；VM 在页面销毁时退订）。 */
  subscribeChanges(listener: () => void): void {
    if (this.changeListeners.indexOf(listener) < 0) {
      this.changeListeners.push(listener);
    }
  }

  unsubscribeChanges(listener: () => void): void {
    const index: number = this.changeListeners.indexOf(listener);
    if (index >= 0) {
      this.changeListeners.splice(index, 1);
    }
  }

  private notifyChanged(): void {
    for (let i = 0; i < this.changeListeners.length; i++) {
      this.changeListeners[i]();
    }
  }

  async loadContext(code: string, source: TradeSource): Promise<TradeContext> {
    await delay(CONTEXT_LATENCY_MS);
    const quote: QuoteSnapshot | undefined = await this.quoteOf(code);
    if (quote === undefined) {
      throw new TradeError('not_found', 'unknown code ' + code);
    }
    const prevClose: number | null = quote.prevClose;
    // 涨跌停与行情同源：快照已按板块下发（主板 10 / ST 5 / 科创·创业 20 / 北交所 30）。
    const pair: LimitPair = resolveLimits(prevClose, quote.code, quote.name, quote.limitUp, quote.limitDown);
    const limitUp: number = pair.limitUp !== null ? pair.limitUp : 0;
    const limitDown: number = pair.limitDown !== null ? pair.limitDown : 0;
    // 故障注入的「非交易时段」只覆盖时间因素（不改标的停牌/退市状态）。
    const status = MockFaults.tradeClosed ? 'closed' : quote.status;
    const tradable: Tradable = new Tradable(quote.code, quote.name, quote.market, status,
      quote.last, prevClose, limitUp, limitDown, quote.snapshotTime);
    await this.accounts.load();
    const accounts: AccountInfo[] = MockFaults.tradeNoAccount ? buildNoAccounts() : this.accounts.infos();
    const online: boolean = !MockFaults.tradeOffline && !ConnectionHost.getService().isOffline();
    return new TradeContext(tradable, accounts, TradeAuth.loggedIn, online, source);
  }

  async login(): Promise<void> {
    await delay(LOGIN_LATENCY_MS);
    TradeAuth.loggedIn = true;
  }

  submit(draft: OrderDraft): Promise<OrderResult> {
    return this.enqueue((): Promise<OrderResult> => this.doSubmit(draft));
  }

  private async doSubmit(draft: OrderDraft): Promise<OrderResult> {
    await this.orders.load();
    await this.journal.load();
    await this.accounts.load();
    // 幂等：同键重复提交只返回原回执（AC-113）。
    const existing: OrderItem | undefined = this.orders.get(draft.clientOrderId);
    if (existing !== undefined) {
      return this.receiptOf(existing);
    }
    const quote: QuoteSnapshot | undefined = await this.quoteOf(draft.code);
    if (quote === undefined) {
      throw new TradeError('not_found', 'unknown code ' + draft.code);
    }
    await delay(SUBMIT_LATENCY_MS);
    const now: number = Date.now();
    const account: AccountRecord | undefined = this.accounts.record(draft.accountId);
    const opened: boolean = account !== undefined && account.opened;
    const available: number = this.accounts.availableOf(draft.accountId);
    const sellable: number = this.accounts.sellableOf(draft.accountId);
    const side: OrderSide = draft.side;
    const matchAccount: MatchAccount = new MatchAccount(TradeAuth.loggedIn, opened, available, sellable);
    const matchOrder: MatchOrder = new MatchOrder(draft.code, side, draft.price, draft.qty, 0);
    const outcome: MatchOutcome = matchOnce(matchOrder, this.quoteOfSnapshot(quote), matchAccount);
    let state: OrderState = outcome.state;
    let reason: string = outcome.reasonCode;
    if (MockFaults.tradeReject && outcome.decision !== 'reject') {
      state = 'rejected';
      reason = 'risk';
    }
    const orderId: string = this.nextOrderId(now);
    const item: OrderItem = new OrderItem(draft.clientOrderId, orderId, draft.accountId, draft.code,
      quote.name, side, draft.price, draft.qty, outcome.fillQty, state, now, now, reason);
    if (state !== 'rejected') {
      await this.bookSubmit(item, outcome.fillQty);
    }
    await this.orders.upsert(item);
    await this.journal.put(new JournalEntry(item.clientOrderId, item.code, side, item.price, item.qty,
      state, now));
    if (state === 'pending' || state === 'accepted' || state === 'partial') {
      this.ensureTimer();
    }
    this.notifyChanged();
    return this.receiptOf(item);
  }

  async query(clientOrderId: string): Promise<OrderResult> {
    await this.orders.load();
    await this.journal.load();
    await delay(QUERY_LATENCY_MS);
    const item: OrderItem | undefined = this.orders.get(clientOrderId);
    if (item !== undefined) {
      return this.receiptOf(item);
    }
    const journal: JournalEntry | undefined = this.journal.get(clientOrderId);
    if (journal !== undefined) {
      // 有流水无委托：状态未知（禁止自动重发，等补偿查询）。
      return new OrderResult(clientOrderId, '', 'unknown', journal.code, Date.now(), '');
    }
    throw new TradeError('not_found', 'unknown clientOrderId ' + clientOrderId);
  }

  async listOrders(query: OrderQuery): Promise<OrderPage> {
    await this.orders.load();
    return this.orders.list(query);
  }

  cancelOrder(orderId: string, clientOrderId: string): Promise<CancelResult> {
    return this.enqueue((): Promise<CancelResult> => this.doCancelOrder(orderId, clientOrderId));
  }

  private async doCancelOrder(orderId: string, clientOrderId: string): Promise<CancelResult> {
    await this.orders.load();
    await this.journal.load();
    const now: number = Date.now();
    let item: OrderItem | undefined = this.orders.getByOrderId(orderId);
    if (item === undefined && clientOrderId.length > 0) {
      item = this.orders.get(clientOrderId);
    }
    if (item === undefined) {
      return new CancelResult(clientOrderId, orderId, false, 'unknown', 'not_found', now);
    }
    const decision: CancelDecision = canCancel(item.state);
    if (!decision.ok) {
      // 不可撤（已成/已撤/废单）：幂等返回当前状态与原因，不抛错。
      return new CancelResult(item.clientOrderId, item.orderId, false, item.state, decision.reasonCode, now);
    }
    const remaining: number = item.remaining();
    if (item.side === 'buy' && remaining > 0) {
      await this.accounts.unfreeze(item.accountId, round2(item.price * remaining));
    }
    item.state = 'canceled';
    item.updatedAt = now;
    await this.orders.upsert(item);
    await this.journal.mark(item.clientOrderId, 'canceled');
    this.stopTimerIfIdle();
    this.notifyChanged();
    return new CancelResult(item.clientOrderId, item.orderId, true, 'canceled', '', now);
  }

  /** 本地开户（M10-1）：没有真实券商，只把本地账户标记为已开通。 */
  async openAccount(): Promise<OpenAccountResult> {
    await this.accounts.load();
    const ids: string[] = this.accounts.ids();
    if (ids.length === 0) {
      return new OpenAccountResult(false, 'local', 'busy');
    }
    const ok: boolean = await this.accounts.open(ids[0]);
    await this.accounts.flush();
    return new OpenAccountResult(ok, 'local', ok ? '' : 'no_account');
  }

  /** 撮合推进（1s 一拍）：待报 → 已报 → 部成/已成。测试可直接调用。 */
  tick(now: number): Promise<void> {
    if (this.ticking) {
      return Promise.resolve();
    }
    this.ticking = true;
    const run: Promise<void> = this.enqueue((): Promise<void> => this.doTick(now));
    return run.then((): void => {
      this.ticking = false;
    }, (): void => {
      this.ticking = false;
    });
  }

  private async doTick(now: number): Promise<void> {
    await this.orders.load();
    const open: OrderItem[] = this.orders.openOrders();
    if (open.length === 0) {
      this.stopTimer();
      return;
    }
    for (let i = 0; i < open.length; i++) {
      // F1：队列里拿到的引用可能已被撤单/成交改过，每拍按最新状态重取一次。
      const live: OrderItem | undefined = this.orders.get(open[i].clientOrderId);
      if (live === undefined || isFinalState(live.state)) {
        continue;
      }
      const item: OrderItem = live;
      if (item.state === 'pending') {
        if (now - item.createdAt < ACCEPT_DELAY_MS) {
          continue;
        }
        item.state = 'accepted';
        item.updatedAt = now;
        await this.orders.upsert(item);
        await this.journal.mark(item.clientOrderId, 'accepted');
        continue;
      }
      const quote: QuoteSnapshot | undefined = await this.quoteOf(item.code);
      if (quote === undefined) {
        continue;
      }
      const available: number = this.accounts.availableOf(item.accountId);
      const sellable: number = this.accounts.sellableOf(item.accountId);
      const account: MatchAccount = new MatchAccount(true, true, available, sellable);
      const order: MatchOrder = new MatchOrder(item.code, item.side, item.price, item.qty, item.filledQty);
      const outcome: MatchOutcome = matchOnce(order, this.quoteOfSnapshot(quote), account);
      if (outcome.decision === 'reject') {
        // 撮合中不再会拒单（提交时已校验）；出现则按废单收口并释放冻结。
        await this.releaseRemaining(item);
        item.state = 'rejected';
        item.reasonCode = outcome.reasonCode;
      } else if (outcome.fillQty > 0) {
        await this.bookFill(item, outcome.fillQty);
        item.filledQty += outcome.fillQty;
        item.state = outcome.state;
        item.updatedAt = now;
      }
      await this.orders.upsert(item);
      await this.journal.mark(item.clientOrderId, item.state);
    }
    this.stopTimerIfIdle();
    this.notifyChanged();
  }

  /** 调试：重置账户与委托（回到种子）。 */
  async resetAll(): Promise<void> {
    await this.accounts.resetAll();
    await this.orders.clear();
    await this.journal.clear();
    this.stopTimer();
  }

  // ---------- 私有 ----------

  /**
   * 提交时的资金处理：买单冻结未成交部分；已成交部分直接记账。
   * 成交价统一取**委托价**（限价单语义，可预测、不随行情跳动而变），见 `bookFill`。
   */
  private async bookSubmit(item: OrderItem, fillQty: number): Promise<void> {
    if (item.side === 'buy') {
      const remaining: number = item.qty - fillQty;
      if (remaining > 0) {
        await this.accounts.freeze(item.accountId, round2(item.price * remaining));
      }
    }
    if (fillQty > 0) {
      if (item.side === 'buy') {
        await this.accounts.unfreeze(item.accountId, round2(item.price * fillQty));
      }
      await this.accounts.applyFill(item.accountId, item.side, item.code, item.price, fillQty);
    }
    await this.accounts.flush();
  }

  /** 成交记账：释放该笔冻结后按成交价落账。 */
  private async bookFill(item: OrderItem, fillQty: number): Promise<void> {
    if (item.side === 'buy') {
      await this.accounts.unfreeze(item.accountId, round2(item.price * fillQty));
      await this.accounts.applyFill(item.accountId, 'buy', item.code, item.price, fillQty);
    } else {
      await this.accounts.applyFill(item.accountId, 'sell', item.code, item.price, fillQty);
    }
    await this.accounts.flush();
  }

  private async releaseRemaining(item: OrderItem): Promise<void> {
    const remaining: number = item.remaining();
    if (item.side === 'buy' && remaining > 0) {
      await this.accounts.unfreeze(item.accountId, round2(item.price * remaining));
    }
  }

  private receiptOf(item: OrderItem): OrderResult {
    let status: OrderStatus = 'accepted';
    if (item.state === 'rejected') {
      status = 'rejected';
    } else if (item.state === 'unknown') {
      status = 'unknown';
    }
    return new OrderResult(item.clientOrderId, item.orderId, status, item.code, item.updatedAt,
      item.reasonCode);
  }

  private async quoteOf(code: string): Promise<QuoteSnapshot | undefined> {
    const list: QuoteSnapshot[] = await this.quotes.getSnapshots([code]);
    return list.length > 0 ? list[0] : undefined;
  }

  private quoteOfSnapshot(quote: QuoteSnapshot): MatchQuote {
    const pair: LimitPair = resolveLimits(quote.prevClose, quote.code, quote.name,
      quote.limitUp, quote.limitDown);
    return new MatchQuote(quote.status, quote.last, pair.limitUp !== null ? pair.limitUp : 0,
      pair.limitDown !== null ? pair.limitDown : 0);
  }

  private nextOrderId(now: number): string {
    this.seq++;
    const tail: string = this.seq < 10 ? `00${this.seq}` : (this.seq < 100 ? `0${this.seq}` : `${this.seq}`);
    return `O${now}${tail}`;
  }

  private ensureTimer(): void {
    if (this.timer !== -1) {
      return;
    }
    this.timer = setInterval((): void => {
      this.tick(Date.now()).catch((): void => {
      });
    }, TICK_MS);
  }

  private stopTimer(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private stopTimerIfIdle(): void {
    if (this.orders.openOrders().length === 0) {
      this.stopTimer();
    }
  }
}
