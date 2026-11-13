import { QuoteProvider } from './model/QuoteModels';
import { DetailProvider } from './model/DetailModels';
import { MockQuoteProvider } from './provider/MockQuoteProvider';
import { MockDetailProvider } from './provider/MockDetailProvider';
import { MockWatchlistProvider, WatchlistProvider } from './provider/WatchlistProvider';
import { TradeProvider } from './model/TradeModels';
import { QuoteBus } from './bus/QuoteBus';
import { DetailSubscriptionRegistry } from './bus/DetailSubscriptionRegistry';
import { MockSearchProvider } from './provider/MockSearchProvider';
import { SearchProvider } from './model/SearchModels';
import { SearchHistoryStore } from './store/SearchHistoryStore';
import { WatchlistStore } from './store/WatchlistStore';
import { WatchlistSyncService } from './store/WatchlistSyncService';
import { ViewPrefStore } from './store/ViewPrefStore';
import { QuoteCacheStore } from './store/QuoteCacheStore';
import { QuoteChannel } from './real/QuoteChannel';
import { AppConfig, QuoteSource } from './real/AppConfig';
import { LocalTradeProvider } from './provider/LocalTradeProvider';
import { TradeAccountStore } from './store/TradeAccountStore';
import { TradeOrderStore } from './store/TradeOrderStore';
import { OrderJournalStore } from './store/OrderJournalStore';

/**
 * 数据装配点：全工程唯一允许 `new Mock*` / `new Real*` 的地方（R-05）。
 * 唯一一处 provider ↔ bus 的接线也在本文件，上层只拿接口。
 */
export class DataServices {
  private static quote: QuoteProvider | undefined = undefined;
  /** 底层数据源（Mock）；通道模式下由 `QuoteChannel` 包一层。 */
  private static quoteRaw: QuoteProvider | undefined = undefined;
  private static quoteChannelInstance: QuoteChannel | undefined = undefined;
  private static watch: WatchlistProvider | undefined = undefined;
  private static detail: DetailProvider | undefined = undefined;
  private static trade: TradeProvider | undefined = undefined;
  private static bus: QuoteBus | undefined = undefined;
  private static detailSubsRegistry: DetailSubscriptionRegistry | undefined = undefined;
  private static search: SearchProvider | undefined = undefined;
  private static history: SearchHistoryStore | undefined = undefined;
  private static watchStore: WatchlistStore | undefined = undefined;
  private static pendingSync: WatchlistSyncService | undefined = undefined;
  private static viewPreferences: ViewPrefStore | undefined = undefined;
  private static quoteCacheStore: QuoteCacheStore | undefined = undefined;
  private static accountStore: TradeAccountStore | undefined = undefined;
  private static orderStore: TradeOrderStore | undefined = undefined;
  private static journalStore: OrderJournalStore | undefined = undefined;

  /**
   * 行情源（M9-2）：按 `AppConfig.quoteSource` 装配。
   * - `sandbox`（默认）：`QuoteChannel` 包住本地 Mock，获得 鉴权/帧校验/限流降级/健康状态；
   * - `mock`：直连本地 Mock，最短链路（排查通道问题时可回退）。
   * 本方法仍是全工程唯一 `new Mock*` 之处（R-05）。
   */
  static quoteProvider(): QuoteProvider {
    if (DataServices.quote === undefined) {
      const raw: QuoteProvider = new MockQuoteProvider();
      DataServices.quoteRaw = raw;
      if (AppConfig.useChannel()) {
        const channel: QuoteChannel = new QuoteChannel(raw);
        DataServices.quoteChannelInstance = channel;
        DataServices.quote = channel;
      } else {
        DataServices.quote = raw;
      }
    }
    return DataServices.quote;
  }

  /** 通道实例（仅通道模式下存在；调试面板/验收断言用）。 */
  static quoteChannel(): QuoteChannel | undefined {
    DataServices.quoteProvider();
    return DataServices.quoteChannelInstance;
  }

  /** 当前数据源（只读，供调试面板展示）。 */
  static quoteSource(): QuoteSource {
    return AppConfig.quoteSource;
  }

  static watchlistProvider(): WatchlistProvider {
    if (DataServices.watch === undefined) {
      DataServices.watch = new MockWatchlistProvider();
    }
    return DataServices.watch;
  }

  /** 详情源与自选同源行情：共用同一个 quote provider 实例。 */
  static detailProvider(): DetailProvider {
    if (DataServices.detail === undefined) {
      DataServices.detail = new MockDetailProvider(DataServices.quoteProvider());
    }
    return DataServices.detail;
  }

  /** 交易网关与账户上下文：本地模拟撮合（M10），与行情同源（下单时读一次快照）。 */
  static tradeProvider(): TradeProvider {
    if (DataServices.trade === undefined) {
      DataServices.trade = new LocalTradeProvider(
        DataServices.quoteProvider(),
        DataServices.tradeAccount(),
        DataServices.tradeOrders(),
        DataServices.orderJournal()
      );
    }
    return DataServices.trade;
  }

  /** 交易账户/持仓（M10，`trade_account_v1`）。 */
  static tradeAccount(): TradeAccountStore {
    if (DataServices.accountStore === undefined) {
      DataServices.accountStore = new TradeAccountStore();
    }
    return DataServices.accountStore;
  }

  /** 委托库（M10，`trade_orders_v1`）。 */
  static tradeOrders(): TradeOrderStore {
    if (DataServices.orderStore === undefined) {
      DataServices.orderStore = new TradeOrderStore();
    }
    return DataServices.orderStore;
  }

  /** 幂等流水（M10，`order_journal_v1`）。 */
  static orderJournal(): OrderJournalStore {
    if (DataServices.journalStore === undefined) {
      DataServices.journalStore = new OrderJournalStore();
    }
    return DataServices.journalStore;
  }

  /** 本地交易网关实例（调试面板/验收断言用；未装配时为 undefined）。 */
  static localTrade(): LocalTradeProvider | undefined {
    const provider: TradeProvider = DataServices.tradeProvider();
    return provider instanceof LocalTradeProvider ? provider : undefined;
  }

  static quoteBus(): QuoteBus {
    if (DataServices.bus === undefined) {
      DataServices.bus = new QuoteBus(DataServices.quoteProvider());
    }
    return DataServices.bus;
  }

  /** 详情订阅登记表（M4）：同 code 多窗合并一路 + 非焦点降频，上层不直接订阅 provider。 */
  static detailSubs(): DetailSubscriptionRegistry {
    if (DataServices.detailSubsRegistry === undefined) {
      DataServices.detailSubsRegistry = new DetailSubscriptionRegistry(DataServices.detailProvider());
    }
    return DataServices.detailSubsRegistry;
  }

  /** 搜索源（M6）：本地索引 + 同源行情快照，离线可搜（D52）。 */
  static searchProvider(): SearchProvider {
    if (DataServices.search === undefined) {
      DataServices.search = new MockSearchProvider(DataServices.quoteProvider());
    }
    return DataServices.search;
  }

  /** 搜索历史（M6-5）：唯一入口是 StorageAdapter，本方法只返回同一实例。 */
  static searchHistory(): SearchHistoryStore {
    if (DataServices.history === undefined) {
      DataServices.history = new SearchHistoryStore();
    }
    return DataServices.history;
  }

  /** 自选存储（M7-1）：自选集合与分组定义的唯一来源，首次访问即挂上待同步服务。 */
  static watchlistStore(): WatchlistStore {
    if (DataServices.watchStore === undefined) {
      DataServices.watchStore = new WatchlistStore();
      DataServices.pendingSync = new WatchlistSyncService(DataServices.watchStore);
      DataServices.pendingSync.start();
    }
    return DataServices.watchStore;
  }

  /** 待同步服务（M7-7）：页面回到前台可主动补一次。 */
  static watchlistSync(): WatchlistSyncService {
    const store: WatchlistStore = DataServices.watchlistStore();
    const existing: WatchlistSyncService | undefined = DataServices.pendingSync;
    if (existing !== undefined) {
      return existing;
    }
    const created: WatchlistSyncService = new WatchlistSyncService(store);
    DataServices.pendingSync = created;
    created.start();
    return created;
  }

  /** 视图偏好（M8-4）：`view_pref_v1` 的唯一读写入口，冷启由 EntryAbility 预读。 */
  static viewPref(): ViewPrefStore {
    if (DataServices.viewPreferences === undefined) {
      DataServices.viewPreferences = new ViewPrefStore();
    }
    return DataServices.viewPreferences;
  }

  /**
   * 行情缓存（M9-6）：`quote_cache_v1` 的唯一入口。
   * 冷启由 EntryAbility 预热读盘；页面在等网络前先渲染缓存（AC-111 ≤800ms 出内容）。
   */
  static quoteCache(): QuoteCacheStore {
    if (DataServices.quoteCacheStore === undefined) {
      DataServices.quoteCacheStore = new QuoteCacheStore();
    }
    return DataServices.quoteCacheStore;
  }
}
