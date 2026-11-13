/**
 * 搜索（M6 实现）。对外唯一入口：跨模块只允许 import from 'search'（R-06）。
 */
export { SearchPage } from './src/main/ets/view/SearchPage';
export type { SearchMode } from './src/main/ets/view/SearchPage';
export { SearchVM } from './src/main/ets/viewmodel/SearchVM';
export type { SearchAddResult, SearchHotState, SearchRowAction, SearchState } from './src/main/ets/viewmodel/SearchVM';
export { SearchRowVM } from './src/main/ets/viewmodel/SearchRowVM';
export { SearchSectionVM } from './src/main/ets/viewmodel/SearchSectionVM';
export { SearchQuery } from './src/main/ets/repository/SearchQuery';
export { compareHits, hitRanges, matchLevel, normalizeTerm, rangesForField } from './src/main/ets/repository/MatchRules';
export { browseBounds, BrowseBounds } from './src/main/ets/repository/MatchRules';
export type { HitRange } from './src/main/ets/repository/MatchRules';
