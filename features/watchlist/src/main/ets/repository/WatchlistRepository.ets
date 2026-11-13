import {
  DataServices,
  MockFaults,
  QuoteSnapshot,
  QuoteSink,
  SinkSubscription,
  WatchGroup,
  WatchItem,
  WatchlistSnapshot
} from 'commons_data';

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
    const snapshots: QuoteSnapshot[] = await DataServices.quoteProvider().getSnapshots(all);
    for (let i = 0; i < snapshots.length; i++) {
      data.quotes.set(snapshots[i].code, snapshots[i]);
    }
    return data;
  }

  /** 订阅走 QuoteBus：1s 合并窗口 + 单行分发。 */
  subscribe(codes: string[], sink: QuoteSink): SinkSubscription {
    return DataServices.quoteBus().subscribe(codes, sink);
  }
}
