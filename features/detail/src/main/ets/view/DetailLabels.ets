import { AppColor } from 'commons_ui';
import { ChartPeriod, Market, StockTag, TradeStatus, ValueTone } from '../viewmodel/DetailExports';
import { MetricKey } from '../viewmodel/DetailVM';

/** 数值方向 → 主题色（涨红 / 跌绿 / 平灰 / 空值主文色）。 */
export function toneColor(tone: ValueTone): Resource {
  if (tone === 'up') {
    return AppColor.priceUp;
  }
  if (tone === 'down') {
    return AppColor.priceDown;
  }
  if (tone === 'flat') {
    return AppColor.priceFlat;
  }
  return AppColor.textPrimary;
}

export function metricLabel(key: MetricKey): Resource {
  switch (key) {
    case 'open':
      return $r('app.string.detail_metric_open');
    case 'prevClose':
      return $r('app.string.detail_metric_prev_close');
    case 'turnover':
      return $r('app.string.detail_metric_turnover');
    case 'high':
      return $r('app.string.detail_metric_high');
    case 'low':
      return $r('app.string.detail_metric_low');
    case 'pe':
      return $r('app.string.detail_metric_pe');
    case 'volume':
      return $r('app.string.detail_metric_volume');
    case 'amount':
      return $r('app.string.detail_metric_amount');
    case 'marketCap':
      return $r('app.string.detail_metric_market_cap');
    case 'amplitude':
      return $r('app.string.detail_metric_amplitude');
    case 'volumeRatio':
      return $r('app.string.detail_metric_volume_ratio');
    default:
      return $r('app.string.detail_metric_float_cap');
  }
}

export function statusLabel(status: TradeStatus): Resource {
  switch (status) {
    case 'pre':
      return $r('app.string.detail_status_pre');
    case 'auction':
      return $r('app.string.detail_status_auction');
    case 'open':
      return $r('app.string.detail_status_open');
    case 'lunch':
      return $r('app.string.detail_status_lunch');
    case 'suspended':
      return $r('app.string.detail_status_suspended');
    case 'delisted':
      return $r('app.string.detail_status_delisted');
    default:
      return $r('app.string.detail_status_closed');
  }
}

export function marketLabel(market: Market): Resource {
  if (market === 'SZ') {
    return $r('app.string.detail_market_sz');
  }
  if (market === 'BJ') {
    return $r('app.string.detail_market_bj');
  }
  return $r('app.string.detail_market_sh');
}

export function tagLabel(tag: StockTag): Resource {
  if (tag === 'rzrq') {
    return $r('app.string.detail_tag_rzrq');
  }
  if (tag === 'large') {
    return $r('app.string.detail_tag_large');
  }
  if (tag === 'new') {
    return $r('app.string.watch_tag_new');
  }
  if (tag === 'suspended') {
    return $r('app.string.watch_tag_suspended');
  }
  return $r('app.string.detail_tag_hsgt');
}

export function periodLabel(period: ChartPeriod): Resource {
  switch (period) {
    case 'five':
      return $r('app.string.detail_period_five');
    case 'd':
      return $r('app.string.detail_period_d');
    case 'w':
      return $r('app.string.detail_period_w');
    case 'm':
      return $r('app.string.detail_period_m');
    case 'q':
      return $r('app.string.detail_period_q');
    case 'hy':
      return $r('app.string.detail_period_hy');
    case 'y':
      return $r('app.string.detail_period_y');
    default:
      return $r('app.string.detail_period_timeline');
  }
}
