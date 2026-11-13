import {
  normalizeTerm,
  SEARCH_CACHE_CAPACITY,
  SEARCH_CACHE_TTL_MS,
  SEARCH_DEBOUNCE_MS,
  SEARCH_SECTION_MAX,
  SearchOptions,
  SearchProvider,
  SearchResult
} from 'commons_data';

/** LRU 缓存条目：结果 + 写入时刻。 */
class CacheEntry {
  result: SearchResult;
  at: number;

  constructor(result: SearchResult, at: number) {
    this.result = result;
    this.at = at;
  }
}

/**
 * 查询编排（M6-3 的一部分）：防抖、seq、LRU(5min/50)、在途请求作废。
 * 纯逻辑 + 定时器，不含 UI；seq 递增由本类统一发放，VM 只比较是否最新。
 */
export class SearchQuery {
  private provider: SearchProvider;
  private seq: number = 0;
  private debounceTimer: number = -1;
  private cache: Map<string, CacheEntry> = new Map<string, CacheEntry>();
  private lru: string[] = [];

  constructor(provider: SearchProvider) {
    this.provider = provider;
  }

  /** 每次发起查询前自增；返回给 VM 作为「本次请求编号」。 */
  nextSeq(): number {
    this.seq++;
    return this.seq;
  }

  isLatest(seq: number): boolean {
    return seq === this.seq;
  }

  /** 作废所有在途请求（清空输入 / 页面销毁）。 */
  invalidate(): void {
    this.seq++;
    this.cancelDebounce();
  }

  /** 300ms 防抖；immediate=true 时立即执行（首字符 / Enter / 点历史热搜）。 */
  schedule(action: () => void, immediate: boolean): void {
    this.cancelDebounce();
    if (immediate) {
      action();
      return;
    }
    this.debounceTimer = setTimeout((): void => {
      this.debounceTimer = -1;
      action();
    }, SEARCH_DEBOUNCE_MS);
  }

  cancelDebounce(): void {
    if (this.debounceTimer !== -1) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
  }

  /** 命中缓存则同步返回（AC-93：同 term 5min / 容量 50，命中不发请求）。 */
  cached(term: string): SearchResult | undefined {
    const key: string = normalizeTerm(term);
    const entry: CacheEntry | undefined = this.cache.get(key);
    if (entry === undefined) {
      return undefined;
    }
    if (Date.now() - entry.at > SEARCH_CACHE_TTL_MS) {
      this.cache.delete(key);
      this.removeFromLru(key);
      return undefined;
    }
    this.touch(key);
    return entry.result;
  }

  async run(term: string, seq: number, offline: boolean): Promise<SearchResult> {
    const cached: SearchResult | undefined = this.cached(term);
    if (cached !== undefined) {
      return cached;
    }
    const opts: SearchOptions = { offline: offline, limit: SEARCH_SECTION_MAX };
    const result: SearchResult = await this.provider.search(term, seq, opts);
    if (result.seq !== seq) {
      // provider 返回的 seq 与请求不一致（被更新的请求覆盖）：按作废处理。
      throw new Error('stale');
    }
    // 离线结果不进缓存：否则恢复网络后同词命中缓存，页面会一直显示「当前离线」。
    if (!result.offline) {
      this.put(term, result);
    }
    return result;
  }

  dispose(): void {
    this.cancelDebounce();
    this.clearCache();
  }

  /** 清空 LRU（debug 注入故障前必须清，否则命中缓存会绕过失败/限流）。 */
  clearCache(): void {
    this.cache.clear();
    this.lru = [];
  }

  private put(term: string, result: SearchResult): void {
    const key: string = normalizeTerm(term);
    if (key.length === 0) {
      return;
    }
    if (this.cache.has(key)) {
      this.touch(key);
    } else {
      this.lru.push(key);
    }
    this.cache.set(key, new CacheEntry(result, Date.now()));
    while (this.lru.length > SEARCH_CACHE_CAPACITY) {
      const oldest: string = this.lru[0];
      this.lru.splice(0, 1);
      this.cache.delete(oldest);
    }
  }

  private touch(key: string): void {
    const index: number = this.lru.indexOf(key);
    if (index >= 0) {
      this.lru.splice(index, 1);
    }
    this.lru.push(key);
  }

  private removeFromLru(key: string): void {
    const index: number = this.lru.indexOf(key);
    if (index >= 0) {
      this.lru.splice(index, 1);
    }
  }
}
