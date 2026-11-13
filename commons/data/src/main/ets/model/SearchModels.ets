import { Market, TradeStatus } from './QuoteModels';

/** 搜索段：股票 / 指数 / 板块（FR-05.5，三段各 20 条可展开）。 */
export type SearchKind = 'stock' | 'index' | 'sector';

/**
 * 匹配层级（FR-05.4，L0~L6 七层）：
 * L0 代码精确 → L1 代码前缀 → L2 名称前缀 → L3 名称包含 → L4 全拼 → L5 首字母 → L6 板块。
 * 层内按成交额降序，成交额相同按 code 升序（稳定）。
 */
export const SEARCH_LEVEL_CODE_EXACT: number = 0;
export const SEARCH_LEVEL_CODE_PREFIX: number = 1;
export const SEARCH_LEVEL_NAME_PREFIX: number = 2;
export const SEARCH_LEVEL_NAME_CONTAINS: number = 3;
export const SEARCH_LEVEL_PINYIN: number = 4;
export const SEARCH_LEVEL_INITIALS: number = 5;
export const SEARCH_LEVEL_SECTOR: number = 6;
export const SEARCH_LEVEL_NONE: number = -1;

/** 高亮字段（name / code / pinyin 各自独立区间）。 */
export type HitField = 'name' | 'code' | 'pinyin';

/** 高亮区间：半开区间 [start, end)，由 MatchRules 计算，View 只消费。 */
export interface HitRange {
  field: HitField;
  start: number;
  end: number;
}

/**
 * 本地索引条目（主数据一条 = 一个可被搜到的对象）。
 * 拼音为静态表（D16 不引三方库）：全拼 pinyin / 首字母 initials 均为大写。
 */
export interface SearchEntry {
  code: string;
  name: string;
  kind: SearchKind;
  market: Market;
  status: TradeStatus;
  isNew: boolean;
  pinyin: string;
  initials: string;
  /** 板块名（股票所属板块；板块条自身即板块名）。 */
  sector: string;
  tags: string[];
  /** 板块/指数兜底展示值（股票/指数优先取行情快照；板块没有行情）。 */
  staticPrice: number;
  staticPct: number;
}

/** 单条命中（provider → VM）：level 与 ranges 由匹配规则算出，View 不重算。 */
export class SearchHit {
  code: string = '';
  name: string = '';
  kind: SearchKind = 'stock';
  market: Market = 'SH';
  status: TradeStatus = 'closed';
  isNew: boolean = false;
  price: number | null = null;
  pct: number | null = null;
  tags: string[] = [];
  level: number = SEARCH_LEVEL_NONE;
  ranges: HitRange[] = [];
  /** 层内排序权重（成交额，板块用 0）。 */
  amount: number = 0;
  sector: string = '';
}

/** 结果段：hits 为全部命中（≤SEARCH_SECTION_MAX），total 用于「展开 / 共 N 条」。 */
export class SearchSection {
  kind: SearchKind = 'stock';
  hits: SearchHit[] = [];
  total: number = 0;
}

export class SearchResult {
  term: string = '';
  seq: number = 0;
  sections: SearchSection[] = [];
  costMs: number = 0;
  offline: boolean = false;

  hitCount(): number {
    let count: number = 0;
    for (let i = 0; i < this.sections.length; i++) {
      count += this.sections[i].hits.length;
    }
    return count;
  }

  firstSection(kind: SearchKind): SearchSection | undefined {
    for (let i = 0; i < this.sections.length; i++) {
      if (this.sections[i].kind === kind) {
        return this.sections[i];
      }
    }
    return undefined;
  }
}

/** 错误原因：与六态对齐（失败 / 离线 / 429；timeout 留给真实实现）。 */
export type SearchErrorReason = 'timeout' | 'failed' | 'offline' | 'rate_limited';

export interface SearchError {
  reason: SearchErrorReason;
  retryAfterMs?: number;
}

/**
 * 搜索失败载体：provider 以 reject 抛出，VM 按 reason 翻译成六态文案。
 * 不用裸字符串，避免 L2 层出现中文（架构红线）。
 */
export class SearchFault extends Error {
  readonly reason: SearchErrorReason;
  readonly retryAfterMs: number;

  constructor(reason: SearchErrorReason, retryAfterMs: number) {
    super(reason);
    this.name = 'SearchFault';
    this.reason = reason;
    this.retryAfterMs = retryAfterMs;
  }
}

/** 搜索选项：offline 由 VM 按 ConnectionHub 传入；limit 为每段上限（默认 20）。 */
export interface SearchOptions {
  offline?: boolean;
  limit?: number;
}

/**
 * 空关键词「全部股票」分页结果（M6 追加，只加不改）：
 * total 为股票总数，items 为本页命中（已按成交额降序、code 升序）。
 */
export class StockBrowsePage {
  items: SearchHit[] = [];
  total: number = 0;
  offset: number = 0;
}

/**
 * 搜索契约（§5.4 新增，只加不改）：
 * - search 的 seq 由调用方递增，provider 原样带回，由上层丢弃旧响应（provider 不做策略）；
 * - hot 失败时 reject，视图整块隐藏（AC-90），不占位、不报错；
 * - browse（M6 追加）：空关键词浏览全部股票，分页返回；缺失时 VM 回退空列表。
 */
export interface SearchProvider {
  search(term: string, seq: number, opts?: SearchOptions): Promise<SearchResult>;

  hot(): Promise<string[]>;

  browse?(offset: number, limit: number, seq: number): Promise<StockBrowsePage>;
}

/** 搜索结果每段默认展示条数（FR-05.5）。 */
export const SEARCH_SECTION_LIMIT: number = 20;
/** 空关键词「全部股票」分页每页条数（M6 追加；80 只 = 4 页）。 */
export const SEARCH_BROWSE_PAGE_SIZE: number = 20;
/** 每段最多保留条数（展开后最多全量，索引规模 <200，无需分页）。 */
export const SEARCH_SECTION_MAX: number = 200;
/** 搜索历史上限（FR-05.7）。 */
export const SEARCH_HISTORY_MAX: number = 10;
/** 热搜条数（G-1：两列 × 5 行）。 */
export const SEARCH_HOT_MAX: number = 10;
/** 输入归一化后最大长度（FR-05.2 粘贴截断）。 */
export const SEARCH_TERM_MAX: number = 20;
/** 缓存有效期 5min（FR-05.11 / AC-93）。 */
export const SEARCH_CACHE_TTL_MS: number = 5 * 60 * 1000;
/** 缓存容量（LRU）。 */
export const SEARCH_CACHE_CAPACITY: number = 50;
/** 防抖 300ms（FR-05.3）。 */
export const SEARCH_DEBOUNCE_MS: number = 300;
/** 429 冷却 3s（G-1）。 */
export const SEARCH_RATE_LIMIT_COOLDOWN_MS: number = 3000;
