/**
 * 数据能力层（M1 起接入契约、Mock、QuoteBus/QuoteCache）。
 * 唯一允许 new Provider 的地方是 DataServices（R-05）。
 */
export {
  ConnectionState,
  Market,
  QuoteError,
  QuoteErrorReason,
  QuoteListener,
  QuotePatch,
  QuoteProvider,
  QuoteSnapshot,
  QuoteSubscription,
  TradeStatus
} from './src/main/ets/model/QuoteModels';
export {
  CHART_PERIODS,
  ChartPeriod,
  ChartPoint,
  ChartSeries,
  DetailError,
  DetailErrorReason,
  DetailListener,
  DetailNews,
  DetailPatch,
  DetailProvider,
  DetailSnapshot,
  DetailSubscription,
  KLINE_MAX_COUNT,
  KLINE_PAGE_SIZE,
  OrderBook,
  OrderLevel,
  StockTag,
  Tick,
  TickDirection,
  TIMELINE_POINT_COUNT,
  isKlinePeriod
} from './src/main/ets/model/DetailModels';
export {
  ChartEngine,
  ChartSelectionListener,
  ChartStyle,
  MpChartEngine,
  createChartEngine
} from './src/main/ets/chart/ChartEngine';
export { GroupType, WatchGroup, WatchItem } from './src/main/ets/entities/WatchEntities';
export {
  AccountInfo,
  AuthSession,
  OrderDraft,
  OrderErrorCode,
  OrderResult,
  OrderSide,
  OrderStatus,
  TradeContext,
  TradeError,
  TradeErrorReason,
  TradeProvider,
  TradeSource,
  Tradable
} from './src/main/ets/model/TradeModels';
export { TradeAuth } from './src/main/ets/mock/TradeSeeds';
export { QuoteSink, QuoteBus, SinkSubscription } from './src/main/ets/bus/QuoteBus';
export {
  BACKGROUND_INTERVAL_MS,
  DetailSubscriptionRegistry,
  SinkTier,
  SubscriptionHandle
} from './src/main/ets/bus/DetailSubscriptionRegistry';
export { WatchlistProvider, WatchlistRaw } from './src/main/ets/provider/WatchlistProvider';
export { MockFaults, NetFault } from './src/main/ets/mock/MockFaults';
export { DataServices } from './src/main/ets/DataServices';
