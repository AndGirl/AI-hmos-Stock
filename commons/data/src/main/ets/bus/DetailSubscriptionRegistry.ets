import { ConnectionHost } from 'commons_basic';
import { DetailListener, DetailPatch, DetailProvider, DetailSubscription } from '../model/DetailModels';

/**
 * 详情推送订阅档位（设计 §5.5.4）：
 * - focus      焦点窗：1s（与 provider 推送同频）
 * - normal     普通：1s
 * - background 非焦点窗：5s（同一路订阅降频投递，不额外起定时器）
 */
export type SinkTier = 'focus' | 'normal' | 'background';

/** 非焦点窗投递间隔（FR-08.7：1s → 5s）。 */
export const BACKGROUND_INTERVAL_MS: number = 5000;

/** 订阅句柄：释放即退订；未释放前可改档位、可要求立即补一帧。 */
export interface SubscriptionHandle {
  release(): void;
}

class SinkEntry {
  listener: DetailListener;
  tier: SinkTier;
  lastDeliveredAt: number = 0;

  constructor(listener: DetailListener, tier: SinkTier) {
    this.listener = listener;
    this.tier = tier;
  }
}

/** 一个 code 一路逻辑订阅：provider 只订一次，多 sink 多播（AC-83）。 */
class CodeEntry {
  code: string;
  providerSub: DetailSubscription | null = null;
  sinks: SinkEntry[] = [];
  /** 最近一次推送：焦点提升时立即补投一帧，避免切窗等一个周期（首帧 ≤300ms）。 */
  lastPatch: DetailPatch | null = null;

  constructor(code: string) {
    this.code = code;
  }

  dispatch(patch: DetailPatch): void {
    // CC-7.6：断线冻结——保留最后一帧，不投递新数据也不清空。
    if (ConnectionHost.getService().isOffline()) {
      return;
    }
    this.lastPatch = patch;
    const now: number = Date.now();
    for (let i = 0; i < this.sinks.length; i++) {
      const sink: SinkEntry = this.sinks[i];
      if (sink.tier === 'background' && now - sink.lastDeliveredAt < BACKGROUND_INTERVAL_MS) {
        continue;
      }
      sink.lastDeliveredAt = now;
      sink.listener.onPatch(patch);
    }
  }

  flushTo(sink: SinkEntry): void {
    if (this.lastPatch === null) {
      return;
    }
    sink.lastDeliveredAt = Date.now();
    sink.listener.onPatch(this.lastPatch);
  }
}

class SubscriptionHandleImpl implements SubscriptionHandle {
  private registry: DetailSubscriptionRegistry;
  private entry: CodeEntry;
  private sink: SinkEntry;
  private active: boolean = true;

  constructor(registry: DetailSubscriptionRegistry, entry: CodeEntry, sink: SinkEntry) {
    this.registry = registry;
    this.entry = entry;
    this.sink = sink;
  }

  release(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.registry.releaseSink(this.entry, this.sink);
  }

  isActive(): boolean {
    return this.active;
  }

  sinkTier(): SinkTier {
    return this.sink.tier;
  }

  promote(tier: SinkTier): void {
    if (!this.active) {
      return;
    }
    this.sink.tier = tier;
    if (tier !== 'background') {
      // 恢复焦点/普通档：立即补一次最新一帧（不必等下一个 1s 周期）。
      this.entry.flushTo(this.sink);
    }
  }
}

class FanoutSink implements DetailListener {
  private entry: CodeEntry;

  constructor(entry: CodeEntry) {
    this.entry = entry;
  }

  onPatch(patch: DetailPatch): void {
    this.entry.dispatch(patch);
  }
}

/**
 * 详情订阅登记表（L1，唯一入口：DataServices.detailSubs()）。
 * 规则（设计 §5.5.4 / INV-W3）：
 * - 同 code 多窗合并为一路，按 sink 多播；`activeCount()` 即逻辑订阅数（3 窗 ≤3 路）。
 * - 非焦点窗 5s 投递；释放最后一个 sink 时整路退订（`activeCount()` 归零）。
 * - 只做投递调度，不持有 VM/视图引用；无可变业务状态。
 */
export class DetailSubscriptionRegistry {
  private provider: DetailProvider;
  private entries: Map<string, CodeEntry> = new Map<string, CodeEntry>();

  constructor(provider: DetailProvider) {
    this.provider = provider;
  }

  acquire(code: string, listener: DetailListener, tier: SinkTier): SubscriptionHandle {
    let entry: CodeEntry | undefined = this.entries.get(code);
    if (entry === undefined) {
      entry = new CodeEntry(code);
      entry.providerSub = this.provider.subscribe(code, new FanoutSink(entry));
      this.entries.set(code, entry);
    }
    const sink: SinkEntry = new SinkEntry(listener, tier);
    // 新 sink 立即可用：把最近一帧补给它（同 code 多窗不重复等首帧）。
    if (entry.lastPatch !== null) {
      sink.lastDeliveredAt = Date.now();
      sink.listener.onPatch(entry.lastPatch);
    }
    entry.sinks.push(sink);
    return new SubscriptionHandleImpl(this, entry, sink);
  }

  setTier(handle: SubscriptionHandle, tier: SinkTier): void {
    if (handle instanceof SubscriptionHandleImpl) {
      handle.promote(tier);
    }
  }

  releaseSink(entry: CodeEntry, sink: SinkEntry): void {
    const index: number = entry.sinks.indexOf(sink);
    if (index >= 0) {
      entry.sinks.splice(index, 1);
    }
    if (entry.sinks.length > 0) {
      return;
    }
    const sub: DetailSubscription | null = entry.providerSub;
    entry.providerSub = null;
    entry.lastPatch = null;
    this.entries.delete(entry.code);
    if (sub !== null) {
      sub.unsubscribe();
    }
  }

  /** 逻辑订阅数（同 code 合并后）：AC-83 断言「3 窗 ≤3 路」「全部关闭后归零」。 */
  activeCount(): number {
    return this.entries.size;
  }

  /** sink 总数（窗实例数，含同 code 多播）。 */
  sinkCount(): number {
    let total: number = 0;
    this.entries.forEach((entry: CodeEntry): void => {
      total += entry.sinks.length;
    });
    return total;
  }

  /** 调试日志串：`subs=2 sinks=3 codes=600519,000001`。 */
  stats(): string {
    const codes: string[] = [];
    this.entries.forEach((entry: CodeEntry): void => {
      codes.push(entry.code);
    });
    return `subs=${this.activeCount()} sinks=${this.sinkCount()} codes=${codes.join(',')}`;
  }
}
