import { describe, expect, it } from '@ohos/hypium';
import {
  BoardKind,
  boardOf,
  deriveLimitDown,
  deriveLimitUp,
  isStName,
  LIMIT_RATIO_BSE,
  LIMIT_RATIO_CHINEXT,
  LIMIT_RATIO_MAIN,
  LIMIT_RATIO_ST,
  LIMIT_RATIO_STAR,
  LimitPair,
  limitRatioOf,
  priceInRange,
  priceWithinLimits,
  resolveLimits
} from '../main/ets/rules/LimitRules';

/**
 * M9-5 / AC-110 涨跌停推导单测（CK-10 口径）：
 * 主板 10 / ST 5 / 科创 20 / 创业 20 / 北交所 30，服务端下发优先。
 */
export default function limitRulesTest(): void {
  describe('LimitRules', () => {
    it('board_by_code_prefix', 0, () => {
      expect(boardOf('600519')).assertEqual('main');
      expect(boardOf('000001')).assertEqual('main');
      expect(boardOf('002594')).assertEqual('main');
      expect(boardOf('688981')).assertEqual('star');
      expect(boardOf('300750')).assertEqual('chinext');
      expect(boardOf('301999')).assertEqual('chinext');
      expect(boardOf('920001')).assertEqual('bse');
      expect(boardOf('830799')).assertEqual('bse');
      expect(boardOf('430047')).assertEqual('bse');
    });

    it('ratio_five_board_samples', 0, () => {
      // 五组样本：主板 / ST / 科创板 / 创业板 / 北交所
      expect(limitRatioOf('600519', '贵州茅台')).assertEqual(LIMIT_RATIO_MAIN);
      expect(limitRatioOf('600519', 'ST 示范')).assertEqual(LIMIT_RATIO_ST);
      expect(limitRatioOf('688981', '中芯国际')).assertEqual(LIMIT_RATIO_STAR);
      expect(limitRatioOf('300750', '宁德时代')).assertEqual(LIMIT_RATIO_CHINEXT);
      expect(limitRatioOf('920001', '北交示范')).assertEqual(LIMIT_RATIO_BSE);
    });

    it('st_name_detection', 0, () => {
      expect(isStName('ST 示范')).assertTrue();
      expect(isStName('*ST 示范')).assertTrue();
      expect(isStName('贵州茅台')).assertFalse();
      expect(isStName(undefined)).assertFalse();
      expect(isStName('')).assertFalse();
    });

    it('derive_up_down_by_board', 0, () => {
      // 主板 ±10%
      expect(deriveLimitUp(10, '600519', '贵州茅台')).assertEqual(11);
      expect(deriveLimitDown(10, '600519', '贵州茅台')).assertEqual(9);
      // 创业板 ±20%
      expect(deriveLimitUp(10, '300750', '宁德时代')).assertEqual(12);
      expect(deriveLimitDown(10, '300750', '宁德时代')).assertEqual(8);
      // 科创板 ±20%
      expect(deriveLimitUp(10, '688981', '中芯国际')).assertEqual(12);
      // 北交所 ±30%
      expect(deriveLimitUp(10, '920001', '北交示范')).assertEqual(13);
      expect(deriveLimitDown(10, '920001', '北交示范')).assertEqual(7);
      // ST ±5%
      expect(deriveLimitUp(10, '600519', 'ST 示范')).assertEqual(10.5);
      expect(deriveLimitDown(10, '600519', 'ST 示范')).assertEqual(9.5);
    });

    it('derive_null_when_prev_close_invalid', 0, () => {
      expect(deriveLimitUp(null, '600519', '贵州茅台')).assertNull();
      expect(deriveLimitUp(0, '600519', '贵州茅台')).assertNull();
      expect(deriveLimitDown(-1, '600519', '贵州茅台')).assertNull();
    });

    it('server_value_wins', 0, () => {
      // 服务端下发 12.34 / 9.87（与本地规则不一致）：以服务端为准（CK-10）
      const pair: LimitPair = resolveLimits(10, '600519', '贵州茅台', 12.34, 9.87);
      expect(pair.limitUp).assertEqual(12.34);
      expect(pair.limitDown).assertEqual(9.87);
    });

    it('fallback_when_server_missing', 0, () => {
      const pair: LimitPair = resolveLimits(10, '300750', '宁德时代', null, undefined);
      expect(pair.limitUp).assertEqual(12);
      expect(pair.limitDown).assertEqual(8);
    });

    it('price_range_and_limit_tolerance', 0, () => {
      expect(priceInRange(0.01)).assertTrue();
      expect(priceInRange(100000)).assertTrue();
      expect(priceInRange(0)).assertFalse();
      expect(priceInRange(100000.01)).assertFalse();
      expect(priceInRange(null)).assertFalse();
      // 涨停 11：容差 2% 内（上限 11.22）接受，超出（11.5）拒绝
      expect(priceWithinLimits(11.2, 11, 9)).assertTrue();
      expect(priceWithinLimits(11.5, 11, 9)).assertFalse();
      // 跌停 9：容差 2% 内（下限 8.82）接受，超出（8.8 / 8.5）拒绝
      expect(priceWithinLimits(8.85, 11, 9)).assertTrue();
      expect(priceWithinLimits(8.8, 11, 9)).assertFalse();
      expect(priceWithinLimits(8.5, 11, 9)).assertFalse();
      // 无涨跌停（停牌/新股）只判价格区间
      expect(priceWithinLimits(12345, null, null)).assertTrue();
    });

    it('board_kind_is_string_union', 0, () => {
      const kind: BoardKind = boardOf('688981');
      expect(kind).assertEqual('star');
    });
  });
}
