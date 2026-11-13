import { TradeStatus } from '../model/QuoteModels';
import { OrderSide, OrderState } from '../model/TradeModels';

/**
 * 本地假撮合规则（M10-2 / AC-113~116）。
 *
 * 为什么是纯函数：AC-114~116 的断言都是「给定委托 + 给定行情 + 给定账户 → 期望状态/错误码」，
 * 只有纯函数能穷举组合（同一套路见 M6 `SearchRules`、M9 `LimitRules`）。
 *
 * 撮合模型（已确认口径）：**分阶段 + 行情联动**
 * - 买：委托价 ≥ 最新价 → 可成交；卖：委托价 ≤ 最新价 → 可成交；
 * - 首次成交先吃一半（整手，至少 1 手），剩余挂单等下一拍；
 * - 剩余 ≤ 1 手时一次吃完 → `filled`；否则 `partial`；
 * - 未触及 → `pending`（待报），由 provider 在下一拍转 `accepted` 并继续撮合。
 *
 * 全程不使用随机数：同一委托 + 同一行情永远得到同一结果（可重放、可单测）。
 */

/** 一手 = 100 股（与 `TradeRules.LOT_SIZE` 同口径）。 */
export const MATCH_LOT: number = 100;

/** 撮合参考行情（只取用得到的字段，避免纯函数依赖完整快照）。 */
export class MatchQuote {
  status: TradeStatus;
  last: number | null;
  limitUp: number;
  limitDown: number;

  constructor(status: TradeStatus, last: number | null, limitUp: number, limitDown: number) {
    this.status = status;
    this.last = last;
    this.limitUp = limitUp;
    this.limitDown = limitDown;
  }
}

/** 撮合参考账户（可买 = available；可卖 = sellable）。 */
export class MatchAccount {
  loggedIn: boolean;
  opened: boolean;
  available: number;
  sellable: number;

  constructor(loggedIn: boolean, opened: boolean, available: number, sellable: number) {
    this.loggedIn = loggedIn;
    this.opened = opened;
    this.available = available;
    this.sellable = sellable;
  }
}

/** 待撮合委托（可变部分）。 */
export class MatchOrder {
  code: string;
  side: OrderSide;
  price: number;
  qty: number;
  filledQty: number;

  constructor(code: string, side: OrderSide, price: number, qty: number, filledQty: number) {
    this.code = code;
    this.side = side;
    this.price = price;
    this.qty = qty;
    this.filledQty = filledQty;
  }

  remaining(): number {
    return Math.max(0, this.qty - this.filledQty);
  }
}

export type MatchDecision = 'fill' | 'partial' | 'pending' | 'reject';

/** 一次撮合判定结果。 */
export class MatchOutcome {
  decision: MatchDecision;
  state: OrderState;
  /** 本次成交数量（0 表示未成交）。 */
  fillQty: number;
  /** 拒单原因码（`OrderErrorCode`，空串表示无）。 */
  reasonCode: string;

  constructor(decision: MatchDecision, state: OrderState, fillQty: number, reasonCode: string) {
    this.decision = decision;
    this.state = state;
    this.fillQty = fillQty;
    this.reasonCode = reasonCode;
  }
}

function reject(reasonCode: string): MatchOutcome {
  return new MatchOutcome('reject', 'rejected', 0, reasonCode);
}

/** 是否可交易时段（与行情侧 `TradingSession` 的 open/auction 判定一致）。 */
export function matchableSession(status: TradeStatus): boolean {
  return status === 'open' || status === 'auction';
}

/**
 * 提交前校验（拒单判定），返回原因码；空串表示通过。
 * 顺序：登录 → 开户 → 停牌/退市 → 时段 → 价格合法 → 价格区间 → 资金/持仓。
 */
export function precheck(order: MatchOrder, quote: MatchQuote, account: MatchAccount): string {
  if (!account.loggedIn) {
    return 'no_permission';
  }
  if (!account.opened) {
    return 'no_permission';
  }
  if (quote.status === 'suspended') {
    return 'suspended';
  }
  if (quote.status === 'delisted') {
    return 'delisted';
  }
  if (!matchableSession(quote.status)) {
    return 'closed';
  }
  if (!(order.price > 0) || order.qty <= 0 || order.qty % MATCH_LOT !== 0) {
    return 'risk';
  }
  if (order.price > quote.limitUp) {
    return 'price_limit';
  }
  if (order.price < quote.limitDown) {
    return 'price_limit';
  }
  if (order.side === 'buy') {
    if (order.price * order.qty > account.available) {
      return 'fund_short';
    }
  } else if (order.qty > account.sellable) {
    return 'qty_short';
  }
  return '';
}

/**
 * 撮合一次：先过 `precheck`，再按行情判定成交/部成/挂单。
 *
 * - `fill`    全部成交 → `filled`
 * - `partial` 部分成交 → `partial`
 * - `pending` 未触及 → `pending`
 * - `reject`  不满足条件 → `rejected` + 原因码
 */
export function matchOnce(order: MatchOrder, quote: MatchQuote, account: MatchAccount): MatchOutcome {
  const reason: string = precheck(order, quote, account);
  if (reason.length > 0) {
    return reject(reason);
  }
  const last: number | null = quote.last;
  if (last === null || !(last > 0)) {
    // 无最新价（未开盘/异常）：挂单等下一拍，不算拒单。
    return new MatchOutcome('pending', 'pending', 0, '');
  }
  const remaining: number = order.remaining();
  if (remaining <= 0) {
    return new MatchOutcome('fill', 'filled', 0, '');
  }
  const crossed: boolean = order.side === 'buy' ? order.price >= last : order.price <= last;
  if (!crossed) {
    return new MatchOutcome('pending', 'pending', 0, '');
  }
  let fillQty: number = remaining;
  if (order.filledQty === 0 && remaining > MATCH_LOT) {
    // 首次只吃一半（整手、至少 1 手）：让「部成」可见，也为撤销留出空间。
    const half: number = Math.floor(remaining / 2 / MATCH_LOT) * MATCH_LOT;
    fillQty = Math.max(MATCH_LOT, half);
  }
  if (fillQty >= remaining) {
    return new MatchOutcome('fill', 'filled', remaining, '');
  }
  return new MatchOutcome('partial', 'partial', fillQty, '');
}

/**
 * 成交后的账户变化（买：扣资金、增持仓；卖：增资金、减持仓）。
 * 纯函数，返回新值，便于单测与「一次性算清」。
 */
export class AccountDelta {
  available: number;
  sellable: number;

  constructor(available: number, sellable: number) {
    this.available = available;
    this.sellable = sellable;
  }
}

export function applyFill(side: OrderSide, price: number, fillQty: number, account: MatchAccount): AccountDelta {
  const amount: number = round2(price * fillQty);
  if (side === 'buy') {
    return new AccountDelta(round2(account.available - amount), account.sellable + fillQty);
  }
  return new AccountDelta(round2(account.available + amount), Math.max(0, account.sellable - fillQty));
}

/** 金额两位小数（与交易/行情同口径）。 */
export function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

/**
 * 撤单判定：只有 待报/已报/部成 可撤；终态重复撤单返回 `ok=false` + 当前状态（幂等，不抛错）。
 */
export class CancelDecision {
  ok: boolean;
  reasonCode: string;

  constructor(ok: boolean, reasonCode: string) {
    this.ok = ok;
    this.reasonCode = reasonCode;
  }
}

export function canCancel(state: OrderState): CancelDecision {
  if (state === 'pending' || state === 'accepted' || state === 'partial') {
    return new CancelDecision(true, '');
  }
  if (state === 'filled') {
    return new CancelDecision(false, 'filled');
  }
  if (state === 'canceled') {
    return new CancelDecision(false, 'canceled');
  }
  return new CancelDecision(false, 'not_cancelable');
}
