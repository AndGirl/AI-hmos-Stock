/**
 * 搜索匹配规则（M6-2）在 features/search 的唯一入口。
 * 纯函数实现放在 commons/data/rules（provider 与 VM 共用一份），此处只做桶导出，
 * 保证「feature 内单测的入口」与「数据层使用的规则」是同一份代码，不会漂移。
 */
export {
  browseBounds,
  BrowseBounds,
  compareHits,
  hitRanges,
  matchLevel,
  normalizeTerm,
  rangesForField
} from 'commons_data';
export {
  HitField,
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
} from 'commons_data';
