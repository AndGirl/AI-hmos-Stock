import { describe, expect, it } from '@ohos/hypium';
import { QuotePatch } from '../main/ets/model/QuoteModels';
import {
  BAD_FRAME_RESUBSCRIBE_THRESHOLD,
  FrameReference,
  FrameStats,
  FrameValidator,
  hasMutableField
} from '../main/ets/rules/FrameValidator';

function frame(code: string, time: number, last: number): QuotePatch {
  const item: QuotePatch = { code: code, snapshotTime: time, last: last, seq: time };
  return item;
}

/**
 * M9-5 / AC-110 帧校验单测：
 * 时间回退、价格越界、超涨跌停、空帧、连续 10 帧触发重订阅。
 */
export default function frameValidatorTest(): void {
  describe('FrameValidator', () => {
    it('accept_normal_frame', 0, () => {
      const validator: FrameValidator = new FrameValidator();
      const reference: FrameReference = new FrameReference(11, 9);
      expect(validator.validate(frame('600519', 1000, 10), reference)).assertEqual('ok');
      expect(validator.snapshotStats().accepted).assertEqual(1);
      expect(validator.snapshotStats().dropped()).assertEqual(0);
    });

    it('drop_stale_time', 0, () => {
      const validator: FrameValidator = new FrameValidator();
      const reference: FrameReference = new FrameReference(null, null);
      expect(validator.validate(frame('600519', 2000, 10), reference)).assertEqual('ok');
      // 时间等于上一条 → 回退（要求严格递增）
      expect(validator.validate(frame('600519', 2000, 10.1), reference)).assertEqual('stale_time');
      // 时间早于上一条 → 回退
      expect(validator.validate(frame('600519', 1500, 10.2), reference)).assertEqual('stale_time');
      expect(validator.snapshotStats().staleTime).assertEqual(2);
      // 时间水位不因丢弃而回退
      expect(validator.validate(frame('600519', 2500, 10.3), reference)).assertEqual('ok');
    });

    it('drop_price_out_of_range', 0, () => {
      const validator: FrameValidator = new FrameValidator();
      const reference: FrameReference = new FrameReference(null, null);
      expect(validator.validate(frame('600519', 1000, 0), reference)).assertEqual('price_invalid');
      expect(validator.validate(frame('600519', 1001, 100001), reference)).assertEqual('price_invalid');
      expect(validator.snapshotStats().priceInvalid).assertEqual(2);
    });

    it('drop_price_out_of_limit', 0, () => {
      const validator: FrameValidator = new FrameValidator();
      const reference: FrameReference = new FrameReference(11, 9);
      // 12 超出涨停 11 的 2% 容差（11.22）
      expect(validator.validate(frame('600519', 1000, 12), reference)).assertEqual('price_out_of_limit');
      // 8.5 超出跌停 9 的 2% 容差（8.82）
      expect(validator.validate(frame('600519', 1001, 8.5), reference)).assertEqual('price_out_of_limit');
      expect(validator.snapshotStats().priceOutOfLimit).assertEqual(2);
    });

    it('drop_empty_frame', 0, () => {
      const validator: FrameValidator = new FrameValidator();
      const reference: FrameReference = new FrameReference(null, null);
      const empty: QuotePatch = { code: '600519', snapshotTime: 1000 };
      expect(hasMutableField(empty)).assertFalse();
      expect(validator.validate(empty, reference)).assertEqual('empty_frame');
      expect(validator.snapshotStats().emptyFrame).assertEqual(1);
    });

    it('resubscribe_after_ten_bad_frames', 0, () => {
      const validator: FrameValidator = new FrameValidator();
      const reference: FrameReference = new FrameReference(11, 9);
      // 先用一条正常帧建立水位
      expect(validator.validate(frame('600519', 1000, 10), reference)).assertEqual('ok');
      for (let i = 0; i < BAD_FRAME_RESUBSCRIBE_THRESHOLD; i++) {
        // 全部早于水位 → stale
        expect(validator.validate(frame('600519', 900 + i, 10), reference)).assertEqual('stale_time');
      }
      expect(validator.shouldResubscribe('600519')).assertTrue();
      // 一条正常帧清零连续异常计数
      expect(validator.validate(frame('600519', 3000, 10), reference)).assertEqual('ok');
      expect(validator.shouldResubscribe('600519')).assertFalse();
    });

    it('normal_frame_resets_consecutive_counter', 0, () => {
      const validator: FrameValidator = new FrameValidator();
      const reference: FrameReference = new FrameReference(null, null);
      for (let i = 0; i < BAD_FRAME_RESUBSCRIBE_THRESHOLD - 1; i++) {
        validator.validate(frame('000001', 100, 0), reference);
      }
      expect(validator.shouldResubscribe('000001')).assertFalse();
      validator.validate(frame('000001', 200, 11), reference);
      expect(validator.shouldResubscribe('000001')).assertFalse();
    });

    it('reset_code_clears_time_watermark', 0, () => {
      const validator: FrameValidator = new FrameValidator();
      const reference: FrameReference = new FrameReference(null, null);
      validator.validate(frame('600519', 5000, 10), reference);
      validator.resetCode('600519');
      // 重订阅后新通道时间更早也应被接受（不再误判回退）
      expect(validator.validate(frame('600519', 1000, 10), reference)).assertEqual('ok');
    });

    it('stats_reports_counts', 0, () => {
      const validator: FrameValidator = new FrameValidator();
      const reference: FrameReference = new FrameReference(11, 9);
      validator.validate(frame('600519', 1000, 10), reference);
      validator.validate(frame('600519', 900, 10), reference);
      validator.validate(frame('600519', 1200, 0), reference);
      const stats: FrameStats = validator.snapshotStats();
      expect(stats.accepted).assertEqual(1);
      expect(stats.dropped()).assertEqual(2);
      expect(stats.describe().indexOf('accepted=1') >= 0).assertTrue();
    });
  });
}
