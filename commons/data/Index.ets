/**
 * 数据能力层（M1 起接入契约、Mock、QuoteBus/QuoteCache）。
 * 唯一允许 new Provider 的地方是 DataServices（R-05）。
 */
export {
  ConnectionState,
  Market,
  QuoteCapabilities,
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
  ChartViewport,
  MpChartEngine,
  createChartEngine
} from './src/main/ets/chart/ChartEngine';
export { GroupType, WatchGroup, WatchItem } from './src/main/ets/entities/WatchEntities';
export {
  AccountInfo,
  AuthSession,
  CancelResult,
  isCancelable,
  isFinalState,
  OpenAccountResult,
  ORDER_STATES,
  OrderDraft,
  OrderErrorCode,
  OrderItem,
  OrderPage,
  OrderQuery,
  OrderResult,
  OrderSide,
  OrderState,
  OrderStatus,
  TradeContext,
  TradeError,
  TradeErrorReason,
  TradeProvider,
  TradeSource,
  Tradable
} from './src/main/ets/model/TradeModels';
export {
  CostBasis,
  Position,
  PositionError,
  PositionErrorReason,
  PositionProvider,
  PositionSummary
} from './src/main/ets/model/PositionModels';
export {
  applyWeights,
  compareNullable,
  computePosition,
  isSuspendedStatus,
  nextPositionSortDir,
  POSITION_SORT_KEYS,
  PositionBasis,
  PositionSortDir,
  PositionSortKey,
  sortPositions,
  summarizePositions,
  valuationPriceOf,
  valueOfPosition
} from './src/main/ets/rules/PositionRules';
export {
  AccountDelta,
  applyFill,
  CancelDecision,
  canCancel,
  MATCH_LOT,
  MatchAccount,
  MatchDecision,
  matchableSession,
  MatchOrder,
  MatchOutcome,
  matchOnce,
  MatchQuote,
  precheck,
  round2
} from './src/main/ets/rules/MatchingRules';
export { JournalEntry, OrderJournalStore } from './src/main/ets/store/OrderJournalStore';
export { AccountRecord, DEFAULT_CASH, HoldRecord, TradeAccountStore } from './src/main/ets/store/TradeAccountStore';
export { TRADE_ORDERS_MAX, TradeOrderStore } from './src/main/ets/store/TradeOrderStore';
export { LocalTradeProvider } from './src/main/ets/provider/LocalTradeProvider';
export { LocalPositionProvider } from './src/main/ets/provider/LocalPositionProvider';
export { TradeAuth } from './src/main/ets/mock/TradeSeeds';
export { QuoteSink, QuoteBus, SinkSubscription } from './src/main/ets/bus/QuoteBus';
export {
  BACKGROUND_INTERVAL_MS,
  DetailSubscriptionRegistry,
  SinkTier,
  SubscriptionHandle
} from './src/main/ets/bus/DetailSubscriptionRegistry';
export { WatchlistProvider } from './src/main/ets/provider/WatchlistProvider';
export { MockFaults, NetFault } from './src/main/ets/mock/MockFaults';
export { DataServices } from './src/main/ets/DataServices';
export {
  HitField,
  HitRange,
  SEARCH_CACHE_CAPACITY,
  SEARCH_CACHE_TTL_MS,
  SEARCH_BROWSE_PAGE_SIZE,
  SEARCH_DEBOUNCE_MS,
  SEARCH_HISTORY_MAX,
  SEARCH_HOT_MAX,
  SEARCH_LEVEL_CODE_EXACT,
  SEARCH_LEVEL_CODE_PREFIX,
  SEARCH_LEVEL_INITIALS,
  SEARCH_LEVEL_NAME_CONTAINS,
  SEARCH_LEVEL_NAME_PREFIX,
  SEARCH_LEVEL_NONE,
  SEARCH_LEVEL_PINYIN,
  SEARCH_LEVEL_SECTOR,
  SEARCH_RATE_LIMIT_COOLDOWN_MS,
  SEARCH_SECTION_LIMIT,
  SEARCH_SECTION_MAX,
  SEARCH_TERM_MAX,
  SearchEntry,
  SearchError,
  SearchErrorReason,
  SearchFault,
  SearchHit,
  SearchKind,
  SearchOptions,
  SearchProvider,
  SearchResult,
  SearchSection,
  StockBrowsePage
} from './src/main/ets/model/SearchModels';
export {
  browseBounds,
  BrowseBounds,
  compareHits,
  hitRanges,
  matchLevel,
  normalizeTerm,
  rangesForField
} from './src/main/ets/rules/SearchRules';
export { LocalSearchIndex, SearchMatch } from './src/main/ets/provider/LocalSearchIndex';
export { buildHotWords, buildSearchEntries } from './src/main/ets/mock/SearchSeeds';
export { StorageAdapter } from './src/main/ets/store/StorageAdapter';
export { QuoteCacheStore } from './src/main/ets/store/QuoteCacheStore';
export { SearchHistoryStore } from './src/main/ets/store/SearchHistoryStore';
export {
  RemoveSnapshot,
  WatchAddInput,
  WatchlistAddOutcome,
  WatchlistChange,
  WatchlistChangeListener,
  WatchlistGroupOutcome,
  WatchlistRemoveOutcome,
  WatchlistSnapshot,
  WatchlistStore
} from './src/main/ets/store/WatchlistStore';
export { WatchlistSyncService } from './src/main/ets/store/WatchlistSyncService';
export { ViewPrefStore } from './src/main/ets/store/ViewPrefStore';
export {
  charCount,
  countUserGroups,
  GroupEditReason,
  GroupNameIssue,
  hasEmoji,
  isSystemGroupId,
  isVirtualGroupId,
  limitNameSummary,
  normalizeGroupName,
  resolveGroupMembership,
  systemGroupsOf,
  validateGroupName,
  WATCHLIST_ALL_GROUP,
  WATCHLIST_GROUP_NAME_MAX,
  WATCHLIST_MAX_ITEMS,
  WATCHLIST_MAX_USER_GROUPS
} from './src/main/ets/rules/WatchlistRules';
export {
  BoardKind,
  boardOf,
  deriveLimitDown,
  deriveLimitUp,
  isStName,
  LIMIT_RATIO_BSE,
  LIMIT_RATIO_CHINEXT,
  LIMIT_RATIO_MAIN,
  LIMIT_RATIO_ST,
  LIMIT_RATIO_STAR,
  LIMIT_TOLERANCE_RATIO,
  LimitPair,
  limitRatioOf,
  PRICE_MAX,
  PRICE_MIN,
  priceInRange,
  priceWithinLimits,
  resolveLimits
} from './src/main/ets/rules/LimitRules';
export {
  applyPatch,
  decideSeq,
  mergePatch,
  QuoteSnapshotLike,
  SEQ_NONE,
  SeqDecision,
  SeqVerdict,
  seqOf
} from './src/main/ets/rules/QuoteMergeRules';
export {
  BAD_FRAME_RESUBSCRIBE_THRESHOLD,
  FrameReference,
  FrameStats,
  FrameValidator,
  FrameVerdict,
  hasMutableField
} from './src/main/ets/rules/FrameValidator';
export {
  POLL_INTERVAL_MS,
  QuoteMode,
  RATE_LIMIT_STREAK_TO_POLL,
  RateLimitPolicy,
  RateLimitState,
  RECOVER_QUIET_MS,
  THROTTLE_INTERVAL_MS
} from './src/main/ets/rules/RateLimitRules';
export {
  cacheable,
  cacheTtlMs,
  capEntries,
  endOfDay,
  isTradingStatus,
  pruneExpired,
  QUOTE_CACHE_MAX,
  QUOTE_CACHE_TTL_TRADING_MS,
  QuoteCacheEntry
} from './src/main/ets/rules/QuoteCacheRules';
export { hashSeed, SESSION_SEED, SeededRandom } from './src/main/ets/mock/SeededRandom';
export { SESSION_MODES, SessionMode, TradingSession } from './src/main/ets/mock/TradingSession';
export { AppConfig, QuoteSource } from './src/main/ets/real/AppConfig';
export { AuthClient } from './src/main/ets/real/AuthClient';
export { ChannelEntry, QuoteChannel } from './src/main/ets/real/QuoteChannel';

