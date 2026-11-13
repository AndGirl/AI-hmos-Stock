import { describe, expect, it } from '@ohos/hypium';
import {
  QuoteListener,
  QuoteProvider,
  QuoteSnapshot,
  QuoteSubscription,
  TradeStatus
} from '../main/ets/model/QuoteModels';
import { LocalTradeProvider } from '../main/ets/provider/LocalTradeProvider';
import { TradeAccountStore, HoldRecord } from '../main/ets/store/TradeAccountStore';
import { TradeOrderStore } from '../main/ets/store/TradeOrderStore';
import { OrderJournalStore } from '../main/ets/store/OrderJournalStore';
import {
  CancelResult,
  OpenAccountResult,
  OrderDraft,
  OrderItem,
  OrderPage,
  OrderQuery,
  OrderResult,
  TradeContext
} from '../main/ets/model/TradeModels';
import { TradeAuth } from '../main/ets/mock/TradeSeeds';
import { MockFaults } from '../main/ets/mock/MockFaults';

class NoopSubscription implements QuoteSubscription {
  unsubscribe(): void {
  }
}

/** 测试桩行情：可改 last/status，用于驱动撮合。 */
class StubQuotes implements QuoteProvider {
  last: number = 10;
  status: TradeStatus = 'open';

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
      name: '示范股',
      status: this.status,
      snapshotTime: Date.now(),
      isNew: false,
      last: this.last,
      prevClose: 10,
      chg: this.last - 10,
      pct: (this.last - 10) / 10 * 100,
      volume: 1000,
      lastVolume: 10,
      amount: 10000,
      amplitude: 1,
      turnover: 1,
      pe: 10,
      pb: 1,
      limitUp: 11,
      limitDown: 9
    };
    return item;
  }
}

class Rig {
  quotes: StubQuotes = new StubQuotes();
  accounts: TradeAccountStore = new TradeAccountStore();
  orders: TradeOrderStore = new TradeOrderStore();
  journal: OrderJournalStore = new OrderJournalStore();
  provider: LocalTradeProvider | undefined = undefined;

  async ready(): Promise<LocalTradeProvider> {
    await this.accounts.load();
    await this.accounts.resetAll();
    await this.orders.load();
    await this.orders.clear();
    await this.journal.load();
    await this.journal.clear();
    TradeAuth.loggedIn = true;
    MockFaults.reset();
    this.provider = new LocalTradeProvider(this.quotes, this.accounts, this.orders, this.journal);
    return this.provider;
  }
}

function draft(price: number, qty: number, clientOrderId: string, side?: 'buy' | 'sell'): OrderDraft {
  return new OrderDraft('600519', '50012345', price, qty, clientOrderId, side);
}

/**
 * M10-2 / AC-113~117 本地交易网关单测：
 * 成交/挂单/幂等/拒单/撤单/卖出/委托列表/资金与持仓记账。
 */
export default function localTradeProviderTest(): void {
  describe('LocalTradeProvider', () => {
    it('buy_cross_fills_and_books_cash', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalTradeProvider = await rig.ready();
      const result: OrderResult = await provider.submit(draft(10.5, 100, 'c1'));
      expect(result.status).assertEqual('accepted');
      const item: OrderItem | undefined = rig.orders.get('c1');
      expect(item !== undefined ? item.state : '').assertEqual('filled');
      expect(rig.accounts.availableOf('50012345')).assertEqual(498950);
      const hold: HoldRecord | undefined = rig.accounts.holdingOf('50012345', '600519');
      expect(hold !== undefined ? hold.qty : 0).assertEqual(100);
    });

    it('buy_not_crossed_then_accept_then_fill', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalTradeProvider = await rig.ready();
      const result: OrderResult = await provider.submit(draft(9.5, 100, 'c2'));
      expect(result.status).assertEqual('accepted');
      const pending: OrderItem | undefined = rig.orders.get('c2');
      expect(pending !== undefined ? pending.state : '').assertEqual('pending');
      // 冻结 9.5 × 100
      expect(rig.accounts.availableOf('50012345')).assertEqual(500000 - 950);

      await provider.tick(Date.now() + 2000);
      expect(rig.orders.get('c2')?.state).assertEqual('accepted');

      // 行情跌到 9.4，限价 9.5 ≥ 最新价 → 成交
      rig.quotes.last = 9.4;
      await provider.tick(Date.now() + 3000);
      expect(rig.orders.get('c2')?.state).assertEqual('filled');
      expect(rig.accounts.availableOf('50012345')).assertEqual(500000 - 950);
    });

    it('idempotent_same_client_order_id', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalTradeProvider = await rig.ready();
      const first: OrderResult = await provider.submit(draft(10.5, 100, 'same'));
      const second: OrderResult = await provider.submit(draft(10.5, 100, 'same'));
      expect(first.orderId).assertEqual(second.orderId);
      expect(rig.orders.size()).assertEqual(1);
    });

    it('reject_fund_short', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalTradeProvider = await rig.ready();
      const result: OrderResult = await provider.submit(draft(11, 100000, 'big'));
      expect(result.status).assertEqual('rejected');
      expect(result.reasonCode).assertEqual('fund_short');
      expect(rig.orders.get('big')?.state).assertEqual('rejected');
    });

    it('reject_when_closed', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalTradeProvider = await rig.ready();
      rig.quotes.status = 'closed';
      const result: OrderResult = await provider.submit(draft(10.5, 100, 'closed1'));
      expect(result.status).assertEqual('rejected');
      expect(result.reasonCode).assertEqual('closed');
    });

    it('cancel_pending_releases_freeze', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalTradeProvider = await rig.ready();
      await provider.submit(draft(9.5, 200, 'c3'));
      expect(rig.accounts.availableOf('50012345')).assertEqual(500000 - 1900);
      const item: OrderItem | undefined = rig.orders.get('c3');
      const canceled: CancelResult = await provider.cancelOrder(item !== undefined ? item.orderId : '', 'c3');
      expect(canceled.ok).assertTrue();
      expect(canceled.state).assertEqual('canceled');
      expect(rig.accounts.availableOf('50012345')).assertEqual(500000);
    });

    it('cancel_filled_is_rejected_idempotently', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalTradeProvider = await rig.ready();
      await provider.submit(draft(10.5, 100, 'c4'));
      const item: OrderItem | undefined = rig.orders.get('c4');
      const canceled: CancelResult = await provider.cancelOrder(item !== undefined ? item.orderId : '', 'c4');
      expect(canceled.ok).assertFalse();
      expect(canceled.state).assertEqual('filled');
      expect(canceled.reasonCode).assertEqual('filled');
    });

    it('sell_reduces_holding_and_adds_cash', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalTradeProvider = await rig.ready();
      await rig.accounts.applyFill('50012345', 'buy', '600519', 10, 100);
      await rig.accounts.flush();
      const result: OrderResult = await provider.submit(draft(9.5, 100, 's1', 'sell'));
      expect(result.status).assertEqual('accepted');
      const hold: HoldRecord | undefined = rig.accounts.holdingOf('50012345', '600519');
      expect(hold === undefined).assertTrue();
      // 卖出成交价 = 最新价 10
      expect(rig.accounts.availableOf('50012345')).assertEqual(500000 - 1000 + 950);
    });

    it('list_orders_paging', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalTradeProvider = await rig.ready();
      await provider.submit(draft(9.5, 100, 'p1'));
      await provider.submit(draft(9.6, 100, 'p2'));
      const page: OrderPage = await provider.listOrders(new OrderQuery(0, 1));
      expect(page.total).assertEqual(2);
      expect(page.items.length).assertEqual(1);
      expect(page.hasMore).assertTrue();
    });

    it('open_account_sets_opened', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalTradeProvider = await rig.ready();
      await rig.accounts.setOpened('50012345', false);
      const result: OpenAccountResult = await provider.openAccount();
      expect(result.ok).assertTrue();
      expect(rig.accounts.record('50012345')?.opened).assertTrue();
    });

    it('load_context_reports_closed_gate_inputs', 0, async () => {
      const rig: Rig = new Rig();
      const provider: LocalTradeProvider = await rig.ready();
      rig.quotes.status = 'lunch';
      const context: TradeContext = await provider.loadContext('600519', 'detail');
      expect(context.tradable.status).assertEqual('lunch');
      expect(context.accounts.length).assertEqual(2);
      expect(context.loggedIn).assertTrue();
    });
  });
}
