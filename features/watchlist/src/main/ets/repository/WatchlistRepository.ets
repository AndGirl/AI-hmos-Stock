import {
  DataServices,
  QuotePatch,
  QuoteSnapshot,
  QuoteSink,
  SinkSubscription,
  WatchGroup,
  WatchItem,
  WatchlistRaw
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
 * L2 仓储：组合 commons/data 的 provider / bus，向上只输出实体。
 * 不返回中文文案、不做 UI 副作用（附录 C 第 13 条）。
 */
export class WatchlistRepository {
  async load(): Promise<WatchlistData> {
    const provider = DataServices.watchlistProvider();
    const raw: WatchlistRaw = await provider.load();
    const data: WatchlistData = new WatchlistData();
    data.groups = raw.groups;
    data.items = raw.items;
    data.indexSet = provider.indexSet();

    const codes: string[] = [];
    for (let i = 0; i < raw.items.length; i++) {
      codes.push(raw.items[i].code);
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
