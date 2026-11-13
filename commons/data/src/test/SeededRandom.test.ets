import { describe, expect, it } from '@ohos/hypium';
import { hashSeed, SESSION_SEED, SeededRandom } from '../main/ets/mock/SeededRandom';

/**
 * M9-7 确定性随机单测：
 * 同种子同序列 100% 可复现（这是「假数据可重放、后端可对齐」的地基），
 * 不同 code 派生不同随机流（各标的走势互不干扰）。
 */
export default function seededRandomTest(): void {
  describe('SeededRandom', () => {
    it('same_seed_same_sequence', 0, () => {
      const a: SeededRandom = new SeededRandom(SESSION_SEED);
      const b: SeededRandom = new SeededRandom(SESSION_SEED);
      for (let i = 0; i < 64; i++) {
        expect(a.next()).assertEqual(b.next());
      }
    });

    it('different_seed_diverges', 0, () => {
      const a: SeededRandom = new SeededRandom(1);
      const b: SeededRandom = new SeededRandom(2);
      let same: number = 0;
      for (let i = 0; i < 64; i++) {
        if (a.next() === b.next()) {
          same++;
        }
      }
      expect(same).assertEqual(0);
    });

    it('next_in_unit_interval', 0, () => {
      const rnd: SeededRandom = new SeededRandom(SESSION_SEED);
      for (let i = 0; i < 256; i++) {
        const value: number = rnd.next();
        expect(value >= 0 && value < 1).assertTrue();
      }
    });

    it('int_stays_in_range', 0, () => {
      const rnd: SeededRandom = new SeededRandom(42);
      for (let i = 0; i < 256; i++) {
        const value: number = rnd.int(200);
        expect(value >= 0 && value < 200).assertTrue();
      }
    });

    it('between_stays_in_range', 0, () => {
      const rnd: SeededRandom = new SeededRandom(7);
      for (let i = 0; i < 128; i++) {
        const value: number = rnd.between(-1, 1);
        expect(value >= -1 && value < 1).assertTrue();
      }
    });

    it('hash_is_stable_and_code_specific', 0, () => {
      expect(hashSeed('600519')).assertEqual(hashSeed('600519'));
      expect(hashSeed('600519') === hashSeed('000001')).assertFalse();
    });

    it('per_code_streams_are_independent', 0, () => {
      // 与 MockQuoteProvider 同算法：hashSeed(code) ^ SESSION_SEED
      const a: SeededRandom = new SeededRandom(hashSeed('600519') ^ SESSION_SEED);
      const b: SeededRandom = new SeededRandom(hashSeed('000001') ^ SESSION_SEED);
      expect(a.next() === b.next()).assertFalse();
    });
  });
}
