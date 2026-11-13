import { describe, it, expect } from '@ohos/hypium';
import { nextViewMode, normalizeViewMode } from 'commons_basic';
import {
  baseCardColumns,
  CARD_MAX_COLUMNS,
  CARD_MIN_COLUMNS,
  CARD_PADDING,
  cardGapOf,
  computeCardColumns,
  computeCardMetrics,
  layoutViolations,
  metricColumnsOf,
  metricCountOf
} from '../main/ets/repository/CardMetrics';

/** 4 断点的代表性视口宽（sm=Mate 60 Pro 388、md/lg/xl 取各档中值）。 */
const BPS: string[] = ['sm', 'md', 'lg', 'xl'];
const VIEWPORTS: number[] = [388, 700, 1000, 1280];
const SCALES: number[] = [1.0, 1.3, 1.45];

/**
 * M8-1 卡片几何单测（AC-100）：
 * 12 组（4 断点 × 3 字号）布局断言 + 列数表 + 指标口径 + 虚线卡可见性。
 * 纯函数，无设备依赖（Hypium Local Test）。
 */
export default function cardMetricsTest(): void {
  describe('CardMetrics', () => {
    it('case_no_horizontal_overflow_12_combos', 0, () => {
      for (let b = 0; b < BPS.length; b++) {
        for (let s = 0; s < SCALES.length; s++) {
          const viewport: number = VIEWPORTS[b];
          const columns: number = computeCardColumns(BPS[b], viewport, SCALES[s]);
          const issues: string[] = layoutViolations(viewport, columns, SCALES[s]);
          expect(`${BPS[b]}@${SCALES[s]}x:${issues.join('|')}`).assertEqual(`${BPS[b]}@${SCALES[s]}x:`);
        }
      }
    });

    it('case_columns_table_at_base_font', 0, () => {
      expect(computeCardColumns('sm', 388, 1)).assertEqual(2);
      expect(computeCardColumns('md', 700, 1)).assertEqual(3);
      expect(computeCardColumns('lg', 1000, 1)).assertEqual(4);
      expect(computeCardColumns('xl', 1280, 1)).assertEqual(5);
    });

    it('case_columns_reduced_at_145', 0, () => {
      // 1.45× 只降列：md 3→2、lg 4→3、xl 放得下不降、sm 已到底保持 2。
      expect(computeCardColumns('md', 700, 1.45)).assertEqual(2);
      expect(computeCardColumns('lg', 1000, 1.45)).assertEqual(3);
      expect(computeCardColumns('xl', 1280, 1.45)).assertEqual(5);
      expect(computeCardColumns('sm', 388, 1.45)).assertEqual(2);
    });

    it('case_columns_floor_is_two', 0, () => {
      // 极窄窗也只能降到 2 列（禁止 1 列），且不允许出现负宽/溢出。
      const columns: number = computeCardColumns('sm', 320, 1.45);
      expect(columns).assertEqual(CARD_MIN_COLUMNS);
      expect(layoutViolations(320, columns, 1.45).length).assertEqual(0);
    });

    it('case_columns_never_exceeds_five', 0, () => {
      expect(baseCardColumns('xl')).assertEqual(CARD_MAX_COLUMNS);
      expect(computeCardMetrics(1600, 9, 1).columns).assertEqual(CARD_MAX_COLUMNS);
    });

    it('case_gap_follows_columns', 0, () => {
      expect(cardGapOf(2)).assertEqual(12);
      expect(cardGapOf(3)).assertEqual(12);
      expect(cardGapOf(4)).assertEqual(16);
      expect(cardGapOf(5)).assertEqual(16);
    });

    it('case_card_width_fills_viewport_without_overflow', 0, () => {
      for (let b = 0; b < BPS.length; b++) {
        const metrics = computeCardMetrics(VIEWPORTS[b], baseCardColumns(BPS[b]), 1);
        const used: number = metrics.cardW * metrics.columns + metrics.gap * (metrics.columns - 1) +
          metrics.padding * 2;
        expect(used <= VIEWPORTS[b]).assertTrue();
        // 取整后剩余不足一列（不会右边留出一大片空白）
        expect(VIEWPORTS[b] - used < metrics.columns).assertTrue();
        expect(metrics.padding).assertEqual(CARD_PADDING);
      }
    });

    it('case_metric_count_by_breakpoint', 0, () => {
      expect(metricCountOf('sm')).assertEqual(4);
      expect(metricCountOf('md')).assertEqual(6);
      expect(metricCountOf('lg')).assertEqual(6);
      expect(metricCountOf('xl')).assertEqual(6);
    });

    it('case_metric_columns_switch_by_card_width', 0, () => {
      expect(metricColumnsOf(172)).assertEqual(1);
      expect(metricColumnsOf(214)).assertEqual(2);
      expect(metricColumnsOf(236)).assertEqual(2);
    });

    it('case_view_mode_normalize_and_toggle', 0, () => {
      expect(normalizeViewMode('card')).assertEqual('card');
      expect(normalizeViewMode('list')).assertEqual('list');
      // 磁盘脏值/旧版本一律回列表
      expect(normalizeViewMode('')).assertEqual('list');
      expect(normalizeViewMode('grid')).assertEqual('list');
      expect(nextViewMode('list')).assertEqual('card');
      expect(nextViewMode('card')).assertEqual('list');
    });
  });
}
