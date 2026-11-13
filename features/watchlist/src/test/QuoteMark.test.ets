import { describe, it, expect } from '@ohos/hypium';
import { ARROW_DOWN, ARROW_UP, arrowOfDir, arrowOfTone, arrowOfValue } from 'commons_basic';

/**
 * M12-3 涨跌符号单测（AC-123）：
 * 涨/跌/平/空值四类，覆盖自选行、详情 ValueTone、原始数值三个入口。
 */
export default function quoteMarkTest(): void {
  describe('QuoteMark', () => {
    it('case_dir_up_down_flat', 0, () => {
      expect(arrowOfDir(1)).assertEqual(ARROW_UP);
      expect(arrowOfDir(-1)).assertEqual(ARROW_DOWN);
      expect(arrowOfDir(0)).assertEqual('');
    });

    it('case_tone_up_down_flat_none', 0, () => {
      expect(arrowOfTone('up')).assertEqual(ARROW_UP);
      expect(arrowOfTone('down')).assertEqual(ARROW_DOWN);
      expect(arrowOfTone('flat')).assertEqual('');
      expect(arrowOfTone('none')).assertEqual('');
    });

    it('case_value_sign', 0, () => {
      expect(arrowOfValue(2.35)).assertEqual(ARROW_UP);
      expect(arrowOfValue(-0.12)).assertEqual(ARROW_DOWN);
      expect(arrowOfValue(0)).assertEqual('');
    });

    it('case_value_nullish', 0, () => {
      expect(arrowOfValue(null)).assertEqual('');
      expect(arrowOfValue(undefined)).assertEqual('');
    });

    it('case_symbols_are_not_ascii_plus_minus', 0, () => {
      // 必须是 ▲/▼，不能退回 +/-（颜色之外的第二重区分）。
      expect(ARROW_UP).assertEqual('▲');
      expect(ARROW_DOWN).assertEqual('▼');
    });
  });
}
