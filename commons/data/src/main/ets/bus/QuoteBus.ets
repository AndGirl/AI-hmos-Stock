import { ConnectionHost } from 'commons_basic';
import { ConnectionState, QuoteListener, QuotePatch, QuoteProvider, QuoteSubscription } from '../model/QuoteModels';

/** 行级消费方：只接收自己订阅代码的 patch（单行刷新，CC-1.2）。 */
export interface QuoteSink {
  onPatch(patch: QuotePatch): void;

  onStatus(state: ConnectionState): void;
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
 */
export class QuoteBus {
  private provider: QuoteProvider;
  private entries: SinkEntry[] = [];
  private providerSub: QuoteSubscription | undefined = undefined;
  private listener: QuoteListener;
  private subscribedKey: string = '';
  private pending: Map<string, QuotePatch> = new Map<string, QuotePatch>();
  private flushTimer: number = -1;

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

  removeEntry(entry: SinkEntry): void {
    const index: number = this.entries.indexOf(entry);
    if (index >= 0) {
      this.entries.splice(index, 1);
    }
    this.resubscribe();
    if (this.entries.length === 0) {
      this.stopFlushTimer();
      this.pending.clear();
    }
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

function mergePatch(base: QuotePatch, next: QuotePatch): QuotePatch {
  const merged: QuotePatch = {
    code: base.code,
    snapshotTime: next.snapshotTime
  };
  merged.last = next.last !== undefined ? next.last : base.last;
  merged.chg = next.chg !== undefined ? next.chg : base.chg;
  merged.pct = next.pct !== undefined ? next.pct : base.pct;
  merged.volume = next.volume !== undefined ? next.volume : base.volume;
  merged.lastVolume = next.lastVolume !== undefined ? next.lastVolume : base.lastVolume;
  merged.amount = next.amount !== undefined ? next.amount : base.amount;
  merged.amplitude = next.amplitude !== undefined ? next.amplitude : base.amplitude;
  merged.turnover = next.turnover !== undefined ? next.turnover : base.turnover;
  merged.pe = next.pe !== undefined ? next.pe : base.pe;
  merged.pb = next.pb !== undefined ? next.pb : base.pb;
  merged.status = next.status !== undefined ? next.status : base.status;
  return merged;
}
