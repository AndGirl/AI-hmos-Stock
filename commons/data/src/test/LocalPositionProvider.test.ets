import { describe, expect, it } from '@ohos/hypium';
import {
  QuoteListener,
  QuoteProvider,
  QuoteSnapshot,
  QuoteSubscription,
  TradeStatus
} from '../main/ets/model/QuoteModels';
import { LocalPositionProvider } from '../main/ets/provider/LocalPositionProvider';
import { HoldRecord, TradeAccountStore } from '../main/ets/store/TradeAccountStore';
import { MockFaults } from '../main/ets/mock/MockFaults';
import { Position, PositionSummary } from '../main/ets/model/PositionModels';

class NoopSubscription implements QuoteSubscription {
  unsubscribe(): void {
  }
}

/** 测试桩行情：按 code 返回可配置的快照（停牌时可置 null）。 */
class StubQuotes implements QuoteProvider {
  last: number | null = 48.9;
  prevClose: number | null = 48;
  status: TradeStatus = 'open';
  name: string = '示范股';

  getSnapshots(codes: string[]): Promise<QuoteSnapshot[]> {
    const out: QuoteSnapshot[] = [];
    for (let i = 0; i < codes.length; i++) {
      out.push(this.snapshotOf(codes[i]));
    }
    return Promise.resolve(out);
  }

  subscribe(codes: string[], listener: QuoteListener): QuoteSubscription {
    listener.onStatus('online');
    return new NoopSubscription();
  }

  private snapshotOf(code: string): QuoteSnapshot {
    const item: QuoteSnapshot = {
      code: code,
      market: 'SH',
      name: this.name,
      status: this.status,
      snapshotTime: Date.now(),
      isNew: false,
      last: this.last,
      prevClose: this.prevClose,
      chg: null,
      pct: null,
      volume: 1000,
      lastVolume: 10,
      amount: 10000,
      amplitude: 1,
      turnover: 1,
      pe: 10,
      pb: 1
    };
    return item;
  }
}

class Rig {
  quotes: StubQuotes = new StubQuotes();
  accounts: TradeAccountStore = new TradeAccountStore();

  async ready(holds: HoldRecord[]): Promise<LocalPositionProvider> {
    await this.accounts.load();
    await this.accounts.resetAll();
    this.accounts.records()[0].holdings = holds;
    MockFaults.reset();
    return new LocalPositionProvider(this.quotes, this.accounts);
  }
}

/**
 * M11-1 本地持仓源单测：主账户口径、行情估值、停牌兜底、lastPrice 记忆、故障注入。
 * 未注入 context 时 StorageAdapter 退化为内存，因此可直接 new。
 */
export default function localPositionProviderTest(): void {
  describe('LocalPositionProvider', () => {
    it('positions_from_holdings_and_quotes', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalPositionProvider = await rig.ready([new HoldRecord('601318', 1000, 45, 45)]);
      const rows: Position[] = await provider.positions();
      expect(rows.length).assertEqual(1);
      expect(rows[0].code).assertEqual('601318');
      expect(rows[0].qty).assertEqual(1000);
      expect(rows[0].last).assertEqual(48.9);
      expect(rows[0].marketValue).assertEqual(48900);
      expect(rows[0].pnl).assertEqual(3900);
      expect(rows[0].dayPnl).assertEqual(900);
      expect(rows[0].weight).assertEqual(100);
    });

    it('only_main_account_is_listed', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalPositionProvider = await rig.ready([new HoldRecord('601318', 1000, 45, 45)]);
      // 第二个账户的种子持仓（600519）不应出现在主账户口径里
      expect(rig.accounts.records()[1].holdings.length > 0).assertTrue();
      const rows: Position[] = await provider.positions();
      expect(rows.length).assertEqual(1);
      expect(rows[0].code).assertEqual('601318');
    });

    it('suspended_falls_back_to_last_price', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalPositionProvider = await rig.ready([new HoldRecord('601318', 1000, 45, 47.5)]);
      rig.quotes.status = 'suspended';
      rig.quotes.last = null;
      rig.quotes.prevClose = null;
      const rows: Position[] = await provider.positions();
      expect(rows[0].last).assertEqual(47.5);
      expect(rows[0].marketValue).assertEqual(47500);
      expect(rows[0].dayPnl).assertEqual(0);
    });

    it('remembers_last_valid_price', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalPositionProvider = await rig.ready([new HoldRecord('601318', 1000, 45, 45)]);
      await provider.positions();
      const hold: HoldRecord | undefined = rig.accounts.holdingOf('50012345', '601318');
      expect(hold !== undefined ? hold.lastPrice : 0).assertEqual(48.9);
    });

    it('position_of_returns_single_and_null', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalPositionProvider = await rig.ready([new HoldRecord('601318', 1000, 45, 45)]);
      const one: Position | null = await provider.positionOf('601318');
      expect(one !== null ? one.qty : 0).assertEqual(1000);
      const none: Position | null = await provider.positionOf('600519');
      expect(none === null).assertTrue();
    });

    it('no_holdings_returns_empty', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalPositionProvider = await rig.ready([]);
      const rows: Position[] = await provider.positions();
      expect(rows.length).assertEqual(0);
      const summary: PositionSummary = await provider.summary();
      expect(summary.count).assertEqual(0);
      expect(summary.marketValue).assertEqual(0);
    });

    it('summary_matches_positions', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalPositionProvider = await rig.ready([
        new HoldRecord('601318', 1000, 45, 45),
        new HoldRecord('000858', 200, 150, 150)
      ]);
      const summary: PositionSummary = await provider.summary();
      expect(summary.count).assertEqual(2);
      // 桩行情对所有 code 返回 48.9：601318=48900，000858=9780
      expect(summary.marketValue).assertEqual(58680);
      expect(summary.costTotal).assertEqual(75000);
      expect(summary.totalPnl).assertEqual(-16320);
    });

    it('fault_injection_throws', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalPositionProvider = await rig.ready([new HoldRecord('601318', 1000, 45, 45)]);
      MockFaults.failPositions = true;
      let failed: boolean = false;
      try {
        await provider.positions();
      } catch (err) {
        failed = true;
      }
      expect(failed).assertTrue();
      MockFaults.reset();
      const rows: Position[] = await provider.positions();
      expect(rows.length).assertEqual(1);
    });
  });
}
