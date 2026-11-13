import { describe, expect, it } from '@ohos/hypium';
import {
  POLL_INTERVAL_MS,
  QuoteMode,
  RATE_LIMIT_STREAK_TO_POLL,
  RateLimitPolicy,
  RECOVER_QUIET_MS,
  THROTTLE_INTERVAL_MS
} from '../main/ets/rules/RateLimitRules';

/**
 * M9-4 / AC-109 限流降级单测：429 → 降频 5s → 连续 3 次转轮询 → 60s 无 429 恢复。
 */
export default function rateLimitRulesTest(): void {
  describe('RateLimitRules', () => {
    it('first_429_enters_throttled', 0, () => {
      const policy: RateLimitPolicy = new RateLimitPolicy();
      expect(policy.mode()).assertEqual('push');
      expect(policy.degraded()).assertFalse();
      const mode: QuoteMode = policy.onRateLimited(undefined, 1000);
      expect(mode).assertEqual('throttled');
      expect(policy.intervalMs()).assertEqual(THROTTLE_INTERVAL_MS);
      expect(policy.streak()).assertEqual(1);
      expect(policy.degraded()).assertTrue();
    });

    it('server_retry_after_is_honoured', 0, () => {
      const policy: RateLimitPolicy = new RateLimitPolicy();
      policy.onRateLimited(8000, 1000);
      expect(policy.intervalMs()).assertEqual(8000);
      // 小于 5s 的建议按 5s 下限
      const second: RateLimitPolicy = new RateLimitPolicy();
      second.onRateLimited(1200, 1000);
      expect(second.intervalMs()).assertEqual(THROTTLE_INTERVAL_MS);
    });

    it('three_429_switches_to_polling', 0, () => {
      const policy: RateLimitPolicy = new RateLimitPolicy();
      for (let i = 0; i < RATE_LIMIT_STREAK_TO_POLL - 1; i++) {
        policy.onRateLimited(undefined, 1000 + i);
      }
      expect(policy.mode()).assertEqual('throttled');
      const mode: QuoteMode = policy.onRateLimited(undefined, 2000);
      expect(mode).assertEqual('polling');
      expect(policy.intervalMs()).assertEqual(POLL_INTERVAL_MS);
      expect(policy.streak()).assertEqual(RATE_LIMIT_STREAK_TO_POLL);
    });

    it('recover_after_60s_quiet', 0, () => {
      const policy: RateLimitPolicy = new RateLimitPolicy();
      policy.onRateLimited(undefined, 10000);
      // 未满 60s：不恢复
      expect(policy.onServed(10000 + RECOVER_QUIET_MS - 1)).assertFalse();
      expect(policy.mode()).assertEqual('throttled');
      // 满 60s：恢复
      expect(policy.onServed(10000 + RECOVER_QUIET_MS)).assertTrue();
      expect(policy.mode()).assertEqual('push');
      expect(policy.streak()).assertEqual(0);
      expect(policy.degraded()).assertFalse();
    });

    it('recover_uses_last_429_not_first', 0, () => {
      const policy: RateLimitPolicy = new RateLimitPolicy();
      policy.onRateLimited(undefined, 1000);
      policy.onRateLimited(undefined, 40000);
      // 自最后一次 429 起算 60s
      expect(policy.onServed(40000 + RECOVER_QUIET_MS - 1)).assertFalse();
      expect(policy.onServed(40000 + RECOVER_QUIET_MS)).assertTrue();
    });

    it('push_mode_never_reports_recovered', 0, () => {
      const policy: RateLimitPolicy = new RateLimitPolicy();
      expect(policy.onServed(999999)).assertFalse();
      expect(policy.tick(999999)).assertFalse();
    });

    it('tick_recovers_without_frames', 0, () => {
      const policy: RateLimitPolicy = new RateLimitPolicy();
      policy.onRateLimited(undefined, 1000);
      expect(policy.tick(1000 + RECOVER_QUIET_MS)).assertTrue();
      expect(policy.mode()).assertEqual('push');
    });

    it('reset_clears_state', 0, () => {
      const policy: RateLimitPolicy = new RateLimitPolicy();
      policy.onRateLimited(undefined, 1000);
      policy.onRateLimited(undefined, 2000);
      policy.onRateLimited(undefined, 3000);
      expect(policy.mode()).assertEqual('polling');
      policy.reset(4000);
      expect(policy.mode()).assertEqual('push');
      expect(policy.streak()).assertEqual(0);
      expect(policy.intervalMs()).assertEqual(THROTTLE_INTERVAL_MS);
    });
  });
}
