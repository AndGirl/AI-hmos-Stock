import { describe, expect, it } from '@ohos/hypium';
import { Position, PositionSummary } from '../main/ets/model/PositionModels';
import {
  applyWeights,
  compareNullable,
  computePosition,
  isSuspendedStatus,
  nextPositionSortDir,
  PositionBasis,
  sortPositions,
  summarizePositions,
  valuationPriceOf
} from '../main/ets/rules/PositionRules';

function basis(code: string, qty: number, cost: number, last: number | null, lastKnown: number | null,
  prevClose: number | null): PositionBasis {
  return new PositionBasis(code, code, qty, qty, cost, last, lastKnown, prevClose, 'open', '50012345',
    'withoutFee');
}

/**
 * M11-1 收益口径单测（AC-121）：市值/累计盈亏/盈亏比/当日盈亏/仓位/汇总/排序。
 * 纯函数，无设备依赖；样例与 `docs/phase2-position-metrics.md` 的 3 组复核一致。
 */
export default function positionRulesTest(): void {
  describe('PositionRules', () => {
    it('market_value_pnl_and_ratio', 0, () => {
      const row: Position = computePosition(basis('600519', 500, 1500, 1680, 1680, 1660));
      expect(row.qty).assertEqual(500);
      expect(row.last).assertEqual(1680);
      expect(row.marketValue).assertEqual(840000);
      expect(row.pnl).assertEqual(90000);
      expect(row.pnlRatio).assertEqual(12);
      expect(row.dayPnl).assertEqual(10000);
      expect(row.costBasis).assertEqual('withoutFee');
    });

    it('zero_qty_has_no_value', 0, () => {
      const row: Position = computePosition(basis('600519', 0, 1500, 1680, 1680, 1660));
      expect(row.marketValue === null).assertTrue();
      expect(row.pnl === null).assertTrue();
      expect(row.pnlRatio === null).assertTrue();
      expect(row.dayPnl === null).assertTrue();
    });

    it('negative_cost_ratio_is_null', 0, () => {
      const row: Position = computePosition(basis('600519', 100, -10, 1680, 1680, 1660));
      expect(row.marketValue).assertEqual(168000);
      // 成本额 = -1000：累计盈亏仍可算，但盈亏率无意义
      expect(row.pnl).assertEqual(169000);
      expect(row.pnlRatio === null).assertTrue();
    });

    it('zero_cost_ratio_is_null', 0, () => {
      const row: Position = computePosition(basis('600519', 100, 0, 1680, 1680, 1660));
      expect(row.pnl).assertEqual(168000);
      expect(row.pnlRatio === null).assertTrue();
    });

    it('suspended_uses_last_known_and_zero_day_pnl', 0, () => {
      const input: PositionBasis = new PositionBasis('601318', '中国平安', 1000, 1000, 45, null, 48.9,
        null, 'suspended', '50012345', 'withoutFee');
      const row: Position = computePosition(input);
      expect(row.last).assertEqual(48.9);
      expect(row.marketValue).assertEqual(48900);
      expect(row.dayPnl).assertEqual(0);
      expect(isSuspendedStatus(row.status)).assertTrue();
    });

    it('missing_price_marks_unvalued', 0, () => {
      const row: Position = computePosition(basis('601318', 1000, 45, null, 0, null));
      expect(row.last === null).assertTrue();
      expect(row.marketValue === null).assertTrue();
      expect(row.pnl === null).assertTrue();
      const rows: Position[] = [row];
      applyWeights(rows);
      expect(rows[0].weight === null).assertTrue();
      const summary: PositionSummary = summarizePositions(rows);
      expect(summary.unvalued).assertEqual(1);
      expect(summary.marketValue).assertEqual(0);
      expect(summary.costTotal).assertEqual(45000);
    });

    it('valuation_price_prefers_last_then_fallback', 0, () => {
      expect(valuationPriceOf(10, 9)).assertEqual(10);
      expect(valuationPriceOf(null, 9)).assertEqual(9);
      expect(valuationPriceOf(0, 9)).assertEqual(9);
      expect(valuationPriceOf(null, 0) === null).assertTrue();
    });

    it('weights_share_portfolio', 0, () => {
      const a: Position = computePosition(basis('600519', 500, 1500, 1680, 1680, 1660));
      const b: Position = computePosition(basis('601318', 1000, 45, 48.9, 48.9, 48));
      const rows: Position[] = [a, b];
      applyWeights(rows);
      // 840000 / (840000 + 48900) = 94.5%
      expect(rows[0].weight).assertEqual(94.5);
      expect(rows[1].weight).assertEqual(5.5);
    });

    it('summary_totals_and_ratio', 0, () => {
      const a: Position = computePosition(basis('600519', 500, 1500, 1680, 1680, 1660));
      const b: Position = computePosition(basis('601318', 1000, 45, 48.9, 48.9, 48));
      const summary: PositionSummary = summarizePositions([a, b]);
      expect(summary.count).assertEqual(2);
      expect(summary.marketValue).assertEqual(888900);
      expect(summary.costTotal).assertEqual(795000);
      expect(summary.totalPnl).assertEqual(93900);
      expect(summary.dayPnl).assertEqual(10900);
      // 93900 / 795000 = 11.81%
      expect(summary.ratio()).assertEqual(11.81);
    });

    it('summary_ratio_null_when_cost_zero', 0, () => {
      const summary: PositionSummary = new PositionSummary(0, 0, 0, 0, 0, 0);
      expect(summary.ratio() === null).assertTrue();
    });

    it('invalid_prev_close_gives_zero_day_pnl', 0, () => {
      const row: Position = computePosition(basis('600519', 500, 1500, 1680, 1680, 0));
      expect(row.dayPnl).assertEqual(0);
    });

    it('sort_market_value_desc_nulls_last', 0, () => {
      const a: Position = computePosition(basis('600519', 500, 1500, 1680, 1680, 1660));
      const b: Position = computePosition(basis('601318', 1000, 45, 48.9, 48.9, 48));
      const c: Position = computePosition(basis('000858', 200, 150, null, 0, null));
      const sorted: Position[] = sortPositions([a, b, c], 'marketValue', 'desc');
      expect(sorted[0].code).assertEqual('600519');
      expect(sorted[1].code).assertEqual('601318');
      expect(sorted[2].code).assertEqual('000858');
    });

    it('sort_pnl_asc_nulls_last', 0, () => {
      const win: Position = computePosition(basis('600519', 500, 1500, 1680, 1680, 1660));
      const loss: Position = computePosition(basis('601318', 1000, 50, 48.9, 48.9, 48));
      const none: Position = computePosition(basis('000858', 200, 150, null, 0, null));
      const sorted: Position[] = sortPositions([win, loss, none], 'pnl', 'asc');
      expect(sorted[0].code).assertEqual('601318');
      expect(sorted[1].code).assertEqual('600519');
      expect(sorted[2].code).assertEqual('000858');
    });

    it('sort_cycle_desc_asc_none', 0, () => {
      expect(nextPositionSortDir('none')).assertEqual('desc');
      expect(nextPositionSortDir('desc')).assertEqual('asc');
      expect(nextPositionSortDir('asc')).assertEqual('none');
      const rows: Position[] = [computePosition(basis('601318', 1000, 45, 48.9, 48.9, 48))];
      expect(sortPositions(rows, 'pnl', 'none').length).assertEqual(1);
    });

    it('compare_nullable_keeps_nulls_last_both_dirs', 0, () => {
      expect(compareNullable(null, 1, 'desc') > 0).assertTrue();
      expect(compareNullable(null, 1, 'asc') > 0).assertTrue();
      expect(compareNullable(1, 2, 'desc') > 0).assertTrue();
      expect(compareNullable(1, 2, 'asc') < 0).assertTrue();
      expect(compareNullable(2, 2, 'desc')).assertEqual(0);
    });
  });
}
