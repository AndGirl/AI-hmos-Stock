/**
 * 详情页数值格式化（纯函数，无 UI 依赖）。
 * 单位口径与自选列表保持一致（万手 / 万 / 亿），空值统一 `--`。
 */

export const DASH: string = '--';

/** 数值方向：涨 / 跌 / 平 / 无色（停牌、空值）。 */
export type ValueTone = 'up' | 'down' | 'flat' | 'none';

function pad2(value: number): string {
  return value < 10 ? '0' + value : '' + value;
}

function isNil(value: number | null | undefined): boolean {
  return value === null || value === undefined;
}

export function formatPrice(value: number | null | undefined): string {
  if (isNil(value)) {
    return DASH;
  }
  return (value as number).toFixed(2);
}

/** 带符号数值：+1.23 / -1.23；平盘不加正号。 */
export function formatSigned(value: number | null | undefined, suffix: string): string {
  if (isNil(value)) {
    return DASH;
  }
  const num: number = value as number;
  const sign: string = num > 0 ? '+' : '';
  return sign + num.toFixed(2) + suffix;
}

export function formatPercent(value: number | null | undefined): string {
  if (isNil(value)) {
    return DASH;
  }
  return (value as number).toFixed(2) + '%';
}

/** 成交量：手 → 万手 / 亿手。 */
export function formatVolume(value: number | null | undefined): string {
  if (isNil(value)) {
    return DASH;
  }
  const num: number = value as number;
  if (num >= 100000000) {
    return (num / 100000000).toFixed(2) + '亿手';
  }
  if (num >= 10000) {
    return (num / 10000).toFixed(2) + '万手';
  }
  return Math.round(num) + '手';
}

/** 成交额 / 市值：元 → 万 / 亿 / 万亿。 */
export function formatAmount(value: number | null | undefined): string {
  if (isNil(value)) {
    return DASH;
  }
  const num: number = value as number;
  if (num >= 1000000000000) {
    return (num / 1000000000000).toFixed(2) + '万亿';
  }
  if (num >= 100000000) {
    return (num / 100000000).toFixed(2) + '亿';
  }
  return (num / 10000).toFixed(0) + '万';
}

/** 快照时间：MM-DD HH:mm:ss（只用行情时间，不读设备时钟）。 */
export function formatSnapshotTime(time: number): string {
  if (time <= 0) {
    return DASH;
  }
  const date: Date = new Date(time);
  return pad2(date.getMonth() + 1) + '-' + pad2(date.getDate()) + ' ' +
    pad2(date.getHours()) + ':' + pad2(date.getMinutes()) + ':' + pad2(date.getSeconds());
}

/** 逐笔时间：HH:mm:ss。 */
export function formatClock(time: number): string {
  if (time <= 0) {
    return DASH;
  }
  const date: Date = new Date(time);
  return pad2(date.getHours()) + ':' + pad2(date.getMinutes()) + ':' + pad2(date.getSeconds());
}

/** 五日 / 跨日刻度：MM-DD。 */
export function formatMonthDay(time: number): string {
  if (time <= 0) {
    return DASH;
  }
  const date: Date = new Date(time);
  return pad2(date.getMonth() + 1) + '-' + pad2(date.getDate());
}

/** K 线读数：YYYY-MM-DD。 */
export function formatDate(time: number): string {
  if (time <= 0) {
    return DASH;
  }
  const date: Date = new Date(time);
  return '' + date.getFullYear() + '-' + pad2(date.getMonth() + 1) + '-' + pad2(date.getDate());
}

/** 相对昨收着色（FR-06.8：五档价格按昨收，不按相邻档）。 */
export function toneOf(value: number | null | undefined, base: number | null | undefined): ValueTone {
  if (isNil(value) || isNil(base)) {
    return 'none';
  }
  const num: number = value as number;
  const ref: number = base as number;
  if (num > ref) {
    return 'up';
  }
  if (num < ref) {
    return 'down';
  }
  return 'flat';
}

/** 主动买卖着色：买红、卖绿、平灰。 */
export function toneOfDirection(direction: string): ValueTone {
  if (direction === 'buy') {
    return 'up';
  }
  if (direction === 'sell') {
    return 'down';
  }
  return 'flat';
}
