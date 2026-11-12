import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'Analytics';

/** 单个埋点参数（只允许字符串，避免把金额/持仓当数值上报）。 */
export class AnalyticsParam {
  key: string;
  value: string;

  constructor(key: string, value: string) {
    this.key = key;
    this.value = value;
  }
}

/** 事件载体（队列元素）。 */
export class AnalyticsEvent {
  event: string;
  params: AnalyticsParam[];
  at: number;

  constructor(event: string, params: AnalyticsParam[], at: number) {
    this.event = event;
    this.params = params;
    this.at = at;
  }
}

/** 上报出口：接三方 SDK 时只替换 sink，调用点不动。 */
export interface AnalyticsSink {
  track(event: string, params: AnalyticsParam[]): void;
}

/** 本期出口：hilog（debug 可 grep Analytics；release 由构建裁剪 sink）。 */
class LogSink implements AnalyticsSink {
  track(event: string, params: AnalyticsParam[]): void {
    let text: string = '';
    for (let i = 0; i < params.length; i++) {
      text += (i === 0 ? '' : ' ') + params[i].key + '=' + params[i].value;
    }
    hilog.info(DOMAIN, TAG, 'event=%{public}s %{public}s', event, text);
  }
}

/**
 * 埋点中心（设计 §5.6.5 / 附录 B）：
 * - 内存队列 + 批量 flush（页面退出/队列满/显式调用）；
 * - 失败静默，不阻塞交互；合规：调用方只传 code/枚举/序号，账号、持仓、金额一律不进参数。
 */
export class AnalyticsHub {
  /** 队列上限：达到即 flush，避免长会话堆积。 */
  static readonly MAX_QUEUE: number = 20;

  private sink: AnalyticsSink = new LogSink();
  private queue: AnalyticsEvent[] = [];

  track(event: string, params: AnalyticsParam[]): void {
    this.queue.push(new AnalyticsEvent(event, params, Date.now()));
    if (this.queue.length >= AnalyticsHub.MAX_QUEUE) {
      this.flush();
    }
  }

  /** 批量上报并清空队列；sink 抛错只吞掉，不影响主流程。 */
  flush(): void {
    if (this.queue.length === 0) {
      return;
    }
    const batch: AnalyticsEvent[] = this.queue;
    this.queue = [];
    try {
      for (let i = 0; i < batch.length; i++) {
        this.sink.track(batch[i].event, batch[i].params);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'flush_fail size=%{public}d', batch.length);
    }
  }

  setSink(sink: AnalyticsSink): void {
    this.sink = sink;
  }

  pendingCount(): number {
    return this.queue.length;
  }
}

/** 全局唯一实例（无 UI 观察需求，普通单例即可）。 */
export class AnalyticsHost {
  private static hub: AnalyticsHub | undefined = undefined;

  static get(): AnalyticsHub {
    if (AnalyticsHost.hub === undefined) {
      AnalyticsHost.hub = new AnalyticsHub();
    }
    return AnalyticsHost.hub;
  }
}

/** 便捷入口：大多数事件只要 0~2 个参数。 */
export function trackEvent(event: string): void {
  AnalyticsHost.get().track(event, []);
}
