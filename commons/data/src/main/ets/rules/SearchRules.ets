import {
  HitRange,
  SEARCH_LEVEL_CODE_EXACT,
  SEARCH_LEVEL_CODE_PREFIX,
  SEARCH_LEVEL_INITIALS,
  SEARCH_LEVEL_NAME_CONTAINS,
  SEARCH_LEVEL_NAME_PREFIX,
  SEARCH_LEVEL_NONE,
  SEARCH_LEVEL_PINYIN,
  SEARCH_LEVEL_SECTOR,
  SEARCH_TERM_MAX,
  SearchEntry,
  SearchHit
} from '../model/SearchModels';

/**
 * 搜索匹配规则（M6-2）：纯函数、零中文、零 UI 依赖，可单测。
 * 归一化 / 七级匹配（L0~L6）/ 层内排序 / 高亮区间，全部集中在此，provider 与 VM 共用。
 */

/** 全角 → 半角（含全角空格 U+3000）；字母统一大写，避免大小写影响匹配（FR-05.2）。 */
export function normalizeTerm(raw: string): string {
  let text: string = '';
  for (let i = 0; i < raw.length; i++) {
    let code: number = raw.charCodeAt(i);
    if (code === 0x3000) {
      code = 0x20;
    } else if (code >= 0xFF01 && code <= 0xFF5E) {
      code -= 0xFEE0;
    }
    text += String.fromCharCode(code);
  }
  text = text.trim();
  if (text.length > SEARCH_TERM_MAX) {
    text = text.substring(0, SEARCH_TERM_MAX);
  }
  return text.toUpperCase();
}

/** 匹配层级；-1 表示不命中（见 SearchModels 的 L0~L6 定义）。 */
export function matchLevel(term: string, entry: SearchEntry): number {
  if (term.length === 0) {
    return SEARCH_LEVEL_NONE;
  }
  // 板块条只参与 L6：避免「白酒」这类板块名以 L2 抢到股票前面（FR-05.4：L6 板块）。
  if (entry.kind === 'sector') {
    const upperSector: string = entry.name.toUpperCase();
    if (upperSector.indexOf(term) >= 0) {
      return SEARCH_LEVEL_SECTOR;
    }
    if (entry.pinyin.length > 0 && entry.pinyin.toUpperCase().startsWith(term)) {
      return SEARCH_LEVEL_SECTOR;
    }
    if (entry.initials.length > 0 && entry.initials.toUpperCase().startsWith(term)) {
      return SEARCH_LEVEL_SECTOR;
    }
    return SEARCH_LEVEL_NONE;
  }
  if (entry.code === term) {
    return SEARCH_LEVEL_CODE_EXACT;
  }
  if (entry.code.startsWith(term)) {
    return SEARCH_LEVEL_CODE_PREFIX;
  }
  const upperName: string = entry.name.toUpperCase();
  if (upperName.startsWith(term)) {
    return SEARCH_LEVEL_NAME_PREFIX;
  }
  if (upperName.indexOf(term) >= 0) {
    return SEARCH_LEVEL_NAME_CONTAINS;
  }
  if (entry.pinyin.length > 0 && entry.pinyin.toUpperCase().startsWith(term)) {
    return SEARCH_LEVEL_PINYIN;
  }
  if (entry.initials.length > 0 && entry.initials.toUpperCase().startsWith(term)) {
    return SEARCH_LEVEL_INITIALS;
  }
  return SEARCH_LEVEL_NONE;
}

/** 层内排序：成交额降序 → code 升序（稳定，AC-88）。 */
export function compareHits(a: SearchHit, b: SearchHit): number {
  if (a.level !== b.level) {
    return a.level - b.level;
  }
  if (a.amount !== b.amount) {
    return b.amount - a.amount;
  }
  if (a.code === b.code) {
    return 0;
  }
  return a.code < b.code ? -1 : 1;
}

/** 收集 text 中所有命中位置（大小写不敏感，返回半开区间 [start, end)）。 */
function rangesOf(text: string, term: string, field: 'name' | 'code' | 'pinyin',
  out: HitRange[]): void {
  if (text.length === 0 || term.length === 0) {
    return;
  }
  const upper: string = text.toUpperCase();
  let from: number = 0;
  while (from <= upper.length - term.length) {
    const index: number = upper.indexOf(term, from);
    if (index < 0) {
      break;
    }
    out.push({ field: field, start: index, end: index + term.length });
    from = index + term.length;
  }
}

/**
 * 高亮区间（FR-05.6）：命中片段按字段分组，半开区间，越界不返回。
 * L0/L1 → code；L2/L3 → name（全部出现位置）；L4 → pinyin；L5 → initials；L6 → name（板块名）。
 */
export function hitRanges(term: string, entry: SearchEntry, level: number): HitRange[] {
  const ranges: HitRange[] = [];
  if (term.length === 0 || level === SEARCH_LEVEL_NONE) {
    return ranges;
  }
  if (level === SEARCH_LEVEL_CODE_EXACT || level === SEARCH_LEVEL_CODE_PREFIX) {
    ranges.push({ field: 'code', start: 0, end: Math.min(term.length, entry.code.length) });
    return ranges;
  }
  if (level === SEARCH_LEVEL_NAME_PREFIX || level === SEARCH_LEVEL_NAME_CONTAINS ||
    level === SEARCH_LEVEL_SECTOR) {
    rangesOf(entry.name, term, 'name', ranges);
    return ranges;
  }
  if (level === SEARCH_LEVEL_PINYIN) {
    ranges.push({ field: 'pinyin', start: 0, end: Math.min(term.length, entry.pinyin.length) });
    return ranges;
  }
  if (level === SEARCH_LEVEL_INITIALS) {
    ranges.push({ field: 'pinyin', start: 0, end: Math.min(term.length, entry.initials.length) });
    return ranges;
  }
  return ranges;
}

/** 取某字段的区间（View 侧按字段取，避免每帧过滤整表）。 */
export function rangesForField(ranges: HitRange[], field: 'name' | 'code' | 'pinyin'): HitRange[] {
  const result: HitRange[] = [];
  for (let i = 0; i < ranges.length; i++) {
    if (ranges[i].field === field) {
      result.push(ranges[i]);
    }
  }
  return result;
}

/** 分页切片边界（半开区间 [start, end)）。 */
export class BrowseBounds {
  start: number = 0;
  end: number = 0;
  hasMore: boolean = false;
}

/**
 * 空关键词浏览的分页边界（M6 追加）：越界裁剪、负数归零，供 provider 与单测共用。
 */
export function browseBounds(total: number, offset: number, limit: number): BrowseBounds {
  const bounds: BrowseBounds = new BrowseBounds();
  const safeTotal: number = Math.max(0, total);
  const safeOffset: number = Math.min(Math.max(0, offset), safeTotal);
  const safeLimit: number = Math.max(0, limit);
  bounds.start = safeOffset;
  bounds.end = Math.min(safeOffset + safeLimit, safeTotal);
  bounds.hasMore = bounds.end < safeTotal;
  return bounds;
}
