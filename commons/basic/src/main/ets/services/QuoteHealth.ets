import { AppStorageV2 } from '@kit.ArkUI';

/** 行情通道运行模式（与 `commons_data` 的 `QuoteMode` 结构一致，避免反向依赖）。 */
export type QuoteHealthMode = 'push' | 'throttled' | 'polling';

/** 行情 token 状态（M9-2：401 刷新一次仍失败 → unauthorized）。 */
export type QuoteTokenState = 'none' | 'valid' | 'refreshing' | 'unauthorized';

/**
 * 行情通道健康状况（M9-4 / M9-5 的可观测出口）。
 *
 * 为什么单独一个对象：`ConnectionHub` 只管网络升降级（online/weak/offline/delayed），
 * 行情通道还有「限流降频」「鉴权失败」「异常帧丢弃」三类与网络无关的状态。
 * 混进 `NetState` 会让全站连接状态机回归，所以独立成一个 @ObservedV2 单例，
 * 由 `GlobalBanner` 按优先级渲染（不新增第二条 banner，CC-7.3）。
 *
 * 只存枚举/计数，不存中文文案（文案在 View 层走资源）。
 */
@ObservedV2
export class QuoteHealth {
  /** 推送节奏：正常 / 降频 / 轮询。 */
  @Trace mode: QuoteHealthMode = 'push';
  /** 连续 429 次数。 */
  @Trace streak: number = 0;
  /** 被丢弃的异常帧（时间回退/越界/超限/空帧）。 */
  @Trace dropped: number = 0;
  /** 已接受的帧数。 */
  @Trace accepted: number = 0;
  /** token 状态。 */
  @Trace token: QuoteTokenState = 'none';
  /** 最近一次错误原因（枚举字符串，不落中文）。 */
  @Trace lastError: string = '';
  /** 版本号：视图可据此做一次性动作。 */
  @Trace changeSeq: number = 0;
  @Trace changedAt: number = 0;

  /** 是否处于降级（限流）。 */
  degraded(): boolean {
    return this.mode !== 'push';
  }

  /** 是否因鉴权失败停止更新。 */
  unauthorized(): boolean {
    return this.token === 'unauthorized';
  }

  /** 提示条是否需要显示（降级或未授权）。 */
  bannerVisible(): boolean {
    return this.degraded() || this.unauthorized();
  }

  markMode(mode: QuoteHealthMode, streak: number): void {
    if (this.mode === mode && this.streak === streak) {
      return;
    }
    this.mode = mode;
    this.streak = streak;
    this.bump();
  }

  markToken(state: QuoteTokenState): void {
    if (this.token === state) {
      return;
    }
    this.token = state;
    this.bump();
  }

  markAccepted(count: number): void {
    this.accepted += count;
  }

  markDropped(count: number): void {
    if (count <= 0) {
      return;
    }
    this.dropped += count;
    this.bump();
  }

  markError(reason: string): void {
    this.lastError = reason;
    this.bump();
  }

  /** 调试「恢复」/重订阅成功后回到正常态（计数不清零，便于验收对比）。 */
  markRecovered(): void {
    this.mode = 'push';
    this.streak = 0;
    this.lastError = '';
    this.bump();
  }

  /** 全量重置（调试「重置」）。 */
  reset(): void {
    this.mode = 'push';
    this.streak = 0;
    this.dropped = 0;
    this.accepted = 0;
    this.token = 'none';
    this.lastError = '';
    this.bump();
  }

  /** 稳定串：`mode=push streak=0 acc=12 drop=3 token=valid`。 */
  describe(): string {
    return `mode=${this.mode} streak=${this.streak} acc=${this.accepted} ` +
      `drop=${this.dropped} token=${this.token}`;
  }

  private bump(): void {
    this.changeSeq++;
    this.changedAt = Date.now();
  }
}

/** 全局唯一实例（与 ConnectionHub 同构）。 */
export class QuoteHealthHost {
  private static service: QuoteHealth | undefined = undefined;

  static getService(): QuoteHealth {
    if (QuoteHealthHost.service === undefined) {
      const connected: QuoteHealth | undefined = AppStorageV2.connect(
        QuoteHealth,
        'quote_health_v1',
        () => new QuoteHealth()
      );
      QuoteHealthHost.service = connected !== undefined ? connected : new QuoteHealth();
    }
    return QuoteHealthHost.service;
  }
}
