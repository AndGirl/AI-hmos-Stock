import { errorManager } from '@kit.AbilityKit';
import { hiAppEvent } from '@kit.PerformanceAnalysisKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { StabilitySnapshot, StabilityStore } from '../store/StabilityStore';

const DOMAIN: number = 0x0001;
const TAG: string = 'Stability';
const WATCHER: string = 'stability_watcher';

/**
 * 稳定性采集（M13-3 / AC-127）。
 *
 * 口径（本轮确认）：**只在本机采集，不上报、不接三方 SDK**——
 *   - 崩溃/冻屏：`hiAppEvent` 监听系统事件（`APP_CRASH` / `APP_FREEZE`），下一次启动时落盘；
 *   - JS 未捕获异常：`errorManager.on('error')` 兜底，避免「崩了但没记录」；
 *   - 未处理 Promise 拒绝：`errorManager.on('unhandledRejection')`（API 12+，不支持时静默跳过）；
 *   - 会话数：每次冷启动 +1，用「崩溃 / 会话」即得崩溃率。
 *
 * 不采集任何个人信息：只记次数、事件枚举与时间戳（见 `StabilityStore`）。
 * 崩溃率/ANR 率的分母是本机会话数；线上口径需 AGC（本轮外部待办）。
 */
export class StabilityMonitor {
  private store: StabilityStore = new StabilityStore();
  private started: boolean = false;
  private watcherAdded: boolean = false;

  /** 幂等启动：`EntryAbility.onCreate` 调用一次。 */
  start(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    this.store.load().then((): void => {
      this.store.countSession();
      this.registerSystemWatcher();
      this.registerJsObservers();
      hilog.info(DOMAIN, TAG, 'stability_ready %{public}s', this.describe());
    }).catch((): void => {
      hilog.warn(DOMAIN, TAG, 'stability_start_fail');
    });
  }

  /** 当前计数快照（UI/调试面板用）。 */
  snapshot(): StabilitySnapshot {
    return this.store.snapshot();
  }

  describe(): string {
    return this.store.describe();
  }

  /** 清空计数（保留会话数；调试面板用）。 */
  clear(): void {
    this.store.clear();
  }

  /** 演示用：主动抛一个未捕获异常，验证「兜底 + 下次启动采集」链路（仅 debug 面板可达）。 */
  raiseForTest(): void {
    hilog.info(DOMAIN, TAG, 'stability_raise_for_test');
    setTimeout((): void => {
      throw new Error('stability probe');
    }, 50);
  }

  private registerSystemWatcher(): void {
    if (this.watcherAdded) {
      return;
    }
    try {
      hiAppEvent.addWatcher({
        name: WATCHER,
        appEventFilters: [{
          // 按事件名过滤（`names` 收字符串；`eventTypes` 是 EventType 枚举，不能传事件名）。
          domain: hiAppEvent.domain.OS,
          names: [hiAppEvent.event.APP_CRASH, hiAppEvent.event.APP_FREEZE]
        }],
        onReceive: (domain: string, groups: hiAppEvent.AppEventGroup[]): void => {
          for (let i = 0; i < groups.length; i++) {
            const name: string = groups[i].name;
            if (name === hiAppEvent.event.APP_CRASH) {
              this.store.mark('APP_CRASH');
            } else if (name === hiAppEvent.event.APP_FREEZE) {
              this.store.mark('APP_FREEZE');
            }
          }
        }
      });
      this.watcherAdded = true;
      hilog.info(DOMAIN, TAG, 'stability_watcher_on events=APP_CRASH,APP_FREEZE');
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'stability_watcher_fail');
    }
  }

  private registerJsObservers(): void {
    try {
      errorManager.on('error', {
        onUnhandledException: (errMsg: string): void => {
          // 只记次数与长度，不落堆栈（堆栈可能含输入内容）。
          hilog.error(DOMAIN, TAG, 'js_error len=%{public}d', errMsg.length);
          this.store.mark('js_error');
        }
      });
      hilog.info(DOMAIN, TAG, 'stability_error_observer_on');
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'stability_error_observer_fail');
    }
    try {
      // API 12+：未处理的 Promise 拒绝（低版本无该重载时装不上就跳过）。
      errorManager.on('unhandledRejection', (reason: Error | Object, promise: Promise<Object>): void => {
        hilog.error(DOMAIN, TAG, 'unhandled_rejection');
        this.store.mark('unhandled_rejection');
      });
      hilog.info(DOMAIN, TAG, 'stability_rejection_observer_on');
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'stability_rejection_observer_skip');
    }
  }
}
