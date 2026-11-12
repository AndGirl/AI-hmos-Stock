/**
 * 交易展示格式（L2）：价格恒两位小数、数量整数、查询时间本地化。
 * 不产出中文文案。
 */
export const PRICE_ZERO: string = '0.00';

export function formatPrice(value: number): string {
  if (!Number.isFinite(value)) {
    return PRICE_ZERO;
  }
  return value.toFixed(2);
}

export function formatQty(value: number): string {
  if (!Number.isFinite(value)) {
    return '0';
  }
  return Math.round(value).toString();
}

export function formatQueryTime(ts: number): string {
  const d: Date = new Date(ts);
  const month: string = pad2(d.getMonth() + 1);
  const day: string = pad2(d.getDate());
  const hour: string = pad2(d.getHours());
  const minute: string = pad2(d.getMinutes());
  const second: string = pad2(d.getSeconds());
  return month + '-' + day + ' ' + hour + ':' + minute + ':' + second;
}

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

/** 幂等键：进入弹窗生成一次，流程内复用、成功后作废（INV-T1）。 */
export class TradeId {
  private static seq: number = 0;

  static next(): string {
    TradeId.seq++;
    const stamp: string = Date.now().toString(36).toUpperCase();
    return 'CO' + stamp + TradeId.seq.toString();
  }
}
