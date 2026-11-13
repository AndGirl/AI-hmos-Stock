import { describe, it, expect } from '@ohos/hypium';
import { SearchKind } from 'commons_data';
import {
  browseBounds,
  BrowseBounds,
  compareHits,
  hitRanges,
  HitRange,
  matchLevel,
  normalizeTerm,
  SEARCH_LEVEL_CODE_EXACT,
  SEARCH_LEVEL_CODE_PREFIX,
  SEARCH_LEVEL_INITIALS,
  SEARCH_LEVEL_NAME_CONTAINS,
  SEARCH_LEVEL_NAME_PREFIX,
  SEARCH_LEVEL_NONE,
  SEARCH_LEVEL_PINYIN,
  SEARCH_LEVEL_SECTOR,
  SearchEntry,
  SearchHit
} from '../main/ets/repository/MatchRules';

function entry(code: string, name: string, kind: SearchKind, pinyin: string, initials: string,
  sector: string): SearchEntry {
  return {
    code: code,
    name: name,
    kind: kind,
    market: 'SH',
    status: 'open',
    isNew: false,
    pinyin: pinyin,
    initials: initials,
    sector: sector,
    tags: [],
    staticPrice: 0,
    staticPct: 0
  };
}

function hit(code: string, level: number, amount: number): SearchHit {
  const value: SearchHit = new SearchHit();
  value.code = code;
  value.level = level;
  value.amount = amount;
  return value;
}

export default function searchRulesTest(): void {
  describe('SearchRules', () => {
    it('normalize_fullwidth_to_halfwidth', 0, () => {
      expect(normalizeTerm('６００５１９')).assertEqual('600519');
      expect(normalizeTerm('　600519　')).assertEqual('600519');
    });

    it('normalize_uppercase_and_trim', 0, () => {
      expect(normalizeTerm(' gzmt ')).assertEqual('GZMT');
      expect(normalizeTerm('GuiZhou')).assertEqual('GUIZHOU');
    });

    it('normalize_truncate_20', 0, () => {
      const long: string = '123456789012345678901234';
      expect(normalizeTerm(long).length).assertEqual(20);
    });

    it('level_L0_code_exact', 0, () => {
      const target: SearchEntry = entry('600519', '贵州茅台', 'stock', 'GUIZHOUMAOTAI', 'GZMT', '白酒');
      expect(matchLevel('600519', target)).assertEqual(SEARCH_LEVEL_CODE_EXACT);
      expect(matchLevel('600520', target)).assertEqual(SEARCH_LEVEL_NONE);
      expect(matchLevel('', target)).assertEqual(SEARCH_LEVEL_NONE);
    });

    it('level_L1_code_prefix', 0, () => {
      const target: SearchEntry = entry('600519', '贵州茅台', 'stock', 'GUIZHOUMAOTAI', 'GZMT', '白酒');
      expect(matchLevel('6005', target)).assertEqual(SEARCH_LEVEL_CODE_PREFIX);
      expect(matchLevel('600', target)).assertEqual(SEARCH_LEVEL_CODE_PREFIX);
      expect(matchLevel('519', target)).assertEqual(SEARCH_LEVEL_NONE);
    });

    it('level_L2_name_prefix', 0, () => {
      const target: SearchEntry = entry('600519', '贵州茅台', 'stock', 'GUIZHOUMAOTAI', 'GZMT', '白酒');
      expect(matchLevel('贵州', target)).assertEqual(SEARCH_LEVEL_NAME_PREFIX);
      expect(matchLevel('贵州茅台', target)).assertEqual(SEARCH_LEVEL_NAME_PREFIX);
    });

    it('level_L3_name_contains', 0, () => {
      const target: SearchEntry = entry('600519', '贵州茅台', 'stock', 'GUIZHOUMAOTAI', 'GZMT', '白酒');
      expect(matchLevel('茅台', target)).assertEqual(SEARCH_LEVEL_NAME_CONTAINS);
      expect(matchLevel('州茅', target)).assertEqual(SEARCH_LEVEL_NAME_CONTAINS);
    });

    it('level_L4_pinyin', 0, () => {
      const target: SearchEntry = entry('600519', '贵州茅台', 'stock', 'GUIZHOUMAOTAI', 'GZMT', '白酒');
      expect(matchLevel('GUIZHOU', target)).assertEqual(SEARCH_LEVEL_PINYIN);
      expect(matchLevel('MAOTAI', target)).assertEqual(SEARCH_LEVEL_NONE);
      expect(matchLevel('ZHOU', target)).assertEqual(SEARCH_LEVEL_NONE);
    });

    it('level_L5_initials', 0, () => {
      const target: SearchEntry = entry('600519', '贵州茅台', 'stock', 'GUIZHOUMAOTAI', 'GZMT', '白酒');
      expect(matchLevel('GZMT', target)).assertEqual(SEARCH_LEVEL_INITIALS);
      expect(matchLevel('GZ', target)).assertEqual(SEARCH_LEVEL_INITIALS);
    });

    it('level_L6_sector_only_for_sector_entry', 0, () => {
      const sector: SearchEntry = entry('BK0001', '白酒', 'sector', 'BAIJIU', 'BJ', '白酒');
      const stock: SearchEntry = entry('600888', '茅台镇酒业', 'stock', 'MAOTAIZHENJIUYE', 'MTZJY', '白酒');
      expect(matchLevel('白酒', sector)).assertEqual(SEARCH_LEVEL_SECTOR);
      expect(matchLevel('BAIJIU', sector)).assertEqual(SEARCH_LEVEL_SECTOR);
      expect(matchLevel('BJ', sector)).assertEqual(SEARCH_LEVEL_SECTOR);
      expect(matchLevel('白酒', stock)).assertEqual(SEARCH_LEVEL_NONE);
    });

    it('level_L2_before_L3_same_term', 0, () => {
      const prefix: SearchEntry = entry('600519', '贵州茅台', 'stock', 'GUIZHOUMAOTAI', 'GZMT', '白酒');
      const contains: SearchEntry = entry('600890', '中华茅台镇酒业', 'stock', 'ZHONGHUAMAOTAIZHEN', 'ZHMTZ', '白酒');
      expect(matchLevel('茅台', prefix)).assertEqual(SEARCH_LEVEL_NAME_CONTAINS);
      expect(matchLevel('茅台', contains)).assertEqual(SEARCH_LEVEL_NAME_CONTAINS);
      expect(matchLevel('贵州', prefix)).assertEqual(SEARCH_LEVEL_NAME_PREFIX);
    });

    it('compare_level_then_amount_then_code', 0, () => {
      const l2: SearchHit = hit('600519', SEARCH_LEVEL_NAME_PREFIX, 100);
      const l3: SearchHit = hit('600888', SEARCH_LEVEL_NAME_CONTAINS, 9999);
      expect(compareHits(l2, l3) < 0).assertTrue();
      const big: SearchHit = hit('600000', SEARCH_LEVEL_NAME_PREFIX, 200);
      expect(compareHits(big, l2) < 0).assertTrue();
      const sameA: SearchHit = hit('600001', SEARCH_LEVEL_NAME_PREFIX, 100);
      const sameB: SearchHit = hit('600002', SEARCH_LEVEL_NAME_PREFIX, 100);
      expect(compareHits(sameA, sameB) < 0).assertTrue();
    });

    it('hit_ranges_code_and_name', 0, () => {
      const target: SearchEntry = entry('600519', '贵州茅台贵州', 'stock', 'GUIZHOUMAOTAI', 'GZMT', '白酒');
      const codeRanges: HitRange[] = hitRanges('6005', target, SEARCH_LEVEL_CODE_PREFIX);
      expect(codeRanges.length).assertEqual(1);
      expect(codeRanges[0].field).assertEqual('code');
      expect(codeRanges[0].start).assertEqual(0);
      expect(codeRanges[0].end).assertEqual(4);

      const nameRanges: HitRange[] = hitRanges('贵州', target, SEARCH_LEVEL_NAME_CONTAINS);
      expect(nameRanges.length).assertEqual(2);
      expect(nameRanges[0].start).assertEqual(0);
      expect(nameRanges[1].start).assertEqual(4);
    });

    it('hit_ranges_pinyin_and_bounds', 0, () => {
      const target: SearchEntry = entry('600519', '贵州茅台', 'stock', 'GUIZHOUMAOTAI', 'GZMT', '白酒');
      const pinyinRanges: HitRange[] = hitRanges('GUIZHOU', target, SEARCH_LEVEL_PINYIN);
      expect(pinyinRanges.length).assertEqual(1);
      expect(pinyinRanges[0].end).assertEqual(7);
      const none: HitRange[] = hitRanges('', target, SEARCH_LEVEL_NONE);
      expect(none.length).assertEqual(0);
    });

    it('browse_bounds_first_page', 0, () => {
      const bounds: BrowseBounds = browseBounds(80, 0, 20);
      expect(bounds.start).assertEqual(0);
      expect(bounds.end).assertEqual(20);
      expect(bounds.hasMore).assertTrue();
    });

    it('browse_bounds_last_page', 0, () => {
      const bounds: BrowseBounds = browseBounds(80, 60, 20);
      expect(bounds.start).assertEqual(60);
      expect(bounds.end).assertEqual(80);
      expect(bounds.hasMore).assertFalse();
    });

    it('browse_bounds_clamp_offset', 0, () => {
      const over: BrowseBounds = browseBounds(80, 100, 20);
      expect(over.start).assertEqual(80);
      expect(over.end).assertEqual(80);
      expect(over.hasMore).assertFalse();
      const negative: BrowseBounds = browseBounds(80, -5, 20);
      expect(negative.start).assertEqual(0);
      expect(negative.end).assertEqual(20);
    });

    it('browse_bounds_empty_total', 0, () => {
      const bounds: BrowseBounds = browseBounds(0, 0, 20);
      expect(bounds.end).assertEqual(0);
      expect(bounds.hasMore).assertFalse();
    });
  });
}
