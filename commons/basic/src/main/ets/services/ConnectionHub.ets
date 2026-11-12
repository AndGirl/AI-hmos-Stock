import { AppStorageV2 } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'ConnLog';

/** 连接状态（CC-7.1）：online 正常 / weak 弱网 / offline 中断 / delayed 延迟。 */
export type NetState = 'online' | 'weak' | 'offline' | 'delayed';

/** 重连退避（CC-7.5）：1s → 2s → 4s → 8s → 16s → 30s 封顶，恢复后回 1s。 */
export const BACKOFF_MS: number[] = [1000, 2000, 4000, 8000, 16000, 30000];

/**
 * 全局连接状态机（CC-7）：唯一的重连调度器，页面不得自带重连定时器。
 * 迁移：连续 2 次心跳超时 → weak；≥3 次 → offline（并启动退避重连）；重连成功 → online。
 * 断线期间数据由 QuoteBus / DetailSubscriptionRegistry 在分发处冻结（CC-7.6）。
 */
@ObservedV2
export class ConnectionHub {
  @Trace state: NetState = 'online';
  /** 状态版本：视图侧可据此做一次性动作（如恢复后补一帧）。 */
  @Trace changeSeq: number = 0;
  @Trace changedAt: number = 0;
  @Trace retryCount: number = 0;

  private miss: number = 0;
  private retryIndex: number = 0;
  private retryTimer: number = -1;
  private probe: (() => boolean) | undefined = undefined;

  /** 由数据层注册：一次“探活”是否能连通（Mock 下等价于故障开关已清除）。 */
  setProbe(probe: () => boolean): void {
    this.probe = probe;
  }

  onHeartbeatOk(): void {
    this.miss = 0;
    this.retryIndex = 0;
    this.retryCount = 0;
    this.stopRetry();
    this.move('online');
  }

  onHeartbeatTimeout(): void {
    this.miss++;
    if (this.miss >= 3) {
      this.move('offline');
      this.scheduleRetry();
      return;
    }
    if (this.miss >= 2) {
      this.move('weak');
    }
  }

  onDelayed(): void {
    if (this.state === 'offline') {
      return;
    }
    this.move('delayed');
  }

  /** 调试注入：直接落到目标状态（仍受退避重连影响，故障清除后自动回 online）。 */
  force(state: NetState): void {
    if (state === 'offline') {
      this.move('offline');
      this.scheduleRetry();
      return;
    }
    this.miss = 0;
    this.stopRetry();
    this.move(state);
  }

  isOffline(): boolean {
    return this.state === 'offline';
  }

  /** banner 只对 weak / offline 展示；delayed 用角标（CC-7.4）。 */
  bannerVisible(): boolean {
    return this.state === 'weak' || this.state === 'offline';
  }

  /** 断线时数据冻结（列表/详情/多窗统一）：55% 置灰由此驱动。 */
  greyed(): boolean {
    return this.state === 'offline';
  }

  private move(next: NetState): void {
    if (this.state === next) {
      return;
    }
    this.state = next;
    this.changedAt = Date.now();
    this.changeSeq++;
    hilog.info(DOMAIN, TAG, 'net_state=%{public}s retry=%{public}d',
      next, this.retryCount);
  }

  private scheduleRetry(): void {
    if (this.retryTimer !== -1) {
      return;
    }
    const index: number = Math.min(this.retryIndex, BACKOFF_MS.length - 1);
    const delay: number = BACKOFF_MS[index];
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      this.retryIndex++;
      this.retryCount++;
      const ok: boolean = this.probe !== undefined ? this.probe() : false;
      hilog.info(DOMAIN, TAG, 'net_retry attempt=%{public}d delay=%{public}d ok=%{public}s',
        this.retryIndex, delay, ok ? 'true' : 'false');
      if (ok) {
        this.onHeartbeatOk();
        return;
      }
      this.scheduleRetry();
    }, delay);
  }

  private stopRetry(): void {
    if (this.retryTimer !== -1) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
  }

  /** 调试复位：清计时器、回 online（不写日志噪声）。 */
  reset(): void {
    this.stopRetry();
    this.miss = 0;
    this.retryIndex = 0;
    this.retryCount = 0;
    this.state = 'online';
    this.changeSeq++;
    this.changedAt = Date.now();
  }
}

/** 全局唯一实例（AppStorageV2，与断点/安全区同构）。 */
export class ConnectionHost {
  private static service: ConnectionHub | undefined = undefined;

  static getService(): ConnectionHub {
    if (ConnectionHost.service === undefined) {
      const connected: ConnectionHub | undefined = AppStorageV2.connect(
        ConnectionHub,
        'connection_hub_v1',
        () => new ConnectionHub()
      );
      ConnectionHost.service = connected !== undefined ? connected : new ConnectionHub();
    }
    return ConnectionHost.service;
  }
}
