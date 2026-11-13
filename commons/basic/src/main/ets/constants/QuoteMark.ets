/**
 * 涨跌方向符号（M12-3）：除颜色外的第二重区分手段，覆盖色弱用户（AC-123）。
 * 口径：只加在「涨跌额 / 涨跌幅」等涨跌数值前；最新价、盘口价格本身不加；
 * 平盘（0.00）、停牌/新股的空值（--）不加。符号用较小字号 Span 渲染，避免挤出固定列宽。
 */
export const ARROW_UP: string = '▲';
export const ARROW_DOWN: string = '▼';

/** 自选行/卡片/列表使用的方向值：1 涨 / -1 跌 / 0 平。 */
export function arrowOfDir(dir: number): string {
  if (dir > 0) {
    return ARROW_UP;
  }
  if (dir < 0) {
    return ARROW_DOWN;
  }
  return '';
}

/** 详情页 ValueTone（'up' / 'down' / 'flat' / 'none'）。 */
export function arrowOfTone(tone: string): string {
  if (tone === 'up') {
    return ARROW_UP;
  }
  if (tone === 'down') {
    return ARROW_DOWN;
  }
  return '';
}

/** 原始涨跌数值：空值/0 不加符号。 */
export function arrowOfValue(value: number | null | undefined): string {
  if (value === null || value === undefined || value === 0) {
    return '';
  }
  return value > 0 ? ARROW_UP : ARROW_DOWN;
}
