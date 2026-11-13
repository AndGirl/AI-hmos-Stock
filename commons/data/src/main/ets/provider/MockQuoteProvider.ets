import { ConnectionHost, ConnectionHub } from 'commons_basic';
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
import { buildExtraStockSeeds, ExtraStockSeed } from '../mock/SearchSeeds';
import { MockFaults, NetFault } from '../mock/MockFaults';

const PUSH_INTERVAL_MS: number = 1000;
const LIMIT_RATIO: number = 0.10;

/** 价格 / 涨跌停统一两位小数，与交易侧（MockTradeProvider.round2）同口径。 */
function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

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
  open: number = 0;
  high: number = 0;
  low: number = 0;
  volume: number = 0;
  lastVolume: number = 0;
  amount: number = 0;
  pe: number = 0;
  pb: number = 0;
  volumeRatio: number = 1;
  totalShares: number = 2000000000;
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
    // volume 单位为「手」（契约 §4.3）：先折成股再算换手率。
    const turnover: number | null = suspended ? null : this.volume * 100 / this.floatShares * 100;
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
      pb: suspended || this.pb === 0 ? null : this.pb,
      open: suspended ? null : this.open,
      high: suspended ? null : this.high,
      low: suspended ? null : this.low,
      limitUp: suspended ? null : round2(this.prevClose * (1 + LIMIT_RATIO)),
      limitDown: suspended ? null : round2(this.prevClose * (1 - LIMIT_RATIO)),
      volumeRatio: suspended ? null : this.volumeRatio,
      marketCap: suspended ? null : this.last * this.totalShares,
      floatCap: suspended ? null : this.last * this.floatShares
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
 * 停牌/新股不推送涨跌；断线/弱网/延迟由 `MockFaults.netFault` 驱动 ConnectionHub（M5-1）：
 * - online：正常推送；weak：每 2 个心跳推一次；offline：不推送（数据冻结）；delayed：正常推送但状态挂延迟。
 */
export class MockQuoteProvider implements QuoteProvider {
  private states: Map<string, QuoteState> = new Map<string, QuoteState>();
  private subscribers: Subscriber[] = [];
  private timerId: number = -1;
  private tickSeq: number = 0;

  constructor() {
    // 探活：Mock 下等价于「故障开关已清除」，供 ConnectionHub 的退避重连判定。
    ConnectionHost.getService().setProbe((): boolean => MockFaults.netFault === 'none');
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
      state.open = state.prevClose * (1 + (((i % 5) - 2) / 200));
      state.high = Math.max(seed.base, state.prevClose, state.open);
      state.low = Math.min(seed.base, state.prevClose, state.open);
      state.floatShares = 800000000 + (i % 7) * 400000000;
      state.totalShares = state.floatShares * (1.2 + (i % 5) * 0.1);
      // 量以「手」为单位（1 手 = 100 股）：总量 1.2 万~10.2 万手、现量 10~210 手。
      state.volume = 12000 + (i * 370) % 90000;
      state.lastVolume = 10 + (i * 137) % 200;
      state.amount = state.volume * 100 * seed.base;
      state.volumeRatio = 0.6 + (i % 17) / 10;
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
      state.open = seed.base * 0.998;
      state.high = seed.base * 1.006;
      state.low = seed.base * 0.996;
      state.floatShares = 1000000000000;
      state.volume = 2200000;
      state.amount = state.volume * 100 * seed.base;
      state.snapshotTime = Date.now();
      this.states.set(seed.code, state);
    }
    // 搜索主数据里的追加股票（不在自选种子内）：同样进行情状态，保证搜索结果与详情有价格。
    const extra: ExtraStockSeed[] = buildExtraStockSeeds();
    for (let i = 0; i < extra.length; i++) {
      const seed: ExtraStockSeed = extra[i];
      if (this.states.has(seed.code)) {
        continue;
      }
      const state: QuoteState = new QuoteState();
      state.code = seed.code;
      state.name = seed.name;
      state.market = seed.market;
      state.status = seed.status;
      state.isNew = seed.isNew;
      state.volatility = 1;
      const base: number = 8 + ((i * 23) % 380) / 2;
      state.last = base;
      state.prevClose = base * (1 - (((i % 9) - 4) / 100));
      state.open = state.prevClose * (1 + (((i % 5) - 2) / 200));
      state.high = Math.max(state.last, state.prevClose, state.open);
      state.low = Math.min(state.last, state.prevClose, state.open);
      state.floatShares = 800000000 + (i % 6) * 400000000;
      state.totalShares = state.floatShares * 1.2;
      state.volume = 15000 + (i * 431) % 70000;
      state.lastVolume = 20 + (i * 97) % 180;
      state.amount = state.volume * 100 * base;
      state.volumeRatio = 0.7 + (i % 15) / 10;
      state.pe = 8 + (i % 40);
      state.pb = 1 + (i % 20) / 10;
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

  /**
   * 网络门控（CC-7）：把故障开关映射到 ConnectionHub，并决定本次心跳是否推送。
   * 返回 false 表示本 tick 不推送（断线冻结 / 弱网降低频率）。
   */
  private gateNetwork(): boolean {
    const hub: ConnectionHub = ConnectionHost.getService();
    const fault: NetFault = MockFaults.netFault;
    if (fault === 'offline') {
      hub.force('offline');
      return false;
    }
    if (fault === 'weak') {
      hub.force('weak');
      return this.tickSeq % 2 === 0;
    }
    if (fault === 'delayed') {
      hub.force('delayed');
      return true;
    }
    hub.onHeartbeatOk();
    return true;
  }

  private ensureTimer(): void {    if (this.timerId !== -1) {
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
    this.tickSeq++;
    if (!this.gateNetwork()) {
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
    const upper: number = round2(state.prevClose * (1 + LIMIT_RATIO));
    const lower: number = round2(state.prevClose * (1 - LIMIT_RATIO));
    if (next > upper) {
      next = upper;
    }
    if (next < lower) {
      next = lower;
    }
    state.last = Math.round(next * 100) / 100;
    state.high = Math.max(state.high, state.last);
    state.low = Math.min(state.low, state.last);
    const addedVolume: number = 10 + Math.floor(Math.random() * 200);
    state.volume += addedVolume;
    state.lastVolume = addedVolume;
    state.amount += addedVolume * 100 * state.last;
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
