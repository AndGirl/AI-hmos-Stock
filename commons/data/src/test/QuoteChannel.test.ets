import { describe, expect, it } from '@ohos/hypium';
import {
  ConnectionState,
  QuoteCapabilities,
  QuoteError,
  QuoteListener,
  QuotePatch,
  QuoteProvider,
  QuoteSnapshot,
  QuoteSubscription
} from '../main/ets/model/QuoteModels';
import { QuoteChannel } from '../main/ets/real/QuoteChannel';
import { MockFaults } from '../main/ets/mock/MockFaults';
import { QuoteHealth, QuoteHealthHost } from 'commons_basic';

class NoopSub implements QuoteSubscription {
  unsubscribe(): void {
  }
}

/** 测试桩：不直接 new Provider 实现（R-05），只做「发帧」的最小通道。 */
class StubQuoteProvider implements QuoteProvider {
  private listener: QuoteListener | undefined = undefined;
  private snapshots: QuoteSnapshot[] = [];

  seed(snapshot: QuoteSnapshot): void {
    this.snapshots.push(snapshot);
  }

  getSnapshots(codes: string[]): Promise<QuoteSnapshot[]> {
    const result: QuoteSnapshot[] = [];
    for (let i = 0; i < codes.length; i++) {
      for (let j = 0; j < this.snapshots.length; j++) {
        if (this.snapshots[j].code === codes[i]) {
          result.push(this.snapshots[j]);
        }
      }
    }
    return Promise.resolve(result);
  }

  subscribe(codes: string[], listener: QuoteListener): QuoteSubscription {
    this.listener = listener;
    listener.onStatus('online');
    return new NoopSub();
  }

  emit(patch: QuotePatch): void {
    const listener: QuoteListener | undefined = this.listener;
    if (listener !== undefined) {
      listener.onPatch(patch);
    }
  }
}

class Collector implements QuoteListener {
  patches: QuotePatch[] = [];
  errors: QuoteError[] = [];
  states: ConnectionState[] = [];

  onPatch(patch: QuotePatch): void {
    this.patches.push(patch);
  }

  onStatus(state: ConnectionState): void {
    this.states.push(state);
  }

  onError(error: QuoteError): void {
    this.errors.push(error);
  }
}

function snapshotOf(code: string, last: number, limitUp: number, limitDown: number): QuoteSnapshot {
  const item: QuoteSnapshot = {
    code: code,
    market: 'SH',
    name: '示范',
    status: 'open',
    snapshotTime: 1000,
    isNew: false,
    last: last,
    prevClose: 10,
    chg: 0,
    pct: 0,
    volume: 100,
    lastVolume: 10,
    amount: 1000,
    amplitude: 1,
    turnover: 1,
    pe: 10,
    pb: 1,
    limitUp: limitUp,
    limitDown: limitDown
  };
  return item;
}

function patchOf(code: string, time: number, last: number, seq: number): QuotePatch {
  return { code: code, snapshotTime: time, last: last, seq: seq };
}

/**
 * M9-4 / M9-5 通道单测：帧校验拦截、降频/轮询、鉴权失败与恢复。
 * 用测试桩代替数据源，验证的是通道自身的判定逻辑（不依赖真网络）。
 */
export default function quoteChannelTest(): void {
  describe('QuoteChannel', () => {
    it('valid_frame_forwarded', 0, async () => {
      MockFaults.reset();
      const stub: StubQuoteProvider = new StubQuoteProvider();
      stub.seed(snapshotOf('600519', 10, 11, 9));
      const channel: QuoteChannel = new QuoteChannel(stub);
      const collector: Collector = new Collector();
      const sub: QuoteSubscription = channel.subscribe(['600519'], collector);
      await channel.getSnapshots(['600519']);
      stub.emit(patchOf('600519', 2000, 10.2, 1));
      expect(collector.patches.length).assertEqual(1);
      expect(collector.patches[0].last).assertEqual(10.2);
      sub.unsubscribe();
      channel.recover(3000);
      MockFaults.reset();
    });

    it('stale_time_dropped', 0, async () => {
      MockFaults.reset();
      const stub: StubQuoteProvider = new StubQuoteProvider();
      stub.seed(snapshotOf('600519', 10, 11, 9));
      const channel: QuoteChannel = new QuoteChannel(stub);
      const collector: Collector = new Collector();
      const sub: QuoteSubscription = channel.subscribe(['600519'], collector);
      await channel.getSnapshots(['600519']);
      const health: QuoteHealth = QuoteHealthHost.getService();
      const before: number = health.dropped;
      stub.emit(patchOf('600519', 2000, 10.2, 1));
      // 时间回退帧：丢弃且不进 UI
      stub.emit(patchOf('600519', 1500, 10.3, 2));
      expect(collector.patches.length).assertEqual(1);
      expect(health.dropped - before).assertEqual(1);
      sub.unsubscribe();
      MockFaults.reset();
    });

    it('price_out_of_range_dropped', 0, async () => {
      MockFaults.reset();
      const stub: StubQuoteProvider = new StubQuoteProvider();
      stub.seed(snapshotOf('600519', 10, 11, 9));
      const channel: QuoteChannel = new QuoteChannel(stub);
      const collector: Collector = new Collector();
      const sub: QuoteSubscription = channel.subscribe(['600519'], collector);
      await channel.getSnapshots(['600519']);
      stub.emit(patchOf('600519', 2000, 0.001, 1));
      expect(collector.patches.length).assertEqual(0);
      sub.unsubscribe();
      MockFaults.reset();
    });

    it('price_beyond_limit_dropped', 0, async () => {
      MockFaults.reset();
      const stub: StubQuoteProvider = new StubQuoteProvider();
      stub.seed(snapshotOf('600519', 10, 11, 9));
      const channel: QuoteChannel = new QuoteChannel(stub);
      const collector: Collector = new Collector();
      const sub: QuoteSubscription = channel.subscribe(['600519'], collector);
      await channel.getSnapshots(['600519']);
      // 涨停 11，20 远超 2% 容差
      stub.emit(patchOf('600519', 2000, 20, 1));
      expect(collector.patches.length).assertEqual(0);
      sub.unsubscribe();
      MockFaults.reset();
    });

    it('rate_limit_degrades_to_polling_and_recovers', 0, () => {
      MockFaults.reset();
      const stub: StubQuoteProvider = new StubQuoteProvider();
      const channel: QuoteChannel = new QuoteChannel(stub);
      const collector: Collector = new Collector();
      const sub: QuoteSubscription = channel.subscribe(['600519'], collector);
      expect(channel.mode()).assertEqual('push');

      MockFaults.quoteRateLimited = true;
      MockFaults.quoteRetryAfterMs = 8000;
      channel.tick(10000);
      expect(channel.mode()).assertEqual('throttled');
      expect(collector.errors.length).assertEqual(1);
      expect(collector.errors[0].reason).assertEqual('rate_limited');
      expect(collector.errors[0].retryAfterMs).assertEqual(8000);

      // 连续 3 次 429 → 轮询
      channel.tick(16000);
      channel.tick(22000);
      expect(channel.mode()).assertEqual('polling');

      // 故障清除后 60s 无 429 → 恢复 push
      MockFaults.quoteRateLimited = false;
      MockFaults.quoteRetryAfterMs = 0;
      channel.tick(22000 + 60001);
      expect(channel.mode()).assertEqual('push');
      sub.unsubscribe();
      MockFaults.reset();
    });

    it('unauthorized_stops_and_emits_error', 0, () => {
      MockFaults.reset();
      const stub: StubQuoteProvider = new StubQuoteProvider();
      const channel: QuoteChannel = new QuoteChannel(stub);
      const collector: Collector = new Collector();
      const sub: QuoteSubscription = channel.subscribe(['600519'], collector);
      MockFaults.quoteUnauthorized = true;
      channel.tick(5000);
      expect(channel.tokenState()).assertEqual('unauthorized');
      expect(collector.errors.length >= 1).assertTrue();
      expect(collector.errors[0].reason).assertEqual('unauthorized');
      // 已锁定：再次 tick 不重复刷错误（防死循环）
      channel.tick(6000);
      expect(collector.errors.length).assertEqual(1);
      sub.unsubscribe();
      MockFaults.reset();
    });

    it('recover_clears_unauthorized', 0, () => {
      MockFaults.reset();
      const stub: StubQuoteProvider = new StubQuoteProvider();
      const channel: QuoteChannel = new QuoteChannel(stub);
      const collector: Collector = new Collector();
      const sub: QuoteSubscription = channel.subscribe(['600519'], collector);
      MockFaults.quoteUnauthorized = true;
      channel.tick(5000);
      expect(channel.tokenState()).assertEqual('unauthorized');
      MockFaults.quoteUnauthorized = false;
      channel.recover(9000);
      expect(channel.tokenState()).assertEqual('valid');
      expect(channel.mode()).assertEqual('push');
      sub.unsubscribe();
      MockFaults.reset();
    });

    it('capabilities_declared', 0, () => {
      MockFaults.reset();
      const stub: StubQuoteProvider = new StubQuoteProvider();
      const channel: QuoteChannel = new QuoteChannel(stub);
      const caps: QuoteCapabilities = channel.capabilities();
      expect(caps.push).assertTrue();
      expect(caps.rateLimit).assertTrue();
      MockFaults.reset();
    });

    it('unsubscribe_releases_inner', 0, () => {
      MockFaults.reset();
      const stub: StubQuoteProvider = new StubQuoteProvider();
      const channel: QuoteChannel = new QuoteChannel(stub);
      const collector: Collector = new Collector();
      const sub: QuoteSubscription = channel.subscribe(['600519'], collector);
      expect(channel.stats().indexOf('subs=1') >= 0).assertTrue();
      sub.unsubscribe();
      expect(channel.stats().indexOf('subs=0') >= 0).assertTrue();
      MockFaults.reset();
    });
  });
}
