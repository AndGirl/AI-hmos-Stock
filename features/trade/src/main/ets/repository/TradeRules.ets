import { AccountInfo, AuthSession, TradeStatus, Tradable } from 'commons_data';

/**
 * 交易规则（L2，纯函数，禁止中文）：门禁优先级、字段校验、价格/数量步进与钳制。
 * 设计 §5.4.2 / §5.4.3；文案映射在 TradeVM + 视图资源。
 */

/** 门禁判定顺序：登录 → 开户/权限 → 停牌/退市 → 断线 → 交易时段 → 资金。 */
export enum TradeGate {
  NeedLogin,
  NoAccount,
  Suspended,
  Delisted,
  Offline,
  ClosedSession,
  FundShort,
  Ready
}

export type OrderField = 'price' | 'qty';

export type OrderErrorCode =
  'price_empty' | 'price_above' | 'price_below' | 'qty_empty' | 'qty_lot' | 'qty_over';

export class FieldError {
  field: OrderField;
  code: OrderErrorCode;

  constructor(field: OrderField, code: OrderErrorCode) {
    this.field = field;
    this.code = code;
  }
}

/** 一手 = 100 股（本期只做主板整手，DEC-07-03）。 */
export const LOT_SIZE: number = 100;

export function roundPrice(value: number): number {
  return Math.round(value * 100) / 100;
}

export function clampPrice(value: number, limitDown: number, limitUp: number): number {
  if (value < limitDown) {
    return limitDown;
  }
  if (limitUp > 0 && value > limitUp) {
    return limitUp;
  }
  return value;
}

/** 可买 = 可用资金 / 委托价，向下取整到整手（价格变化后必须重算，FR-07.5）。 */
export function computeCanBuy(available: number, price: number): number {
  if (price <= 0 || available <= 0) {
    return 0;
  }
  return Math.floor(available / price / LOT_SIZE) * LOT_SIZE;
}

export function lotFloor(qty: number): number {
  return Math.floor(qty / LOT_SIZE) * LOT_SIZE;
}

/** 默认数量：一手；可买不足一手时为 0（主按钮因此禁用）。 */
export function defaultQty(canBuy: number): number {
  return canBuy >= LOT_SIZE ? LOT_SIZE : 0;
}

/** 默认价格：当前价 round 到两位，再钳制到涨跌停区间。 */
export function defaultPrice(last: number | null, prevClose: number | null, limitDown: number,
  limitUp: number): number {
  const base: number = last !== null ? last : (prevClose !== null ? prevClose : limitDown);
  return clampPrice(roundPrice(base), limitDown, limitUp);
}

export function stepPrice(current: number, delta: number, limitDown: number, limitUp: number): number {
  return clampPrice(roundPrice(current + delta * 0.01), limitDown, limitUp);
}

/** 数量步进：下限 100、上限可买；可买不足一手时归 0。 */
export function stepQty(current: number, delta: number, canBuy: number): number {
  if (canBuy < LOT_SIZE) {
    return 0;
  }
  const next: number = lotFloor(current + delta * LOT_SIZE);
  if (next < LOT_SIZE) {
    return LOT_SIZE;
  }
  return next > canBuy ? canBuy : next;
}

/** 手输数量：超可买回填为可买（向下取整到手），返回 value 与 corrected。 */
export class QtyCommit {
  value: number;
  corrected: boolean;

  constructor(value: number, corrected: boolean) {
    this.value = value;
    this.corrected = corrected;
  }
}

export function commitQtyValue(raw: number, canBuy: number): QtyCommit {
  if (!Number.isFinite(raw) || raw <= 0) {
    return new QtyCommit(0, false);
  }
  const value: number = Math.floor(raw);
  if (canBuy > 0 && value > canBuy) {
    return new QtyCommit(canBuy, true);
  }
  return new QtyCommit(value, false);
}

export function isTradingSession(status: TradeStatus): boolean {
  return status === 'open' || status === 'auction';
}

/** 门禁（设计 §5.4.2 原样）：入口只拦 未登录/未开户/停牌/退市，其余在弹窗内处理。 */
export function resolveGate(session: AuthSession, account: AccountInfo | null, tradable: Tradable,
  online: boolean): TradeGate {
  if (!session.loggedIn) {
    return TradeGate.NeedLogin;
  }
  if (account === null || !account.opened || !account.canTrade) {
    return TradeGate.NoAccount;
  }
  if (tradable.status === 'suspended') {
    return TradeGate.Suspended;
  }
  if (tradable.status === 'delisted') {
    return TradeGate.Delisted;
  }
  if (!online) {
    return TradeGate.Offline;
  }
  if (!isTradingSession(tradable.status)) {
    return TradeGate.ClosedSession;
  }
  if (computeCanBuy(account.available, tradable.last !== null ? tradable.last : 0) < LOT_SIZE) {
    return TradeGate.FundShort;
  }
  return TradeGate.Ready;
}

/**
 * 单一校验出口（FR-07.6）：点「买入」时才调用，返回顺序固定为 价格 → 数量。
 * 只返回错误码，文案在视图层映射。
 */
export function validateOrder(price: number, qty: number, limitUp: number, limitDown: number,
  canBuy: number): FieldError[] {
  const errors: FieldError[] = [];
  if (!Number.isFinite(price) || price <= 0) {
    errors.push(new FieldError('price', 'price_empty'));
  } else if (limitUp > 0 && price > limitUp) {
    errors.push(new FieldError('price', 'price_above'));
  } else if (limitDown > 0 && price < limitDown) {
    errors.push(new FieldError('price', 'price_below'));
  }
  if (!Number.isFinite(qty) || qty <= 0) {
    errors.push(new FieldError('qty', 'qty_empty'));
  } else if (qty % LOT_SIZE !== 0) {
    errors.push(new FieldError('qty', 'qty_lot'));
  } else if (qty > canBuy) {
    errors.push(new FieldError('qty', 'qty_over'));
  }
  return errors;
}
