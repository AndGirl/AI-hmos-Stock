/**
 * 限流与降级策略（M9-4 / AC-109）。
 *
 * 三档：
 * - `push`      正常推送；
 * - `throttled` 收到 429 后降频到 5s（仍走推送通道），并置「已降频」提示；
 * - `polling`   连续 3 次 429 后退化为 HTTP 批量快照轮询（5s 一次）。
 *
 * 恢复条件（AC-109）：持续 `RECOVER_QUIET_MS`（60s）无 429 自动回到 `push`。
 * 纯逻辑 + 注入 `now`，不持有定时器，便于单测穷举（定时器仍在 commons/data 的 bus 层）。
 */

export type QuoteMode = 'push' | 'throttled' | 'polling';

/** 降频后的推送间隔。 */
export const THROTTLE_INTERVAL_MS: number = 5000;

/** 轮询模式下的快照间隔。 */
export const POLL_INTERVAL_MS: number = 5000;

/** 连续 429 达到此次数转轮询。 */
export const RATE_LIMIT_STREAK_TO_POLL: number = 3;

/** 无 429 持续该时长即恢复。 */
export const RECOVER_QUIET_MS: number = 60000;

export class RateLimitState {
  mode: QuoteMode = 'push';
  /** 连续 429 次数。 */
  streak: number = 0;
  /** 本模式下建议的下次请求间隔。 */
  intervalMs: number = 0;
  /** 最近一次 429 的时间（0 表示从未）。 */
  lastLimitedAt: number = 0;
  /** 本轮降级开始时间（0 表示未降级）。 */
  degradedSince: number = 0;

  constructor() {
    this.intervalMs = THROTTLE_INTERVAL_MS;
  }
}

export class RateLimitPolicy {
  private state: RateLimitState = new RateLimitState();

  /** 当前模式。 */
  mode(): QuoteMode {
    return this.state.mode;
  }

  /** 当前建议间隔（push 模式返回 THROTTLE_INTERVAL_MS，仅作上界提示）。 */
  intervalMs(): number {
    return this.state.intervalMs;
  }

  streak(): number {
    return this.state.streak;
  }

  /** 是否处于降级（throttled / polling）。 */
  degraded(): boolean {
    return this.state.mode !== 'push';
  }

  /**
   * 收到 429：
   * - `retryAfterMs` 有值且大于 5s 时按服务端建议，否则用 5s 下限；
   * - 连续 3 次转轮询；
   * - 已降级时不再延长「降级开始时间」。
   */
  onRateLimited(retryAfterMs: number | undefined, now: number): QuoteMode {
    this.state.streak++;
    this.state.lastLimitedAt = now;
    if (this.state.degradedSince === 0) {
      this.state.degradedSince = now;
    }
    const suggested: number = retryAfterMs !== undefined && retryAfterMs > 0 ? retryAfterMs : 0;
    const next: QuoteMode = this.state.streak >= RATE_LIMIT_STREAK_TO_POLL ? 'polling' : 'throttled';
    this.state.mode = next;
    this.state.intervalMs = next === 'polling' ? POLL_INTERVAL_MS : Math.max(THROTTLE_INTERVAL_MS, suggested);
    return next;
  }

  /**
   * 每次成功送达一帧时调用（用于判断「60s 无 429」）。
   * 返回是否有模式变化（true 表示刚从降级恢复，调用方需要提示一次）。
   */
  onServed(now: number): boolean {
    if (this.state.mode === 'push') {
      return false;
    }
    if (this.state.lastLimitedAt > 0 && now - this.state.lastLimitedAt < RECOVER_QUIET_MS) {
      return false;
    }
    this.reset(now);
    return true;
  }

  /** 定时检查（无帧时也能恢复）：60s 无 429 即回 push。 */
  tick(now: number): boolean {
    return this.onServed(now);
  }

  /** 手动恢复（调试「恢复」按钮 / 重订阅成功）。 */
  reset(now: number): void {
    this.state.mode = 'push';
    this.state.streak = 0;
    this.state.intervalMs = THROTTLE_INTERVAL_MS;
    this.state.degradedSince = 0;
    this.state.lastLimitedAt = 0;
  }
}
