import { Market, TradeStatus } from './QuoteModels';

/**
 * 交易契约（FR-07 §3 / 设计 §5.4）。
 * 只定义「消费」契约：账户、可买额度、标的可交易性、委托提交与回执，
 * 不解释撮合、风控、资金规则（那些由交易网关返回错误码，前端只映射文案）。
 *
 * M10 口径变更（2026-11-14）：**没有真实券商**。`TradeProvider` 的实现改为
 * `LocalTradeProvider`（本地假撮合，见 `docs/api-contract-v1.md`），
 * 契约与「真实网关同形」的原则不变，接本地后端时只换实现。
 */

/** 弹窗来源位（FR-07.1：只透传，不做状态判断）。 */
export type TradeSource = 'detail' | 'pane' | 'deepLink';

/** 买卖方向（M10 增 `sell`：只加不改，`OrderDraft` 尾参默认 `buy`）。 */
export type OrderSide = 'buy' | 'sell';

/** 回执三态：受理 / 拒绝 / 结果未知（超时，禁止自动重发）。 */
export type OrderStatus = 'accepted' | 'rejected' | 'unknown';

/**
 * 委托生命周期（M10-4 / AC-115，7 态，与「回执三态」是两回事）：
 * - `pending`  待报：已本地受理、尚未提交到撮合；
 * - `accepted` 已报：已进入撮合、未成交；
 * - `partial`  部成：部分成交，剩余挂单；
 * - `filled`   已成；
 * - `canceled` 已撤；
 * - `rejected` 废单（含被拒单）；
 * - `unknown`  状态未知（超时/补偿查询失败）。
 */
export type OrderState = 'pending' | 'accepted' | 'partial' | 'filled' | 'canceled' | 'rejected' | 'unknown';

/** 全部状态（顺序即列表筛选项顺序）。 */
export const ORDER_STATES: OrderState[] =
  ['pending', 'accepted', 'partial', 'filled', 'canceled', 'rejected', 'unknown'];

/** 可撤状态（AC-116：只有待报/已报/部成可撤）。 */
export function isCancelable(state: OrderState): boolean {
  return state === 'pending' || state === 'accepted' || state === 'partial';
}

/** 终态（不可再变化）。 */
export function isFinalState(state: OrderState): boolean {
  return state === 'filled' || state === 'canceled' || state === 'rejected';
}

/**
 * 委托错误码：前端只按码映射文案，不在 L2 出现中文。
 * M10-3 扩为 8 个（资金/持仓不足/涨跌停/时段/停牌/权限/风控/繁忙/未知）。
 */
export type OrderErrorCode =
  'fund_short' | 'qty_short' | 'price_limit' | 'closed' | 'suspended' | 'delisted' |
    'no_permission' | 'risk' | 'busy' | 'unknown';

/** 登录态（FR-07.10：未登录入口放行，先登录再续开）。 */
export class AuthSession {
  loggedIn: boolean;

  constructor(loggedIn: boolean) {
    this.loggedIn = loggedIn;
  }
}

/** 股东账户（可买 = (可用资金 − 冻结) / 委托价推导，由上层计算，不缓存二次推导结果）。 */
export class AccountInfo {
  id: string;
  /** 脱敏账号：前 3 后 2（FR-07 §5 Q7）。 */
  maskNo: string;
  /** 可用资金（元，已扣冻结）。 */
  available: number;
  /** 已持有股数。 */
  holdQty: number;
  /** 可卖股数（T+1 口径由本地持仓给，M10 简化为持仓全可卖）。 */
  sellableQty: number;
  opened: boolean;
  canTrade: boolean;

  constructor(id: string, maskNo: string, available: number, holdQty: number, opened: boolean,
    canTrade: boolean, sellableQty?: number) {
    this.id = id;
    this.maskNo = maskNo;
    this.available = available;
    this.holdQty = holdQty;
    this.sellableQty = sellableQty !== undefined ? sellableQty : holdQty;
    this.opened = opened;
    this.canTrade = canTrade;
  }
}

/** 标的中与委托相关的字段（涨跌停由 `commons/data/rules/LimitRules` 推导，下发优先）。 */
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

  constructor(code: string, accountId: string, price: number, qty: number, clientOrderId: string,
    side?: OrderSide) {
    this.code = code;
    this.accountId = accountId;
    this.side = side !== undefined ? side : 'buy';
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
  /** M10：错误码（`OrderErrorCode`，仅 rejected 时有值）。 */
  reasonCode: string;

  constructor(clientOrderId: string, orderId: string, status: OrderStatus, code: string, ts: number,
    reasonCode?: string) {
    this.clientOrderId = clientOrderId;
    this.orderId = orderId;
    this.status = status;
    this.code = code;
    this.ts = ts;
    this.reasonCode = reasonCode !== undefined ? reasonCode : '';
  }
}

/** 委托行（M10-4 / AC-115）：列表与详情共用。 */
export class OrderItem {
  clientOrderId: string;
  orderId: string;
  /** 下单账户（撤单/成交记账要用，M10 增）。 */
  accountId: string;
  code: string;
  name: string;
  side: OrderSide;
  price: number;
  qty: number;
  filledQty: number;
  state: OrderState;
  createdAt: number;
  updatedAt: number;
  /** 废单/拒单原因码（`OrderErrorCode`，空串表示无）。 */
  reasonCode: string;

  constructor(clientOrderId: string, orderId: string, accountId: string, code: string, name: string,
    side: OrderSide, price: number, qty: number, filledQty: number, state: OrderState,
    createdAt: number, updatedAt: number, reasonCode?: string) {
    this.clientOrderId = clientOrderId;
    this.orderId = orderId;
    this.accountId = accountId;
    this.code = code;
    this.name = name;
    this.side = side;
    this.price = price;
    this.qty = qty;
    this.filledQty = filledQty;
    this.state = state;
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
    this.reasonCode = reasonCode !== undefined ? reasonCode : '';
  }

  /** 未成交剩余量。 */
  remaining(): number {
    return Math.max(0, this.qty - this.filledQty);
  }
}

/** 列表查询（M10-4）：分页 20、可按状态过滤。 */
export class OrderQuery {
  /** `all` 或具体状态。 */
  state: string;
  page: number;
  size: number;
  code: string;

  constructor(page: number, size: number, state?: string, code?: string) {
    this.page = page;
    this.size = size;
    this.state = state !== undefined ? state : 'all';
    this.code = code !== undefined ? code : '';
  }
}

/** 列表分页结果。 */
export class OrderPage {
  items: OrderItem[];
  total: number;
  page: number;
  size: number;
  hasMore: boolean;

  constructor(items: OrderItem[], total: number, page: number, size: number, hasMore: boolean) {
    this.items = items;
    this.total = total;
    this.page = page;
    this.size = size;
    this.hasMore = hasMore;
  }
}

/** 撤单结果（M10-5）：幂等，重复撤同一单返回同结果。 */
export class CancelResult {
  clientOrderId: string;
  orderId: string;
  ok: boolean;
  state: OrderState;
  reasonCode: string;
  ts: number;

  constructor(clientOrderId: string, orderId: string, ok: boolean, state: OrderState,
    reasonCode: string, ts: number) {
    this.clientOrderId = clientOrderId;
    this.orderId = orderId;
    this.ok = ok;
    this.state = state;
    this.reasonCode = reasonCode;
    this.ts = ts;
  }
}

/**
 * 开户结果（M10-1）。
 * 本项目没有真实券商：`channel` 只有 `local`（本地开通模拟账户）；
 * 保留 `h5` 是为了将来接 H5 开户时只加不改。
 */
export class OpenAccountResult {
  ok: boolean;
  channel: string;
  reasonCode: string;

  constructor(ok: boolean, channel: string, reasonCode?: string) {
    this.ok = ok;
    this.channel = channel;
    this.reasonCode = reasonCode !== undefined ? reasonCode : '';
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
 *
 * M10 契约 v1.1（只加不改，全部可选）：
 * - `listOrders`  / `cancelOrder` / `openAccount` 供委托列表、撤单、开户引导使用；
 * - 缺失时 VM 走「暂不可用」文案（旧实现不受影响）。
 */
export interface TradeProvider {
  loadContext(code: string, source: TradeSource): Promise<TradeContext>;

  /** 登录（本地实现直接置登录态；接后端时走账号中心）。 */
  login(): Promise<void>;

  submit(draft: OrderDraft): Promise<OrderResult>;

  query(clientOrderId: string): Promise<OrderResult>;

  listOrders?(query: OrderQuery): Promise<OrderPage>;

  cancelOrder?(orderId: string, clientOrderId: string): Promise<CancelResult>;

  openAccount?(): Promise<OpenAccountResult>;
}
