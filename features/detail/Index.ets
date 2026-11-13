/**
 * 个股详情（M2 实现）。对外唯一入口：跨模块只允许 import from 'detail'（R-06）。
 */
export { DetailContent } from './src/main/ets/view/DetailContent';
export { showDetailActionMenu } from './src/main/ets/view/DetailActions';
export { DetailAction, DetailMode, DetailTier } from './src/main/ets/viewmodel/DetailVM';
export { ChartPeriod } from './src/main/ets/viewmodel/DetailExports';
export {
  DETAIL_BLOCK_HEIGHT,
  LANDSCAPE_SPLIT_RATIO,
  landscapeChartHeight,
  landscapeLeftWidth,
  landscapeMetricColumns,
  landscapeMetricRows,
  landscapeRightWidth
} from './src/main/ets/view/DetailLayout';
export { detailSubscriptionStats } from './src/main/ets/repository/DetailRepository';
