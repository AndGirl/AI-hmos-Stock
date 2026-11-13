import { QuoteProvider, QuoteSnapshot, TradeStatus } from '../model/QuoteModels';
import {
  SEARCH_HOT_MAX,
  SEARCH_RATE_LIMIT_COOLDOWN_MS,
  SEARCH_SECTION_MAX,
  SearchEntry,
  SearchFault,
  SearchHit,
  SearchKind,
  SearchOptions,
  SearchProvider,
  SearchResult,
  SearchSection,
  StockBrowsePage
} from '../model/SearchModels';
import { browseBounds, compareHits, normalizeTerm } from '../rules/SearchRules';
import { buildHotWords } from '../mock/SearchSeeds';
import { MockFaults } from '../mock/MockFaults';
import { LocalSearchIndex, SearchMatch } from './LocalSearchIndex';

/** Mock 网络时延：让「搜索中」态可被肉眼/截图观察到，仍远低于 AC-93 的 500ms。 */
const MOCK_LATENCY_MS: number = 120;
/** debug「慢请求」注入：把时延拉长，便于截取「搜索中」态（AC-92 取证）。 */
const MOCK_SLOW_LATENCY_MS: number = 4000;

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: (value: void) => void): void => {
    setTimeout((): void => {
      resolve();
    }, ms);
  });
}

/**
 * 本地搜索实现（D52：本地主数据优先，离线可搜）。
 * - 索引在首帧后预热（setTimeout(0)），不阻塞启动；
 * - seq 原样带回，由 VM 判断是否最新（provider 不做策略）；
 * - 失败/429/热搜失败由 MockFaults 注入，供六态验收（AC-92）。
 */
export class MockSearchProvider implements SearchProvider {
  private quote: QuoteProvider;
  private index: LocalSearchIndex = new LocalSearchIndex();

  constructor(quote: QuoteProvider) {
    this.quote = quote;
    // 首帧后构建索引：避免和启动首屏抢时间片（M6-1）。
    setTimeout((): void => {
      this.ensureIndex();
    }, 0);
  }

  async search(term: string, seq: number, opts?: SearchOptions): Promise<SearchResult> {
    const started: number = Date.now();
    if (MockFaults.searchRateLimited) {
      throw new SearchFault('rate_limited', SEARCH_RATE_LIMIT_COOLDOWN_MS);
    }
    if (MockFaults.failSearch) {
      throw new SearchFault('failed', 0);
    }
    const normalized: string = normalizeTerm(term);
    const result: SearchResult = new SearchResult();
    result.term = normalized;
    result.seq = seq;
    result.offline = opts !== undefined && opts.offline === true;

    if (normalized.length > 0) {
      await delay(MockFaults.searchSlow ? MOCK_SLOW_LATENCY_MS : MOCK_LATENCY_MS);
      this.ensureIndex();
      const matches: SearchMatch[] = this.index.match(normalized);
      const hits: SearchHit[] = await this.enrich(matches);
      hits.sort((a: SearchHit, b: SearchHit): number => {
        return compareHits(a, b);
      });
      result.sections = MockSearchProvider.toSections(hits, MockSearchProvider.limitOf(opts));
    }
    result.costMs = Date.now() - started;
    return result;
  }

  async hot(): Promise<string[]> {
    if (MockFaults.failHot) {
      throw new SearchFault('failed', 0);
    }
    await delay(MOCK_LATENCY_MS);
    const words: string[] = buildHotWords();
    return words.slice(0, SEARCH_HOT_MAX);
  }

  /**
   * 空关键词浏览（M6 追加）：全部股票按「成交额降序 → code 升序」分页。
   * 复用行情补齐（价格/涨跌幅/停牌/新股），与搜索结果行同形。
   */
  async browse(offset: number, limit: number, seq: number): Promise<StockBrowsePage> {
    if (MockFaults.failSearch) {
      throw new SearchFault('failed', 0);
    }
    await delay(MockFaults.searchSlow ? MOCK_SLOW_LATENCY_MS : MOCK_LATENCY_MS);
    this.ensureIndex();
    const entries: SearchEntry[] = this.index.stocks();
    const matches: SearchMatch[] = [];
    for (let i = 0; i < entries.length; i++) {
      // level 0/ranges 空：浏览列表不涉及关键词命中与高亮
      matches.push(new SearchMatch(entries[i], 0, []));
    }
    const hits: SearchHit[] = await this.enrich(matches);
    hits.sort((a: SearchHit, b: SearchHit): number => {
      return MockSearchProvider.compareBrowse(a, b);
    });
    const bounds = browseBounds(hits.length, offset, limit);
    const page: StockBrowsePage = new StockBrowsePage();
    page.total = hits.length;
    page.offset = bounds.start;
    page.items = hits.slice(bounds.start, bounds.end);
    return page;
  }

  private static compareBrowse(a: SearchHit, b: SearchHit): number {
    if (a.amount !== b.amount) {
      return b.amount - a.amount;
    }
    if (a.code === b.code) {
      return 0;
    }
    return a.code < b.code ? -1 : 1;
  }

  /** 调试用：索引条目数（验收时确认主数据规模）。 */
  indexSize(): number {
    this.ensureIndex();
    return this.index.size();
  }

  private ensureIndex(): void {
    if (!this.index.isBuilt()) {
      this.index.build();
    }
  }

  private static limitOf(opts: SearchOptions | undefined): number {
    if (opts === undefined || opts.limit === undefined || opts.limit <= 0) {
      return SEARCH_SECTION_MAX;
    }
    return Math.min(opts.limit, SEARCH_SECTION_MAX);
  }

  /** 补齐行情字段：股票/指数取快照，板块只有涨跌幅。 */
  private async enrich(matches: SearchMatch[]): Promise<SearchHit[]> {
    const codes: string[] = [];
    for (let i = 0; i < matches.length; i++) {
      const kind: SearchKind = matches[i].entry.kind;
      if (kind === 'stock' || kind === 'index') {
        codes.push(matches[i].entry.code);
      }
    }
    const snapshots: Map<string, QuoteSnapshot> = new Map<string, QuoteSnapshot>();
    if (codes.length > 0) {
      const list: QuoteSnapshot[] = await this.quote.getSnapshots(codes);
      for (let i = 0; i < list.length; i++) {
        snapshots.set(list[i].code, list[i]);
      }
    }

    const hits: SearchHit[] = [];
    for (let i = 0; i < matches.length; i++) {
      const match: SearchMatch = matches[i];
      const entry: SearchEntry = match.entry;
      const hit: SearchHit = new SearchHit();
      hit.code = entry.code;
      hit.name = entry.name;
      hit.kind = entry.kind;
      hit.market = entry.market;
      hit.status = entry.status;
      hit.isNew = entry.isNew;
      hit.level = match.level;
      hit.ranges = match.ranges;
      hit.sector = entry.sector;
      if (entry.kind === 'sector') {
        hit.price = null;
        hit.pct = entry.staticPct;
        hit.amount = 0;
      } else {
        const snapshot: QuoteSnapshot | undefined = snapshots.get(entry.code);
        if (snapshot !== undefined) {
          hit.price = snapshot.last;
          hit.pct = snapshot.pct;
          hit.status = snapshot.status;
          hit.isNew = snapshot.isNew;
          hit.amount = snapshot.amount !== null ? snapshot.amount : 0;
          hit.market = snapshot.market;
          if (snapshot.name.length > 0) {
            hit.name = snapshot.name;
          }
        } else {
          hit.price = entry.kind === 'index' ? entry.staticPrice : null;
          hit.pct = entry.staticPct;
          hit.amount = 0;
        }
      }
      hits.push(hit);
    }
    return hits;
  }

  private static toSections(hits: SearchHit[], limit: number): SearchSection[] {
    const sections: SearchSection[] = [];
    const kinds: SearchKind[] = ['stock', 'index', 'sector'];
    for (let k = 0; k < kinds.length; k++) {
      const kind: SearchKind = kinds[k];
      let total: number = 0;
      const section: SearchSection = new SearchSection();
      section.kind = kind;
      for (let i = 0; i < hits.length; i++) {
        if (hits[i].kind !== kind) {
          continue;
        }
        total++;
        if (section.hits.length < limit) {
          section.hits.push(hits[i]);
        }
      }
      if (total > 0) {
        section.total = total;
        sections.push(section);
      }
    }
    return sections;
  }
}

/** 状态判定辅助：停牌/退市不隐藏（AC-88），由 View 决定展示。 */
export function isImmobileStatus(status: TradeStatus): boolean {
  return status === 'suspended' || status === 'delisted';
}
