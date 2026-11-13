import { describe, it, expect } from '@ohos/hypium';
import {
  DETAIL_BLOCK_HEIGHT,
  landscapeChartHeight,
  landscapeLeftWidth,
  landscapeMetricColumns,
  landscapeMetricRows,
  landscapeRightWidth
} from 'detail';

/**
 * M12-1 横屏几何单测（AC-122）：62/38 分栏、图表高度夹取、指标 6×2 / 1.3× 降 4 列。
 * 纯函数，无设备依赖。
 */
export default function detailLayoutTest(): void {
  describe('DetailLayoutLandscape', () => {
    it('case_split_62_38_on_940', 0, () => {
      const left: number = landscapeLeftWidth(940);
      const right: number = landscapeRightWidth(940);
      expect(left).assertEqual(583);
      expect(right).assertEqual(357);
      expect(left + right).assertEqual(940);
    });

    it('case_split_62_38_on_1280', 0, () => {
      const left: number = landscapeLeftWidth(1280);
      const right: number = landscapeRightWidth(1280);
      expect(left).assertEqual(794);
      expect(right).assertEqual(486);
      expect(left + right).assertEqual(1280);
    });

    it('case_chart_height_clamped', 0, () => {
      expect(landscapeChartHeight(665)).assertEqual(226);
      expect(landscapeChartHeight(400)).assertEqual(160);
      expect(landscapeChartHeight(1000)).assertEqual(260);
      expect(landscapeChartHeight(300)).assertEqual(160);
    });

    it('case_metric_columns_by_font_scale', 0, () => {
      expect(landscapeMetricColumns(1.0)).assertEqual(6);
      expect(landscapeMetricColumns(1.3)).assertEqual(4);
      expect(landscapeMetricColumns(1.45)).assertEqual(4);
    });

    it('case_metric_rows_two_at_base', 0, () => {
      expect(landscapeMetricRows(12, 6)).assertEqual(2);
      expect(landscapeMetricRows(12, 4)).assertEqual(3);
      expect(landscapeMetricRows(0, 6)).assertEqual(0);
    });

    it('case_portrait_block_height_unchanged', 0, () => {
      expect(DETAIL_BLOCK_HEIGHT).assertEqual(312);
    });
  });
}
