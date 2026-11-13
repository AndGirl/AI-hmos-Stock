import { describe, expect, it } from '@ohos/hypium';
import { QuotePatch } from '../main/ets/model/QuoteModels';
import { decideSeq, mergePatch, SeqDecision, seqOf } from '../main/ets/rules/QuoteMergeRules';

function patch(code: string, seq: number | undefined, last: number, time: number): QuotePatch {
  const item: QuotePatch = { code: code, snapshotTime: time, last: last };
  if (seq !== undefined) {
    item.seq = seq;
  }
  return item;
}

/**
 * M9-3 / AC-108 帧序号与合窗单测：乱序丢弃、重复丢弃、缺省 0 兼容、合窗取最大 seq。
 */
export default function quoteMergeRulesTest(): void {
  describe('QuoteMergeRules', () => {
    it('accept_increasing_seq', 0, () => {
      const first: SeqDecision = decideSeq(0, 1);
      expect(first.verdict).assertEqual('accept');
      expect(first.nextSeq).assertEqual(1);
      expect(first.accepted()).assertTrue();
      const second: SeqDecision = decideSeq(1, 2);
      expect(second.verdict).assertEqual('accept');
      expect(second.nextSeq).assertEqual(2);
    });

    it('drop_duplicate_seq', 0, () => {
      const decision: SeqDecision = decideSeq(5, 5);
      expect(decision.verdict).assertEqual('duplicate');
      expect(decision.accepted()).assertFalse();
      // 水位不变
      expect(decision.nextSeq).assertEqual(5);
    });

    it('drop_out_of_order_seq', 0, () => {
      const decision: SeqDecision = decideSeq(9, 4);
      expect(decision.verdict).assertEqual('out_of_order');
      expect(decision.accepted()).assertFalse();
      expect(decision.nextSeq).assertEqual(9);
    });

    it('unsequenced_is_accepted_and_keeps_watermark', 0, () => {
      const missing: SeqDecision = decideSeq(7, undefined);
      expect(missing.verdict).assertEqual('unsequenced');
      expect(missing.accepted()).assertTrue();
      expect(missing.nextSeq).assertEqual(7);
      // 缺省视为 0（契约 v1.1）
      const zero: SeqDecision = decideSeq(7, 0);
      expect(zero.verdict).assertEqual('unsequenced');
      expect(zero.accepted()).assertTrue();
      expect(zero.nextSeq).assertEqual(7);
    });

    it('skip_seq_still_accepted', 0, () => {
      // 跳帧（3 → 8）不产生脏数据：接受并推进水位
      const decision: SeqDecision = decideSeq(3, 8);
      expect(decision.verdict).assertEqual('accept');
      expect(decision.nextSeq).assertEqual(8);
    });

    it('merge_takes_max_seq_and_latest_fields', 0, () => {
      const base: QuotePatch = patch('600519', 2, 10, 1000);
      base.volume = 100;
      const next: QuotePatch = patch('600519', 5, 11, 1200);
      const merged: QuotePatch = mergePatch(base, next);
      expect(merged.seq).assertEqual(5);
      expect(merged.last).assertEqual(11);
      expect(merged.snapshotTime).assertEqual(1200);
      // next 未带的字段保留 base 的值（空值不覆盖）
      expect(merged.volume).assertEqual(100);
    });

    it('merge_keeps_undefined_fields', 0, () => {
      const base: QuotePatch = patch('000001', 1, 11, 1000);
      base.pct = 1.5;
      base.status = 'open';
      const next: QuotePatch = patch('000001', 2, 11.2, 1100);
      const merged: QuotePatch = mergePatch(base, next);
      expect(merged.pct).assertEqual(1.5);
      expect(merged.status).assertEqual('open');
      expect(merged.last).assertEqual(11.2);
    });

    it('seq_of_defaults_to_zero', 0, () => {
      expect(seqOf(patch('600519', undefined, 10, 1))).assertEqual(0);
      expect(seqOf(patch('600519', 4, 10, 1))).assertEqual(4);
    });
  });
}
