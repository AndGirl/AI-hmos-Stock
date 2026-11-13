/**
 * 委托列表文案映射（M10-4/M10-5）：VM 只给枚举/码，资源与数字格式在这里统一。
 */
export function stateText(state: string): ResourceStr {
  if (state === 'pending') {
    return $r('app.string.trade_order_state_pending');
  }
  if (state === 'accepted') {
    return $r('app.string.trade_order_state_accepted');
  }
  if (state === 'partial') {
    return $r('app.string.trade_order_state_partial');
  }
  if (state === 'filled') {
    return $r('app.string.trade_order_state_filled');
  }
  if (state === 'canceled') {
    return $r('app.string.trade_order_state_canceled');
  }
  if (state === 'rejected') {
    return $r('app.string.trade_order_state_rejected');
  }
  return $r('app.string.trade_order_state_unknown');
}

export function sideText(side: string): ResourceStr {
  return side === 'sell' ? $r('app.string.trade_order_side_sell') : $r('app.string.trade_order_side_buy');
}

export function filterText(filter: string): ResourceStr {
  if (filter === 'all') {
    return $r('app.string.trade_orders_filter_all');
  }
  return stateText(filter);
}

/** 错误/失败原因码 → 文案（AC-114：未知码也要有兜底文案）。 */
export function reasonText(code: string): ResourceStr {
  if (code === 'fund_short') {
    return $r('app.string.trade_reason_fund_short');
  }
  if (code === 'qty_short') {
    return $r('app.string.trade_reason_qty_short');
  }
  if (code === 'price_limit') {
    return $r('app.string.trade_reason_price_limit');
  }
  if (code === 'closed') {
    return $r('app.string.trade_reason_closed');
  }
  if (code === 'suspended') {
    return $r('app.string.trade_reason_suspended');
  }
  if (code === 'delisted') {
    return $r('app.string.trade_reason_delisted');
  }
  if (code === 'no_permission') {
    return $r('app.string.trade_reason_no_permission');
  }
  if (code === 'risk') {
    return $r('app.string.trade_reason_risk');
  }
  if (code === 'busy') {
    return $r('app.string.trade_reason_busy');
  }
  if (code === 'filled') {
    return $r('app.string.trade_order_state_filled');
  }
  if (code === 'canceled') {
    return $r('app.string.trade_order_state_canceled');
  }
  return $r('app.string.trade_reason_unknown');
}

/** 价格两位小数（与交易/行情同口径）。 */
export function priceText(value: number): string {
  return value.toFixed(2);
}

export function qtyText(value: number): string {
  return `${value}`;
}

/** 「成交 500/1000」进度文案。 */
export function progressText(filledQty: number, qty: number): string {
  return `成交 ${filledQty}/${qty}`;
}
