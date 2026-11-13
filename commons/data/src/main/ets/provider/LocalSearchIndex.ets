import { HitRange, SEARCH_LEVEL_NONE, SearchEntry } from '../model/SearchModels';
import { buildSearchEntries } from '../mock/SearchSeeds';
import { hitRanges, matchLevel } from '../rules/SearchRules';

/** 命中候选：条目 + 层级 + 高亮区间（已算好，上层不再重算）。 */
export class SearchMatch {
  entry: SearchEntry;
  level: number;
  ranges: HitRange[];

  constructor(entry: SearchEntry, level: number, ranges: HitRange[]) {
    this.entry = entry;
    this.level = level;
    this.ranges = ranges;
  }
}

/**
 * 本地搜索索引（M6-1）：主数据构建一次，之后只做匹配。
 * 规模 <200 条时线性扫描足够（单次 <1ms）；5000 只压测仍在预算内（AC-93）。
 * 拼音是静态表（不引三方库），五路匹配顺序与 FR-05.4 一致，规则在 SearchRules 内。
 */
export class LocalSearchIndex {
  private entries: SearchEntry[] = [];
  private costMs: number = 0;

  build(): void {
    const started: number = Date.now();
    this.entries = buildSearchEntries();
    this.costMs = Date.now() - started;
  }

  isBuilt(): boolean {
    return this.entries.length > 0;
  }

  buildCostMs(): number {
    return this.costMs;
  }

  size(): number {
    return this.entries.length;
  }

  /** 空关键词浏览（M6 追加）：只返回股票条，默认排序由 provider 统一做。 */
  stocks(): SearchEntry[] {
    const result: SearchEntry[] = [];
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].kind === 'stock') {
        result.push(this.entries[i]);
      }
    }
    return result;
  }

  /** 匹配并计算高亮区间；结果未排序（排序由 provider 统一按层级 + 成交额）。 */
  match(term: string): SearchMatch[] {
    const matches: SearchMatch[] = [];
    if (term.length === 0) {
      return matches;
    }
    for (let i = 0; i < this.entries.length; i++) {
      const entry: SearchEntry = this.entries[i];
      const level: number = matchLevel(term, entry);
      if (level === SEARCH_LEVEL_NONE) {
        continue;
      }
      matches.push(new SearchMatch(entry, level, hitRanges(term, entry, level)));
    }
    return matches;
  }
}
