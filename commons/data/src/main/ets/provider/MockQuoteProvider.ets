import {
  Market,
  QuoteListener,
  QuotePatch,
  QuoteProvider,
  QuoteSnapshot,
  QuoteSubscription,
  TradeStatus
} from '../model/QuoteModels';
import { buildIndexSeeds, buildStockSeeds, IndexSeed, StockSeed } from '../mock/MarketSeeds';

const PUSH_INTERVAL_MS: number = 1000;
const LIMIT_RATIO: number = 0.10;

/** 可变行情状态：只有 Mock 内部使用，对外只产出快照/patch。 */
class QuoteState {
  code: string = '';
  name: string = '';
  market: Market = 'SH';
  status: TradeStatus = 'open';
  isNew: boolean = false;
  volatility: number = 1;
  floatShares: number = 2000000000;
  last: number = 0;
  prevClose: number = 0;
  high: number = 0;
  low: number = 0;
  volume: number = 0;
  lastVolume: number = 0;
  amount: number = 0;
  pe: number = 0;
  pb: number = 0;
  snapshotTime: number = 0;

  buildSnapshot(): QuoteSnapshot {
    const suspended: boolean = this.status === 'suspended' || this.status === 'delisted';
    const noChange: boolean = suspended || this.isNew;
    const chgValue: number | null = noChange ? null : this.last - this.prevClose;
    let pctValue: number | null = null;
    if (!noChange && this.prevClose !== 0 && chgValue !== null) {
      pctValue = chgValue / this.prevClose * 100;
    }
    const amplitude: number | null = suspended || this.prevClose === 0 ?
      null : (this.high - this.low) / this.prevClose * 100;
    const turnover: number | null = suspended ? null : this.volume / this.floatShares * 100;
    return {
      code: this.code,
      market: this.market,
      name: this.name,
      status: this.status,
      snapshotTime: this.snapshotTime,
      isNew: this.isNew,
      last: suspended ? null : this.last,
      prevClose: suspended ? null : this.prevClose,
      chg: chgValue,
      pct: pctValue,
      volume: suspended ? null : this.volume,
      lastVolume: suspended ? null : this.lastVolume,
      amount: suspended ? null : this.amount,
      amplitude: amplitude,
      turnover: turnover,
      pe: suspended || this.pe === 0 ? null : this.pe,
      pb: suspended || this.pb === 0 ? null : this.pb
    };
  }

  buildPatch(): QuotePatch {
    const snap: QuoteSnapshot = this.buildSnapshot();
    const patch: QuotePatch = {
      code: this.code,
      snapshotTime: this.snapshotTime
    };
    if (snap.last !== null) {
      patch.last = snap.last;
    }
    if (snap.chg !== null) {
      patch.chg = snap.chg;
    }
    if (snap.pct !== null) {
      patch.pct = snap.pct;
    }
    if (snap.volume !== null) {
      patch.volume = snap.volume;
    }
    if (snap.lastVolume !== null) {
      patch.lastVolume = snap.lastVolume;
    }
    if (snap.amount !== null) {
      patch.amount = snap.amount;
    }
    if (snap.amplitude !== null) {
      patch.amplitude = snap.amplitude;
    }
    if (snap.turnover !== null) {
      patch.turnover = snap.turnover;
    }
    if (snap.status !== undefined) {
      patch.status = snap.status;
    }
    return patch;
  }
}

class Subscriber {
  codes: Set<string>;
  listener: QuoteListener;

  constructor(codes: string[], listener: QuoteListener) {
    this.codes = new Set<string>(codes);
    this.listener = listener;
  }
}

class ProviderSubscription implements QuoteSubscription {
  private provider: MockQuoteProvider;
  private subscriber: Subscriber;
  private active: boolean = true;

  constructor(provider: MockQuoteProvider, subscriber: Subscriber) {
    this.provider = provider;
    this.subscriber = subscriber;
  }

  unsubscribe(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.provider.removeSubscriber(this.subscriber);
  }
}

/**
 * Mock 行情源：1s 心跳，每次只推 1~3 只（保证单行刷新可被观察）；
 * 停牌/新股不推送涨跌；断线/延迟/429 由 M5 的 ConnectionHub 模拟（本期不接）。
 */
export class MockQuoteProvider implements QuoteProvider {
  private states: Map<string, QuoteState> = new Map<string, QuoteState>();
  private subscribers: Subscriber[] = [];
  private timerId: number = -1;

  constructor() {
    const stocks: StockSeed[] = buildStockSeeds();
    for (let i = 0; i < stocks.length; i++) {
      const seed: StockSeed = stocks[i];
      const state: QuoteState = new QuoteState();
      state.code = seed.code;
      state.name = seed.name;
      state.market = seed.market;
      state.status = seed.status;
      state.isNew = seed.isNew;
      state.volatility = seed.volatility;
      state.last = seed.base;
      state.prevClose = seed.base * (1 - (((i % 11) - 5) / 100));
      state.high = Math.max(seed.base, state.prevClose);
      state.low = Math.min(seed.base, state.prevClose);
      state.floatShares = 800000000 + (i % 7) * 400000000;
      state.volume = 1200000 + (i * 37000) % 9000000;
      state.lastVolume = 1000 + (i * 137) % 20000;
      state.amount = state.volume * seed.base;
      state.pe = seed.pe;
      state.pb = seed.pb;
      state.snapshotTime = Date.now();
      this.states.set(seed.code, state);
    }
    const indexes: IndexSeed[] = buildIndexSeeds();
    for (let i = 0; i < indexes.length; i++) {
      const seed: IndexSeed = indexes[i];
      const state: QuoteState = new QuoteState();
      state.code = seed.code;
      state.name = seed.name;
      state.market = 'SH';
      state.status = 'open';
      state.volatility = 0.6;
      state.last = seed.base;
      state.prevClose = seed.base * (1 - 0.004);
      state.high = seed.base * 1.006;
      state.low = seed.base * 0.996;
      state.floatShares = 1000000000000;
      state.volume = 220000000;
      state.amount = state.volume * seed.base;
      state.snapshotTime = Date.now();
      this.states.set(seed.code, state);
    }
  }

  getSnapshots(codes: string[]): Promise<QuoteSnapshot[]> {
    const result: QuoteSnapshot[] = [];
    for (let i = 0; i < codes.length; i++) {
      const state: QuoteState | undefined = this.states.get(codes[i]);
      if (state !== undefined) {
        state.snapshotTime = Date.now();
        result.push(state.buildSnapshot());
      }
    }
    return Promise.resolve(result);
  }

  subscribe(codes: string[], listener: QuoteListener): QuoteSubscription {
    const subscriber: Subscriber = new Subscriber(codes, listener);
    this.subscribers.push(subscriber);
    listener.onStatus('online');
    this.ensureTimer();
    return new ProviderSubscription(this, subscriber);
  }

  removeSubscriber(subscriber: Subscriber): void {
    const index: number = this.subscribers.indexOf(subscriber);
    if (index >= 0) {
      this.subscribers.splice(index, 1);
    }
    if (this.subscribers.length === 0) {
      this.stopTimer();
    }
  }

  private ensureTimer(): void {
    if (this.timerId !== -1) {
      return;
    }
    this.timerId = setInterval((): void => {
      this.tick();
    }, PUSH_INTERVAL_MS);
  }

  private stopTimer(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private tick(): void {
    if (this.subscribers.length === 0) {
      return;
    }
    const codes: Set<string> = new Set<string>();
    for (let i = 0; i < this.subscribers.length; i++) {
      this.subscribers[i].codes.forEach((code: string): void => {
        codes.add(code);
      });
    }
    const all: string[] = Array.from(codes);
    if (all.length === 0) {
      return;
    }
    const count: number = Math.min(all.length, 1 + Math.floor(Math.random() * 3));
    const touched: Set<string> = new Set<string>();
    for (let i = 0; i < count; i++) {
      const code: string = all[Math.floor(Math.random() * all.length)];
      if (touched.has(code)) {
        continue;
      }
      touched.add(code);
      const state: QuoteState | undefined = this.states.get(code);
      if (state === undefined || state.volatility === 0 || state.status !== 'open') {
        continue;
      }
      this.advance(state);
      const patch: QuotePatch = state.buildPatch();
      this.dispatch(patch);
    }
  }

  private advance(state: QuoteState): void {
    const drift: number = (Math.random() * 2 - 1) * 0.008 * state.volatility;
    let next: number = state.last * (1 + drift);
    const upper: number = state.prevClose * (1 + LIMIT_RATIO);
    const lower: number = state.prevClose * (1 - LIMIT_RATIO);
    if (next > upper) {
      next = upper;
    }
    if (next < lower) {
      next = lower;
    }
    state.last = Math.round(next * 100) / 100;
    state.high = Math.max(state.high, state.last);
    state.low = Math.min(state.low, state.last);
    const addedVolume: number = 1000 + Math.floor(Math.random() * 20000);
    state.volume += addedVolume;
    state.lastVolume = addedVolume;
    state.amount += addedVolume * state.last;
    state.snapshotTime = Date.now();
  }

  private dispatch(patch: QuotePatch): void {
    for (let i = 0; i < this.subscribers.length; i++) {
      const subscriber: Subscriber = this.subscribers[i];
      if (subscriber.codes.has(patch.code)) {
        subscriber.listener.onPatch(patch);
      }
    }
  }
}
