/**
 * 视图层可用的详情类型出口（R-07：view 只吃 viewmodel 暴露的类型）。
 * view 不直接 import commons_data / repository，统一从这里取。
 */
export {
  CHART_PERIODS,
  ChartPeriod,
  ChartSelectionListener,
  ChartSeries,
  ChartStyle,
  Market,
  MpChartEngine,
  StockTag,
  TradeStatus,
  createChartEngine,
  isKlinePeriod
} from 'commons_data';
export { ValueTone } from '../repository/DetailFormat';
