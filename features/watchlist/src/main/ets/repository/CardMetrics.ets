/**
 * 卡片几何（M8-1）：断点列数 + 卡宽/间距/内边距的唯一实现。
 * 依据：计划 §4.4-G4（sm2/md3/lg4/xl5；间距 sm12/md12/lg16/xl16；页内边距 16；卡高自适应 min 132vp）。
 *
 * 三条硬约束（AC-100）：
 * 1. 任何断点、任何字号都**不得横向滚动**（卡宽按容器宽反算，永远放得下）；
 * 2. 字号放大只**降列**（5→4→3→2，下限 2），不缩字号、不截断；
 * 3. 卡宽低于 `CARD_FLOOR_W` 视为真挤压（只有极端窄窗才会触发），由 `layoutViolations` 报出。
 *
 * 纯函数、不依赖 UI，可直接被 Hypium Local Test 覆盖。
 */

export interface CardMetrics {
  columns: number;
  gap: number;
  padding: number;
  cardW: number;
  /** 去掉左右内边距后的可用宽。 */
  contentWidth: number;
  /** 卡片最小高（随字号放大，避免 1.45× 截断）。 */
  minCardH: number;
}

export const CARD_PADDING: number = 16;
/** 基准字号下的目标最小卡宽：低于该值就降一列（160 是 2 列指标 + 20sp 价格的下限）。 */
export const CARD_MIN_W: number = 160;
/** 真挤压下限：低于此宽才算违规（sm 2 列 + 1.45× 属于「降列到底后允许卡高增长」）。 */
export const CARD_FLOOR_W: number = 120;
export const CARD_MIN_H: number = 132;
export const CARD_MIN_COLUMNS: number = 2;
export const CARD_MAX_COLUMNS: number = 5;
export const CARD_GAP_NARROW: number = 12;
export const CARD_GAP_WIDE: number = 16;
/** 指标区用双列所需的最小卡宽；不足则单列（标签左、值右），避免 1.45× 挤压。 */
export const CARD_METRIC_TWO_COL_MIN: number = 200;
/** 指标池固定 6 项（今开/最高/最低/成交额/换手率/量比），sm 卡降为前 4 项。 */
export const CARD_METRIC_MAX: number = 6;
export const CARD_METRIC_SM: number = 4;

/** 断点基准列数（D53：sm2 / md3 / lg4 / xl5）。 */
export function baseCardColumns(bp: string): number {
  if (bp === 'sm') {
    return 2;
  }
  if (bp === 'md') {
    return 3;
  }
  if (bp === 'lg') {
    return 4;
  }
  return CARD_MAX_COLUMNS;
}

/** 间距只由最终列数决定：≤3 列用 12，4~5 列用 16（恰好覆盖 sm12/md12/lg16/xl16）。 */
export function cardGapOf(columns: number): number {
  return columns <= 3 ? CARD_GAP_NARROW : CARD_GAP_WIDE;
}

/** 按容器宽反算卡宽（向下取整，保证永不溢出）。 */
export function computeCardWidth(viewport: number, columns: number, gap: number): number {
  const safeColumns: number = Math.max(1, Math.round(columns));
  const usable: number = Math.round(viewport) - CARD_PADDING * 2 - gap * (safeColumns - 1);
  if (usable <= 0) {
    return 0;
  }
  return Math.floor(usable / safeColumns);
}

/**
 * 最终列数：从断点基准列数开始，卡宽不满足 `CARD_MIN_W × fontScale` 就降一列，下限 2。
 * 例（1.45×）：md 3→2、lg 4→3、xl 5 保持、sm 2 保持（到底后只允许卡高增长）。
 */
export function computeCardColumns(bp: string, viewport: number, fontScale: number): number {
  const scale: number = fontScale > 0 ? fontScale : 1;
  const minWidth: number = CARD_MIN_W * scale;
  let columns: number = baseCardColumns(bp);
  while (columns > CARD_MIN_COLUMNS) {
    const gap: number = cardGapOf(columns);
    if (computeCardWidth(viewport, columns, gap) >= minWidth) {
      break;
    }
    columns--;
  }
  return columns;
}

/** 几何结果（列数由调用方传入，通常来自 `computeCardColumns`）。 */
export function computeCardMetrics(viewport: number, columns: number, fontScale: number): CardMetrics {
  const safeColumns: number = Math.min(CARD_MAX_COLUMNS, Math.max(CARD_MIN_COLUMNS, Math.round(columns)));
  const gap: number = cardGapOf(safeColumns);
  const scale: number = fontScale > 0 ? fontScale : 1;
  return {
    columns: safeColumns,
    gap: gap,
    padding: CARD_PADDING,
    cardW: computeCardWidth(viewport, safeColumns, gap),
    contentWidth: Math.max(0, Math.round(viewport) - CARD_PADDING * 2),
    minCardH: Math.round(CARD_MIN_H * scale)
  };
}

/** 指标条数：sm 卡 4 项，md 及以上 6 项（不随降列变化）。 */
export function metricCountOf(bp: string): number {
  return bp === 'sm' ? CARD_METRIC_SM : CARD_METRIC_MAX;
}

/** 指标区列数：卡宽足够就用 2 列 × 3 行，否则单列（标签左 / 值右）。 */
export function metricColumnsOf(cardW: number): number {
  return cardW >= CARD_METRIC_TWO_COL_MIN ? 2 : 1;
}

/**
 * 布局自检：返回空数组表示合规。用于 4 断点 × 3 字号 = 12 组断言（AC-100）。
 * 只断言「放得下 + 列数合法 + 不是真挤压」，不把 sm 1.45× 的「降列到底」判成违规。
 */
export function layoutViolations(viewport: number, columns: number, fontScale: number): string[] {
  const issues: string[] = [];
  if (columns < CARD_MIN_COLUMNS || columns > CARD_MAX_COLUMNS) {
    issues.push(`columns_out_of_range:${columns}`);
  }
  const metrics: CardMetrics = computeCardMetrics(viewport, columns, fontScale);
  if (metrics.cardW <= 0) {
    issues.push('no_room');
    return issues;
  }
  const totalWidth: number =
    metrics.padding * 2 + metrics.cardW * metrics.columns + metrics.gap * (metrics.columns - 1);
  if (totalWidth > Math.round(viewport)) {
    issues.push(`horizontal_overflow:${totalWidth}>${Math.round(viewport)}`);
  }
  if (metrics.cardW < CARD_FLOOR_W) {
    issues.push(`card_too_narrow:${metrics.cardW}`);
  }
  return issues;
}
