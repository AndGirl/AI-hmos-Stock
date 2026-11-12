import { Market, TradeStatus } from './QuoteModels';

/**
 * 交易契约（FR-07 §3 / 设计 §5.4）。
 * 只定义「消费」契约：账户、可买额度、标的可交易性、委托提交与回执，
 * 不解释撮合、风控、资金规则（那些由交易网关返回错误码，前端只映射文案）。
 */

/** 弹窗来源位（FR-07.1：只透传，不做状态判断）。 */
export type TradeSource = 'detail' | 'pane' | 'deepLink';

export type OrderSide = 'buy';

/** 回执三态：受理 / 拒绝 / 结果未知（超时，禁止自动重发）。 */
export type OrderStatus = 'accepted' | 'rejected' | 'unknown';

/** 委托错误码：前端只按码映射文案，不在 L2 出现中文。 */
export type OrderErrorCode = 'fund_short' | 'price_limit' | 'closed' | 'risk' | 'timeout';

/** 登录态（FR-07.10：未登录入口放行，先登录再续开）。 */
export class AuthSession {
  loggedIn: boolean;

  constructor(loggedIn: boolean) {
    this.loggedIn = loggedIn;
  }
}

/** 股东账户（可买 = 可用资金 / 委托价推导，由上层计算，不缓存二次推导结果）。 */
export class AccountInfo {
  id: string;
  /** 脱敏账号：前 3 后 2（FR-07 §5 Q7）。 */
  maskNo: string;
  /** 可用资金（元）。 */
  available: number;
  /** 已持有股数。 */
  holdQty: number;
  opened: boolean;
  canTrade: boolean;

  constructor(id: string, maskNo: string, available: number, holdQty: number, opened: boolean,
    canTrade: boolean) {
    this.id = id;
    this.maskNo = maskNo;
    this.available = available;
    this.holdQty = holdQty;
    this.opened = opened;
    this.canTrade = canTrade;
  }
}

/** 标的中与委托相关的字段（涨跌停由昨收推导，见 trade 的 TradeRules）。 */
export class Tradable {
  code: string;
  name: string;
  market: Market;
  status: TradeStatus;
  last: number | null;
  prevClose: number | null;
  limitUp: number;
  limitDown: number;
  snapshotTime: number;

  constructor(code: string, name: string, market: Market, status: TradeStatus, last: number | null,
    prevClose: number | null, limitUp: number, limitDown: number, snapshotTime: number) {
    this.code = code;
    this.name = name;
    this.market = market;
    this.status = status;
    this.last = last;
    this.prevClose = prevClose;
    this.limitUp = limitUp;
    this.limitDown = limitDown;
    this.snapshotTime = snapshotTime;
  }
}

/** 弹窗上下文：标的信息 + 账户列表 + 登录/在线状态 + 来源位（打开弹窗时一次取齐）。 */
export class TradeContext {
  tradable: Tradable;
  accounts: AccountInfo[];
  loggedIn: boolean;
  online: boolean;
  source: TradeSource;

  constructor(tradable: Tradable, accounts: AccountInfo[], loggedIn: boolean, online: boolean,
    source: TradeSource) {
    this.tradable = tradable;
    this.accounts = accounts;
    this.loggedIn = loggedIn;
    this.online = online;
    this.source = source;
  }
}

/** 委托草稿：clientOrderId 进入弹窗生成、流程内复用、成功后作废（INV-T1）。 */
export class OrderDraft {
  code: string;
  accountId: string;
  side: OrderSide;
  price: number;
  qty: number;
  clientOrderId: string;

  constructor(code: string, accountId: string, price: number, qty: number, clientOrderId: string) {
    this.code = code;
    this.accountId = accountId;
    this.side = 'buy';
    this.price = price;
    this.qty = qty;
    this.clientOrderId = clientOrderId;
  }
}

/** 委托回执：成功含委托号与状态文案码，失败含错误码，超时为 unknown。 */
export class OrderResult {
  clientOrderId: string;
  orderId: string;
  status: OrderStatus;
  code: string;
  ts: number;

  constructor(clientOrderId: string, orderId: string, status: OrderStatus, code: string, ts: number) {
    this.clientOrderId = clientOrderId;
    this.orderId = orderId;
    this.status = status;
    this.code = code;
    this.ts = ts;
  }
}

export type TradeErrorReason = 'not_found' | 'internal';

/** 上下文加载失败：not_found → 不打开弹窗，其余 → toast 后不打开。 */
export class TradeError extends Error {
  reason: TradeErrorReason;

  constructor(reason: TradeErrorReason, message: string) {
    super(message);
    this.reason = reason;
  }
}

/**
 * 交易网关 + 账户/标的上下文。
 * 与真实网关同形（DEC-07-01）：幂等键由前端生成，网关按它去重；超时由调用方计时。
 */
export interface TradeProvider {
  loadContext(code: string, source: TradeSource): Promise<TradeContext>;

  /** Mock 登录（真实实现走账号中心）。 */
  login(): Promise<void>;

  submit(draft: OrderDraft): Promise<OrderResult>;

  query(clientOrderId: string): Promise<OrderResult>;
}
