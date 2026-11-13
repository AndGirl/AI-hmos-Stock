import {
  DataServices,
  MockFaults,
  QuoteCacheStore,
  QuoteSnapshot,
  QuoteSink,
  SinkSubscription,
  WatchGroup,
  WatchItem,
  WatchlistSnapshot
} from 'commons_data';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 仓储归一化后的自选数据：分组、条目、快照（含指数）。 */
export class WatchlistData {
  groups: WatchGroup[] = [];
  items: WatchItem[] = [];
  quotes: Map<string, QuoteSnapshot> = new Map<string, QuoteSnapshot>();
  indexSet: Map<string, string[]> = new Map<string, string[]>();

  quoteOf(code: string): QuoteSnapshot | undefined {
    return this.quotes.get(code);
  }
}

/**
 * L2 仓储：组合 commons/data 的 store / provider / bus，向上只输出实体。
 * 数据集合以 `WatchlistStore` 为唯一来源（P0 数据同源）；`MockWatchlistProvider`
 * 只保留指数条配置，自选集合不再从它读取。
 * 不返回中文文案、不做 UI 副作用（附录 C 第 13 条）。
 */
export class WatchlistRepository {
  async load(): Promise<WatchlistData> {
    if (MockFaults.failWatchlist) {
      throw new Error('mock watchlist failure');
    }
    const store = DataServices.watchlistStore();
    const snapshot: WatchlistSnapshot = await store.snapshot();
    const data: WatchlistData = new WatchlistData();
    data.groups = snapshot.groups;
    data.items = snapshot.items;
    data.indexSet = DataServices.watchlistProvider().indexSet();

    const codes: string[] = [];
    for (let i = 0; i < data.items.length; i++) {
      codes.push(data.items[i].code);
    }
    const indexCodes: string[] = [];
    data.indexSet.forEach((list: string[]): void => {
      for (let i = 0; i < list.length; i++) {
        if (indexCodes.indexOf(list[i]) < 0) {
          indexCodes.push(list[i]);
        }
      }
    });
    const all: string[] = codes.concat(indexCodes);
    // M9-6 / AC-111：先看缓存。全部 code 都有新鲜缓存时**直接返回**（冷启 ≤800ms 出内容），
    // 首个网络快照随后由 QuoteBus 推送补上（onPatch 增量刷新，不重建列表，避免位置抖动）。
    // 必须先 await 读盘（EntryAbility 的预热是异步的，不等会读到空缓存）。
    const cache: QuoteCacheStore = DataServices.quoteCache();
    await cache.load();
    const cachedQuotes: QuoteSnapshot[] = cache.cachedMany(all);
    // 覆盖率 ≥90% 即视为命中：留一点余量给「刚加进来/刚过期」的个别标的，
    // 缺的那几行显示 `--`，由 1s 内的推送补上（不为此整表等网络）。
    const hit: boolean = all.length > 0 && cachedQuotes.length * 10 >= all.length * 9;
    if (hit) {
      for (let i = 0; i < cachedQuotes.length; i++) {
        data.quotes.set(cachedQuotes[i].code, cachedQuotes[i]);
      }
      hilog.info(0x0001, 'QuoteLog', 'quote_cache_hit codes=%{public}d', all.length);
      return data;
    }
    for (let i = 0; i < cachedQuotes.length; i++) {
      data.quotes.set(cachedQuotes[i].code, cachedQuotes[i]);
    }
    const snapshots: QuoteSnapshot[] = await DataServices.quoteProvider().getSnapshots(all);
    for (let i = 0; i < snapshots.length; i++) {
      data.quotes.set(snapshots[i].code, snapshots[i]);
    }
    // M9-6：把本次快照写进缓存，供下次冷启首帧直接渲染（≤800ms 出内容）。
    cache.putAll(snapshots);
    hilog.info(0x0001, 'QuoteLog', 'quote_cache_miss filled=%{public}d', snapshots.length);
    return data;
  }

  /** 订阅走 QuoteBus：1s 合并窗口 + 单行分发。 */
  subscribe(codes: string[], sink: QuoteSink): SinkSubscription {
    return DataServices.quoteBus().subscribe(codes, sink);
  }
}
