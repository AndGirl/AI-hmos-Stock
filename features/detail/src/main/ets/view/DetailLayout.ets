/**
 * 详情页版式常量与横屏几何（M12-1）。
 * 纯函数：只依赖视口宽高与字号，便于 Local Test 断言；view 层不重复算。
 */
export const DETAIL_BLOCK_HEIGHT: number = 312;

/**
 * 右栏「全量形态」宽度阈值（§10-83）：xl 平板右栏（≥657vp）按设计稿保留通栏动作栏与内容 Tab；
 * 窄嵌入（<600vp）与多窗实例仍走紧凑版（⋯ 菜单、无动作栏、无交易入口）。
 */
export const PANE_FULL_MIN_VP: number = 600;

/** 横屏左右分栏比例（G-7 兜底 62 / 38）。 */
export const LANDSCAPE_SPLIT_RATIO: number = 0.62;
export const LANDSCAPE_CHART_MIN_VP: number = 160;
export const LANDSCAPE_CHART_MAX_VP: number = 260;
export const LANDSCAPE_LEFT_MIN_VP: number = 320;
export const LANDSCAPE_RIGHT_MIN_VP: number = 220;

/** 横屏左列宽（报价头 + 周期 + 图表 + 指标），保底 320vp。 */
export function landscapeLeftWidth(viewportWidth: number): number {
  return Math.max(LANDSCAPE_LEFT_MIN_VP, Math.round(viewportWidth * LANDSCAPE_SPLIT_RATIO));
}

/** 横屏右列宽（盘口 + 明细），保底 220vp；左右之和不超过视口。 */
export function landscapeRightWidth(viewportWidth: number): number {
  const left: number = landscapeLeftWidth(viewportWidth);
  return Math.max(LANDSCAPE_RIGHT_MIN_VP, viewportWidth - left);
}

/**
 * 横屏图表区（价格 + 量能）高度：按视口高 34% 推导，限制在 160~260vp，
 * 保证手机横屏（约 360~420vp 高）不挤压、平板横屏不浪费。
 */
export function landscapeChartHeight(viewportHeight: number): number {
  const raw: number = Math.round(viewportHeight * 0.34);
  return Math.min(LANDSCAPE_CHART_MAX_VP, Math.max(LANDSCAPE_CHART_MIN_VP, raw));
}

/** 横屏指标列数：默认 6 列 × 2 行；1.3× 及以上降为 4 列 × 3 行避免截断。 */
export function landscapeMetricColumns(fontScale: number): number {
  return fontScale >= 1.3 ? 4 : 6;
}

/** 横屏指标行数：12 项 / 列数向上取整。 */
export function landscapeMetricRows(itemCount: number, columns: number): number {
  if (columns <= 0) {
    return itemCount;
  }
  return Math.ceil(itemCount / columns);
}
