import { QuoteHealth, QuoteHealthHost, QuoteHealthMode, QuoteTokenState } from 'commons_basic';
import {
  ConnectionState,
  QuoteCapabilities,
  QuoteError,
  QuoteListener,
  QuotePatch,
  QuoteProvider,
  QuoteSnapshot,
  QuoteSubscription
} from '../model/QuoteModels';
import { FrameReference, FrameValidator } from '../rules/FrameValidator';
import { QuoteMode, RateLimitPolicy, THROTTLE_INTERVAL_MS } from '../rules/RateLimitRules';
import { AuthClient } from './AuthClient';
import { MockFaults } from '../mock/MockFaults';

/** 健康/降级轮询间隔（与推送同频：1s）。 */
const TICK_MS: number = 1000;
/** 连续异常帧触发重订阅的最小间隔，避免抖动时反复重建通道。 */
const RESUBSCRIBE_MIN_GAP_MS: number = 5000;

/** 一个订阅者的通道状态（导出仅为让 `ingest` / `forwardError` 的签名可见）。 */
export class ChannelEntry {
  codes: Set<string>;
  listener: QuoteListener;
  inner: QuoteSubscription | undefined = undefined;
  lastDelivered: Map<string, number> = new Map<string, number>();
  closed: boolean = false;

  constructor(codes: string[], listener: QuoteListener) {
    this.codes = new Set<string>(codes);
    this.listener = listener;
  }
}

class EntryListener implements QuoteListener {
  private channel: QuoteChannel;
  private entry: ChannelEntry;

  constructor(channel: QuoteChannel, entry: ChannelEntry) {
    this.channel = channel;
    this.entry = entry;
  }

  onPatch(patch: QuotePatch): void {
    this.channel.ingest(this.entry, patch);
  }

  onStatus(state: ConnectionState): void {
    if (!this.entry.closed) {
      this.entry.listener.onStatus(state);
    }
  }

  onError(error: QuoteError): void {
    this.channel.forwardError(this.entry, error);
  }
}

class ChannelSubscription implements QuoteSubscription {
  private channel: QuoteChannel;
  private entry: ChannelEntry;
  private active: boolean = true;

  constructor(channel: QuoteChannel, entry: ChannelEntry) {
    this.channel = channel;
    this.entry = entry;
  }

  unsubscribe(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.channel.removeEntry(this.entry);
  }
}

/**
 * 行情通道（M9-2 / M9-3 / M9-4 / M9-5 的落地层）。
 *
 * 为什么要在 provider 与 bus 之间插一层：
 * - 鉴权（AC-106）：订阅前取 token，401 只刷新一次，失败转未授权；
 * - 订阅合并与退订（AC-107）：由 `QuoteBus` 完成，本层只保证「一路 inner subscription」；
 * - 帧校验（AC-110）：脏帧在这里被丢弃并计数，永远不进 UI；
 * - 限流降级（AC-109）：429 → 5s 降频 → 3 次转轮询 → 60s 恢复；
 * - 可观测：状态写入 `QuoteHealth`，由 `GlobalBanner` 统一展示。
 *
 * 数据源仍是本地 Mock（本项目永不接真实行情）；将来接本地后端时，
 * 把构造入参换成 transport 支持的 provider 即可，上层与 UI 不动。
 */
export class QuoteChannel implements QuoteProvider {
  private inner: QuoteProvider;
  private auth: AuthClient = new AuthClient();
  private policy: RateLimitPolicy = new RateLimitPolicy();
  private validator: FrameValidator = new FrameValidator();
  private references: Map<string, FrameReference> = new Map<string, FrameReference>();
  private entries: ChannelEntry[] = [];
  private health: QuoteHealth = QuoteHealthHost.getService();
  private timer: number = -1;
  private injectCursor: number = 0;
  private lastRateLimitAt: number = 0;
  private lastResubscribeAt: number = 0;

  constructor(inner: QuoteProvider) {
    this.inner = inner;
  }

  capabilities(): QuoteCapabilities {
    return { push: true, orderBook: true, ticks: true, chart: true, rateLimit: true };
  }

  async getSnapshots(codes: string[]): Promise<QuoteSnapshot[]> {
    const now: number = Date.now();
    const state: QuoteTokenState = this.auth.ensureToken(now, MockFaults.quoteUnauthorized);
    this.health.markToken(state);
    if (state === 'unauthorized') {
      this.reportUnauthorized();
      return [];
    }
    const list: QuoteSnapshot[] = await this.inner.getSnapshots(codes);
    for (let i = 0; i < list.length; i++) {
      this.references.set(list[i].code, FrameReference.fromSnapshot(list[i]));
    }
    return list;
  }

  subscribe(codes: string[], listener: QuoteListener): QuoteSubscription {
    const entry: ChannelEntry = new ChannelEntry(codes, listener);
    this.entries.push(entry);
    const now: number = Date.now();
    const state: QuoteTokenState = this.auth.ensureToken(now, MockFaults.quoteUnauthorized);
    this.health.markToken(state);
    if (state === 'unauthorized') {
      this.reportUnauthorized();
    } else {
      this.openInner(entry);
    }
    this.primeReferences(codes);
    this.ensureTimer();
    return new ChannelSubscription(this, entry);
  }

  /** 调试/验收断言用：`subs=2 codes=88 mode=push ...`。 */
  stats(): string {
    const codes: Set<string> = new Set<string>();
    for (let i = 0; i < this.entries.length; i++) {
      this.entries[i].codes.forEach((code: string): void => {
        codes.add(code);
      });
    }
    return `subs=${this.entries.length} codes=${codes.size} mode=${this.policy.mode()} ` +
      `${this.validator.snapshotStats().describe()} ${this.auth.describe()}`;
  }

  /** 当前模式（AC-109 断言）。 */
  mode(): QuoteMode {
    return this.policy.mode();
  }

  /** 当前 token 状态（AC-106 断言）。 */
  tokenState(): QuoteTokenState {
    return this.auth.tokenState();
  }

  // ---------- 以下为内部入口（EntryListener / 测试可见，业务层不要直接调） ----------

  /** 收帧：降频闸门 → 异常注入 → 校验 → 投递。 */
  ingest(entry: ChannelEntry, patch: QuotePatch): void {
    if (entry.closed) {
      return;
    }
    const now: number = Date.now();
    // 1) 降频闸门：降级期间按 5s/轮询间隔投递，其余帧静默丢弃（不算异常帧）。
    if (this.policy.degraded()) {
      const last: number | undefined = entry.lastDelivered.get(patch.code);
      const base: number = last !== undefined ? last : 0;
      if (now - base < this.policy.intervalMs()) {
        return;
      }
    }
    // 2) 验收用异常帧注入（默认关闭）。
    let candidate: QuotePatch = patch;
    if (MockFaults.quoteBadFrames) {
      candidate = this.injectBadFrame(patch);
    }
    // 3) 校验：脏帧丢弃 + 计数；连续 10 帧触发一次重订阅。
    const reference: FrameReference | undefined = this.references.get(candidate.code);
    const verdict: string = this.validator.validate(candidate,
      reference !== undefined ? reference : new FrameReference(null, null));
    if (verdict !== 'ok') {
      this.health.markDropped(1);
      if (this.validator.shouldResubscribe(candidate.code)) {
        this.resubscribe(now);
      }
      return;
    }
    // 4) 投递
    entry.lastDelivered.set(candidate.code, now);
    this.health.markAccepted(1);
    if (this.policy.onServed(now)) {
      this.syncMode();
    }
    entry.listener.onPatch(candidate);
  }

  /** 错误下发：只给实现了 `onError` 的监听者（契约可选成员）。 */
  forwardError(entry: ChannelEntry, error: QuoteError): void {
    if (entry.closed) {
      return;
    }
    const listener: QuoteListener = entry.listener;
    if (listener.onError !== undefined) {
      listener.onError(error);
    }
  }

  removeEntry(entry: ChannelEntry): void {
    entry.closed = true;
    const index: number = this.entries.indexOf(entry);
    if (index >= 0) {
      this.entries.splice(index, 1);
    }
    this.releaseInner(entry);
    if (this.entries.length === 0) {
      this.stopTimer();
      this.policy.reset(Date.now());
      this.syncMode();
    }
  }

  /** 调试「恢复」：清鉴权锁定、清限流、重开通道（AC-106 / AC-109 的可恢复性）。 */
  recover(now: number): void {
    this.auth.reset(now);
    this.health.markToken(this.auth.tokenState());
    this.policy.reset(now);
    this.syncMode();
    this.validator.resetAll();
    for (let i = 0; i < this.entries.length; i++) {
      this.releaseInner(this.entries[i]);
      this.openInner(this.entries[i]);
    }
  }

  /** 每秒一次：鉴权故障轮询 + 限流故障轮询 + 无帧恢复。 */
  tick(now: number): void {
    this.pollAuthFault(now);
    this.pollRateLimit(now);
    if (this.policy.tick(now)) {
      this.syncMode();
    }
  }

  // ---------- 私有 ----------

  private openInner(entry: ChannelEntry): void {
    if (entry.inner !== undefined || entry.closed) {
      return;
    }
    entry.inner = this.inner.subscribe(Array.from(entry.codes), new EntryListener(this, entry));
  }

  private releaseInner(entry: ChannelEntry): void {
    const sub: QuoteSubscription | undefined = entry.inner;
    entry.inner = undefined;
    if (sub !== undefined) {
      sub.unsubscribe();
    }
  }

  private primeReferences(codes: string[]): void {
    this.inner.getSnapshots(codes).then((list: QuoteSnapshot[]): void => {
      for (let i = 0; i < list.length; i++) {
        this.references.set(list[i].code, FrameReference.fromSnapshot(list[i]));
      }
    }).catch((): void => {
    });
  }

  private resubscribe(now: number): void {
    if (now - this.lastResubscribeAt < RESUBSCRIBE_MIN_GAP_MS) {
      return;
    }
    this.lastResubscribeAt = now;
    this.validator.resetAll();
    for (let i = 0; i < this.entries.length; i++) {
      this.releaseInner(this.entries[i]);
      this.openInner(this.entries[i]);
    }
  }

  private pollRateLimit(now: number): void {
    if (!MockFaults.quoteRateLimited) {
      return;
    }
    if (now - this.lastRateLimitAt < THROTTLE_INTERVAL_MS) {
      return;
    }
    this.lastRateLimitAt = now;
    const retryAfter: number | undefined =
      MockFaults.quoteRetryAfterMs > 0 ? MockFaults.quoteRetryAfterMs : undefined;
    const mode: QuoteMode = this.policy.onRateLimited(retryAfter, now);
    this.syncMode();
    this.health.markError('rate_limited');
    this.broadcastError({ code: '', reason: 'rate_limited', retryAfterMs: this.policy.intervalMs() });
  }

  private pollAuthFault(now: number): void {
    if (!MockFaults.quoteUnauthorized) {
      return;
    }
    if (this.auth.tokenState() === 'unauthorized') {
      return;
    }
    // 模拟「401 → 只刷新一次 → 仍失败」
    this.auth.invalidate();
    const state: QuoteTokenState = this.auth.handleUnauthorized(now, true);
    this.health.markToken(state);
    if (state === 'unauthorized') {
      this.reportUnauthorized();
    }
  }

  private reportUnauthorized(): void {
    this.health.markToken('unauthorized');
    this.health.markError('unauthorized');
    for (let i = 0; i < this.entries.length; i++) {
      this.releaseInner(this.entries[i]);
      this.forwardError(this.entries[i], { code: '', reason: 'unauthorized' });
    }
  }

  private broadcastError(error: QuoteError): void {
    for (let i = 0; i < this.entries.length; i++) {
      this.forwardError(this.entries[i], error);
    }
  }

  private syncMode(): void {
    const mode: QuoteHealthMode = this.policy.mode();
    this.health.markMode(mode, this.policy.streak());
  }

  /** 按序注入 4 类脏帧：时间回退 / 价格越界 / 超涨跌停 / 空帧。 */
  private injectBadFrame(patch: QuotePatch): QuotePatch {
    const kind: number = this.injectCursor % 4;
    this.injectCursor++;
    const copy: QuotePatch = {
      code: patch.code,
      snapshotTime: patch.snapshotTime,
      seq: patch.seq,
      last: patch.last,
      chg: patch.chg,
      pct: patch.pct,
      volume: patch.volume,
      lastVolume: patch.lastVolume,
      amount: patch.amount,
      amplitude: patch.amplitude,
      turnover: patch.turnover,
      pe: patch.pe,
      pb: patch.pb,
      status: patch.status
    };
    if (kind === 0) {
      copy.snapshotTime = patch.snapshotTime - 5000;
    } else if (kind === 1) {
      copy.last = 0.001;
    } else if (kind === 2) {
      const reference: FrameReference | undefined = this.references.get(patch.code);
      const up: number | null = reference !== undefined ? reference.limitUp : null;
      copy.last = up !== null && up > 0 ? up * 1.5 : 999999;
    } else {
      copy.last = undefined;
      copy.chg = undefined;
      copy.pct = undefined;
      copy.volume = undefined;
      copy.lastVolume = undefined;
      copy.amount = undefined;
      copy.amplitude = undefined;
      copy.turnover = undefined;
      copy.pe = undefined;
      copy.pb = undefined;
      copy.status = undefined;
    }
    return copy;
  }

  private ensureTimer(): void {
    if (this.timer !== -1) {
      return;
    }
    this.timer = setInterval((): void => {
      this.tick(Date.now());
    }, TICK_MS);
  }

  private stopTimer(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }
}
