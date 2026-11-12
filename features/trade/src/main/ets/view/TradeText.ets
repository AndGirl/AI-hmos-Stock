import {
  TradeBlockCode,
  TradeFailCode,
  TradeFieldErrorCode,
  TradeHintCode,
  TradeQueryStatus,
  TradeToastCode
} from '../viewmodel/TradeVM';

/**
 * 交易文案映射（视图层唯一出口）：VM 只给 code，资源在这里组装（i18n 单一来源）。
 * 返回 '' 表示不展示。
 */
export function fieldErrorText(code: TradeFieldErrorCode, limitUpText: string, limitDownText: string,
  canBuyText: string): ResourceStr {
  if (code === 'price_empty') {
    return $r('app.string.trade_err_price_empty');
  }
  if (code === 'price_above') {
    return $r('app.string.trade_err_price_above', limitUpText);
  }
  if (code === 'price_below') {
    return $r('app.string.trade_err_price_below', limitDownText);
  }
  if (code === 'qty_empty') {
    return $r('app.string.trade_err_qty_empty');
  }
  if (code === 'qty_lot') {
    return $r('app.string.trade_err_qty_lot');
  }
  if (code === 'qty_over') {
    return $r('app.string.trade_err_qty_over', canBuyText);
  }
  return '';
}

export function hintText(code: TradeHintCode, limitUpText: string, limitDownText: string,
  canBuyText: string): ResourceStr {
  if (code === 'price_up') {
    return $r('app.string.trade_hint_price_up', limitUpText);
  }
  if (code === 'price_down') {
    return $r('app.string.trade_hint_price_down', limitDownText);
  }
  if (code === 'qty_can_buy') {
    return $r('app.string.trade_hint_qty_can_buy', canBuyText);
  }
  return '';
}

export function blockText(code: TradeBlockCode, canBuyText: string): ResourceStr {
  if (code === 'offline') {
    return $r('app.string.trade_block_offline');
  }
  if (code === 'closed') {
    return $r('app.string.trade_block_closed');
  }
  if (code === 'fund_short') {
    return $r('app.string.trade_block_fund_short', canBuyText);
  }
  return '';
}

export function failText(code: TradeFailCode): ResourceStr {
  if (code === 'fund_short') {
    return $r('app.string.trade_fail_fund_short');
  }
  if (code === 'price_limit') {
    return $r('app.string.trade_fail_price_limit');
  }
  if (code === 'closed') {
    return $r('app.string.trade_fail_closed');
  }
  if (code === 'risk') {
    return $r('app.string.trade_fail_risk');
  }
  return '';
}

export function toastText(code: TradeToastCode, orderId: string): ResourceStr {
  if (code === 'no_account') {
    return $r('app.string.trade_toast_no_account');
  }
  if (code === 'suspended') {
    return $r('app.string.trade_toast_suspended');
  }
  if (code === 'delisted') {
    return $r('app.string.trade_toast_delisted');
  }
  if (code === 'submitting') {
    return $r('app.string.trade_toast_submitting');
  }
  if (code === 'load_failed') {
    return $r('app.string.trade_toast_load_failed');
  }
  if (code === 'success') {
    return $r('app.string.trade_toast_success', orderId);
  }
  return '';
}

export function queryStatusText(status: TradeQueryStatus): ResourceStr {
  if (status === 'accepted') {
    return $r('app.string.trade_query_accepted');
  }
  if (status === 'not_found') {
    return $r('app.string.trade_query_not_found');
  }
  return '';
}
