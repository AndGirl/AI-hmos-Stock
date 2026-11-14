import { hilog } from '@kit.PerformanceAnalysisKit';
import { StorageAdapter } from './StorageAdapter';

const DOMAIN: number = 0x0001;
const TAG: string = 'Stability';
const KEY: string = 'stability_v1';

/** 稳定性计数快照（全部为本机计数，不上报、不含任何个人信息）。 */
export class StabilitySnapshot {
  /** 启动会话数（每次冷启动 +1）。 */
  sessions: number = 0;
  /** 系统上报的崩溃次数（HiAppEvent `APP_CRASH`）。 */
  crashes: number = 0;
  /** 系统上报的冻屏/ANR 次数（HiAppEvent `APP_FREEZE`）。 */
  freezes: number = 0;
  /** 被兜底捕获的 JS 未捕获异常次数（`errorManager.on('error')`）。 */
  jsErrors: number = 0;
  /** 未处理的 Promise 拒绝次数（`errorManager.on('unhandledRejection')`）。 */
  rejections: number = 0;
  /** 最近一次事件的枚举串（如 `APP_CRASH` / `js_error`）。 */
  lastEvent: string = '';
  /** 最近一次事件时间（ms）。 */
  lastEventAt: number = 0;
}

/**
 * 稳定性计数（M13-3，`stability_v1`）：只存计数与枚举，不存堆栈/账号/持仓。
 * 写盘失败静默（不影响主流程），读取失败回零。
 */
export class StabilityStore {
  private loading: Promise<void> | undefined = undefined;
  private loaded: boolean = false;
  private data: StabilitySnapshot = new StabilitySnapshot();

  load(): Promise<void> {
    if (this.loaded) {
      return Promise.resolve();
    }
    if (this.loading !== undefined) {
      return this.loading;
    }
    this.loading = this.doLoad();
    return this.loading;
  }

  /** 快照（调用方先 await load()）。 */
  snapshot(): StabilitySnapshot {
    return this.data;
  }

  /** 一次启动：会话数 +1 并落盘。 */
  countSession(): void {
    this.data.sessions++;
    this.persist();
  }

  /** 记录一次事件并落盘（`crashes`/`freezes`/`jsErrors`/`rejections`）。 */
  mark(event: 'APP_CRASH' | 'APP_FREEZE' | 'js_error' | 'unhandled_rejection'): void {
    if (event === 'APP_CRASH') {
      this.data.crashes++;
    } else if (event === 'APP_FREEZE') {
      this.data.freezes++;
    } else if (event === 'js_error') {
      this.data.jsErrors++;
    } else {
      this.data.rejections++;
    }
    this.data.lastEvent = event;
    this.data.lastEventAt = Date.now();
    this.persist();
    hilog.info(DOMAIN, TAG, 'stability_event event=%{public}s', event);
  }

  clear(): void {
    const sessions: number = this.data.sessions;
    this.data = new StabilitySnapshot();
    this.data.sessions = sessions;
    this.persist();
    hilog.info(DOMAIN, TAG, 'stability_clear');
  }

  /** 单行摘要：视图/日志直接用（不含中文，避免与资源门禁冲突）。 */
  describe(): string {
    const d: StabilitySnapshot = this.data;
    return `session=${d.sessions} crash=${d.crashes} freeze=${d.freezes} jserr=${d.jsErrors} ` +
      `rej=${d.rejections} last=${d.lastEvent.length > 0 ? d.lastEvent : 'none'}`;
  }

  private persist(): void {
    StorageAdapter.putString(KEY, JSON.stringify(this.data)).catch((): void => {
    });
  }

  private async doLoad(): Promise<void> {
    try {
      const raw: string = await StorageAdapter.getString(KEY, '');
      this.data = StabilityStore.parse(raw);
    } catch (err) {
      this.data = new StabilitySnapshot();
    }
    this.loaded = true;
    this.loading = undefined;
  }

  /** 容错解析：坏 JSON/旧格式一律回零，不丢会话累加能力。 */
  static parse(raw: string): StabilitySnapshot {
    const out: StabilitySnapshot = new StabilitySnapshot();
    if (raw.length === 0) {
      return out;
    }
    try {
      const obj: StabilitySnapshot = JSON.parse(raw) as StabilitySnapshot;
      out.sessions = typeof obj.sessions === 'number' && obj.sessions >= 0 ? obj.sessions : 0;
      out.crashes = typeof obj.crashes === 'number' && obj.crashes >= 0 ? obj.crashes : 0;
      out.freezes = typeof obj.freezes === 'number' && obj.freezes >= 0 ? obj.freezes : 0;
      out.jsErrors = typeof obj.jsErrors === 'number' && obj.jsErrors >= 0 ? obj.jsErrors : 0;
      out.rejections = typeof obj.rejections === 'number' && obj.rejections >= 0 ? obj.rejections : 0;
      out.lastEvent = typeof obj.lastEvent === 'string' ? obj.lastEvent : '';
      out.lastEventAt = typeof obj.lastEventAt === 'number' ? obj.lastEventAt : 0;
    } catch (err) {
      return new StabilitySnapshot();
    }
    return out;
  }
}
