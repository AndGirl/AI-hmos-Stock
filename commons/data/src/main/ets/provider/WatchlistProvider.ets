import { WatchGroup, WatchItem } from '../entities/WatchEntities';
import { buildIndexSet, buildStockSeeds, buildWatchGroups, buildWatchItems } from '../mock/MarketSeeds';
import { MockFaults } from '../mock/MockFaults';
import { StockSeed } from '../mock/MarketSeeds';

/** 自选列表原始数据（分组 + 条目），由仓储归一化为 VM 实体。 */
export class WatchlistRaw {
  groups: WatchGroup[];
  items: WatchItem[];

  constructor(groups: WatchGroup[], items: WatchItem[]) {
    this.groups = groups;
    this.items = items;
  }
}

/**
 * 自选数据源。M1 全 Mock：启动读一次；增删自选在 FR-04（后续里程碑）。
 */
export interface WatchlistProvider {
  load(): Promise<WatchlistRaw>;

  indexSet(): Map<string, string[]>;
}

export class MockWatchlistProvider implements WatchlistProvider {
  load(): Promise<WatchlistRaw> {
    if (MockFaults.failWatchlist) {
      return Promise.reject(new Error('mock watchlist failure'));
    }
    const seeds: StockSeed[] = MockFaults.emptyWatchlist ? [] : buildStockSeeds();
    return Promise.resolve(new WatchlistRaw(buildWatchGroups(), buildWatchItems(seeds)));
  }

  indexSet(): Map<string, string[]> {
    return buildIndexSet();
  }
}
