import { buildIndexSet } from '../mock/MarketSeeds';

/**
 * 自选数据源（M7-1 退化）：自选集合已由 `WatchlistStore` 唯一提供（P0 数据同源），
 * Provider 只保留「分组 → 指数条配置」这类纯种子数据，不再提供自选集合。
 * 保留接口是为了将来把指数条配置换成服务端下发（只加不改）。
 */
export interface WatchlistProvider {
  indexSet(): Map<string, string[]>;
}

export class MockWatchlistProvider implements WatchlistProvider {
  indexSet(): Map<string, string[]> {
    return buildIndexSet();
  }
}
