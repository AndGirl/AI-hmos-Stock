import { ConnectionHost } from 'commons_basic';
import {
  ConnectionState,
  QuoteError,
  QuoteListener,
  QuotePatch,
  QuoteProvider,
  QuoteSubscription
} from '../model/QuoteModels';
import { decideSeq, mergePatch, SeqDecision } from '../rules/QuoteMergeRules';

/** 行级消费方：只接收自己订阅代码的 patch（单行刷新，CC-1.2）。 */
export interface QuoteSink {
  onPatch(patch: QuotePatch): void;

  onStatus(state: ConnectionState): void;

  /** M9-4 可选：降频/鉴权失败等下行错误（未实现者不受影响）。 */
  onError?(error: QuoteError): void;
}

export interface SinkSubscription {
  unsubscribe(): void;
}

/** 合并窗口（设计 §4.4：单定时器 1s 合窗）。 */
const MERGE_WINDOW_MS: number = 1000;

class SinkEntry {
  sink: QuoteSink;
  codes: Set<string>;

  constructor(sink: QuoteSink, codes: string[]) {
    this.sink = sink;
    this.codes = new Set<string>(codes);
  }
}

class BusListener implements QuoteListener {
  private bus: QuoteBus;

  constructor(bus: QuoteBus) {
    this.bus = bus;
  }

  onPatch(patch: QuotePatch): void {
    this.bus.handlePatch(patch);
  }

  onStatus(state: ConnectionState): void {
    this.bus.handleStatus(state);
  }

  onError(error: QuoteError): void {
    this.bus.handleError(error);
  }
}

class BusSubscription implements SinkSubscription {
  private bus: QuoteBus;
  private entry: SinkEntry;
  private active: boolean = true;

  constructor(bus: QuoteBus, entry: SinkEntry) {
    this.bus = bus;
    this.entry = entry;
  }

  unsubscribe(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.bus.removeEntry(this.entry);
  }
}

/**
 * 行情总线：唯一 provider 订阅 + 1s 合并窗口 + 按 code 分发到 sink。
 * 定时器只允许出现在 commons/data（附录 C 第 8 条）。
 *
 * M9-3 增强：
 * - 按 code 维护帧序号水位，重复帧/乱序帧直接丢弃且不进 UI（AC-108）；
 * - 同一 code 在 1s 窗口内多帧按字段合并，`seq` 取最大；
 * - 下行错误（429/401）通过 `onError` 多播给实现了该方法的 sink（AC-109）。
 */
export class QuoteBus {
  private provider: QuoteProvider;
  private entries: SinkEntry[] = [];
  private providerSub: QuoteSubscription | undefined = undefined;
  private listener: QuoteListener;
  private subscribedKey: string = '';
  private pending: Map<string, QuotePatch> = new Map<string, QuotePatch>();
  private flushTimer: number = -1;
  /** 各 code 已接受的帧序号水位（重订阅后重置，避免新通道从 1 开始被全丢）。 */
  private lastSeq: Map<string, number> = new Map<string, number>();
  /** 丢弃计数（重复 + 乱序），随埋点上报 `quote_drop`。 */
  private dropped: number = 0;

  constructor(provider: QuoteProvider) {
    this.provider = provider;
    this.listener = new BusListener(this);
  }

  subscribe(codes: string[], sink: QuoteSink): SinkSubscription {
    const entry: SinkEntry = new SinkEntry(sink, codes);
    this.entries.push(entry);
    this.resubscribe();
    return new BusSubscription(this, entry);
  }

  handlePatch(patch: QuotePatch): void {
    // CC-7.6：断线期间冻结在最后一帧，不重置列表、不切骨架。
    if (ConnectionHost.getService().isOffline()) {
      return;
    }
    const current: number = this.lastSeqOf(patch.code);
    const decision: SeqDecision = decideSeq(current, patch.seq);
    if (!decision.accepted()) {
      this.dropped++;
      return;
    }
    this.lastSeq.set(patch.code, decision.nextSeq);
    const existing: QuotePatch | undefined = this.pending.get(patch.code);
    this.pending.set(patch.code, existing === undefined ? patch : mergePatch(existing, patch));
    if (this.flushTimer === -1) {
      this.flushTimer = setInterval((): void => {
        this.flush();
      }, MERGE_WINDOW_MS);
    }
  }

  handleStatus(state: ConnectionState): void {
    for (let i = 0; i < this.entries.length; i++) {
      this.entries[i].sink.onStatus(state);
    }
  }

  /** 下行错误多播（429 / 401）：只在通道层判定，这里只做分发。 */
  handleError(error: QuoteError): void {
    for (let i = 0; i < this.entries.length; i++) {
      const sink: QuoteSink = this.entries[i].sink;
      if (sink.onError !== undefined) {
        sink.onError(error);
      }
    }
  }

  removeEntry(entry: SinkEntry): void {
    const index: number = this.entries.indexOf(entry);
    if (index >= 0) {
      this.entries.splice(index, 1);
    }
    this.resubscribe();
    if (this.entries.length === 0) {
      this.stopFlushTimer();
      this.pending.clear();
      this.lastSeq.clear();
    }
  }

  /** 订阅/退订统计（AC-107：同 code 多窗合并为一路，退订即释放）。 */
  stats(): string {
    const codes: string[] = this.subscribedKey.length === 0 ? [] : this.subscribedKey.split(',');
    return `subs=${this.providerSub !== undefined ? 1 : 0} sinks=${this.entries.length} ` +
      `codes=${codes.length} drop=${this.dropped}`;
  }

  /** 逻辑订阅数（provider 侧永远 ≤1 路）。 */
  activeCount(): number {
    return this.providerSub !== undefined ? 1 : 0;
  }

  /** sink 总数（窗实例数）。 */
  sinkCount(): number {
    return this.entries.length;
  }

  /** 丢弃计数（重复/乱序帧）。 */
  droppedCount(): number {
    return this.dropped;
  }

  private lastSeqOf(code: string): number {
    const current: number | undefined = this.lastSeq.get(code);
    return current !== undefined ? current : 0;
  }

  private resubscribe(): void {
    const codes: Set<string> = new Set<string>();
    for (let i = 0; i < this.entries.length; i++) {
      this.entries[i].codes.forEach((code: string): void => {
        codes.add(code);
      });
    }
    const union: string[] = Array.from(codes).sort();
    const key: string = union.join(',');
    if (key === this.subscribedKey) {
      return;
    }
    this.subscribedKey = key;
    if (this.providerSub !== undefined) {
      this.providerSub.unsubscribe();
      this.providerSub = undefined;
    }
    // 新通道的 seq 从 1 重新计数：清空水位，否则新帧会被整体判为乱序而丢弃。
    this.lastSeq.clear();
    if (union.length === 0) {
      return;
    }
    this.providerSub = this.provider.subscribe(union, this.listener);
  }

  private flush(): void {
    if (this.pending.size === 0) {
      this.stopFlushTimer();
      return;
    }
    const patches: QuotePatch[] = Array.from(this.pending.values());
    this.pending.clear();
    for (let i = 0; i < patches.length; i++) {
      const patch: QuotePatch = patches[i];
      for (let j = 0; j < this.entries.length; j++) {
        const entry: SinkEntry = this.entries[j];
        if (entry.codes.has(patch.code)) {
          entry.sink.onPatch(patch);
        }
      }
    }
  }

  private stopFlushTimer(): void {
    if (this.flushTimer !== -1) {
      clearInterval(this.flushTimer);
      this.flushTimer = -1;
    }
  }
}
