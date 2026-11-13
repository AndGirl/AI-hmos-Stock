/**
 * 持仓展示格式（M11-2，View 层）：数字格式与资源映射都放这里，VM 只给原始值。
 * 约定：无值一律 `--`（与行情/卡片同口径）；金额千分位；涨跌带符号。
 */

export const DASH: string = '--';

/** 涨跌色档：View 据此映射 AppColor.priceUp / priceDown / priceFlat。 */
export type Tone = 'up' | 'down' | 'flat';

export function toneOf(value: number | null): Tone {
  if (value === null || value === 0) {
    return 'flat';
  }
  return value > 0 ? 'up' : 'down';
}

/** 千分位（只处理整数部分，保留符号与小数）。 */
function grouped(text: string): string {
  const negative: boolean = text.startsWith('-');
  const body: string = negative ? text.substring(1) : text;
  const dot: number = body.indexOf('.');
  const intPart: string = dot >= 0 ? body.substring(0, dot) : body;
  const decPart: string = dot >= 0 ? body.substring(dot) : '';
  let out: string = '';
  let count: number = 0;
  for (let i = intPart.length - 1; i >= 0; i--) {
    out = intPart.charAt(i) + out;
    count++;
    if (count % 3 === 0 && i > 0) {
      out = ',' + out;
    }
  }
  return (negative ? '-' : '') + out + decPart;
}

/** 金额（两位小数 + 千分位）；null → `--`。 */
export function moneyText(value: number | null): string {
  if (value === null || !Number.isFinite(value)) {
    return DASH;
  }
  return grouped(value.toFixed(2));
}

/** 带符号金额：+1,234.00 / -56.70 / 0.00。 */
export function signedMoneyText(value: number | null): string {
  if (value === null || !Number.isFinite(value)) {
    return DASH;
  }
  const abs: number = Math.abs(value);
  return (value > 0 ? '+' : (value < 0 ? '-' : '')) + grouped(abs.toFixed(2));
}

/** 价格（两位小数）；null → `--`。 */
export function priceText(value: number | null): string {
  if (value === null || !Number.isFinite(value)) {
    return DASH;
  }
  return value.toFixed(2);
}

/** 百分比：12.00% / +12.00%；null → `--`。 */
export function percentText(value: number | null, signed: boolean): string {
  if (value === null || !Number.isFinite(value)) {
    return DASH;
  }
  const abs: number = Math.abs(value);
  const sign: string = signed ? (value > 0 ? '+' : (value < 0 ? '-' : '')) : '';
  return sign + abs.toFixed(2) + '%';
}

/** 数量（整数 + 千分位）。 */
export function qtyText(value: number): string {
  if (!Number.isFinite(value)) {
    return '0';
  }
  return grouped(Math.round(value).toString());
}

/** 排序字段文案（AC-119：市值 / 盈亏 / 盈亏比）。 */
export function sortKeyText(key: string): Resource {
  if (key === 'pnl') {
    return $r('app.string.position_sort_pnl');
  }
  if (key === 'pnlRatio') {
    return $r('app.string.position_sort_ratio');
  }
  return $r('app.string.position_sort_value');
}

/** 排序方向箭头：只做视觉提示；读屏文案由 View 组合（当前方向 + 字段名）。 */
export function sortArrowText(dir: string): string {
  if (dir === 'desc') {
    return '↓';
  }
  if (dir === 'asc') {
    return '↑';
  }
  return '';
}
