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
export { GroupType, WatchGroup, WatchItem } from './src/main/ets/entities/WatchEntities';
export { QuoteSink, QuoteBus, SinkSubscription } from './src/main/ets/bus/QuoteBus';
export { WatchlistProvider, WatchlistRaw } from './src/main/ets/provider/WatchlistProvider';
export { DataServices } from './src/main/ets/DataServices';
