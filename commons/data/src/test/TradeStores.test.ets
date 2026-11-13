import { describe, expect, it } from '@ohos/hypium';
import { TradeAccountStore, AccountRecord, HoldRecord } from '../main/ets/store/TradeAccountStore';
import { TradeOrderStore } from '../main/ets/store/TradeOrderStore';
import { AccountInfo, OrderItem, OrderPage, OrderQuery } from '../main/ets/model/TradeModels';

function order(clientOrderId: string, orderId: string, state: string, createdAt: number): OrderItem {
  return new OrderItem(clientOrderId, orderId, '50012345', '600519', '贵州茅台', 'buy', 10.5, 100, 0,
    state === 'filled' ? 'filled' : (state === 'pending' ? 'pending' : 'accepted'), createdAt, createdAt, '');
}

/**
 * M10 交易存储单测：账户/持仓（`trade_account_v1`）与委托库（`trade_orders_v1`）。
 * 未注入 context 时 `StorageAdapter` 退化为内存，因此可直接 new。
 */
export default function tradeStoresTest(): void {
  describe('TradeAccountStore', () => {
    it('seeds_two_accounts', 0, async () => {
      const store: TradeAccountStore = new TradeAccountStore();
      await store.load();
      await store.resetAll();
      const ids: string[] = store.ids();
      expect(ids.length).assertEqual(2);
      const infos: AccountInfo[] = store.infos();
      expect(infos.length).assertEqual(2);
      expect(infos[0].available).assertEqual(500000);
      expect(infos[1].holdQty).assertEqual(500);
    });

    it('freeze_reduces_available', 0, async () => {
      const store: TradeAccountStore = new TradeAccountStore();
      await store.load();
      await store.resetAll();
      await store.freeze('50012345', 10000);
      expect(store.availableOf('50012345')).assertEqual(490000);
      await store.unfreeze('50012345', 10000);
      expect(store.availableOf('50012345')).assertEqual(500000);
    });

    it('buy_fill_updates_cash_and_holding', 0, async () => {
      const store: TradeAccountStore = new TradeAccountStore();
      await store.load();
      await store.resetAll();
      await store.applyFill('50012345', 'buy', '000001', 10, 1000);
      expect(store.availableOf('50012345')).assertEqual(490000);
      const hold: HoldRecord | undefined = store.holdingOf('50012345', '000001');
      expect(hold !== undefined).assertTrue();
      expect(hold !== undefined ? hold.qty : 0).assertEqual(1000);
      expect(hold !== undefined ? hold.costPrice : 0).assertEqual(10);
    });

    it('weighted_cost_on_second_buy', 0, async () => {
      const store: TradeAccountStore = new TradeAccountStore();
      await store.load();
      await store.resetAll();
      await store.applyFill('50012345', 'buy', '000001', 10, 1000);
      await store.applyFill('50012345', 'buy', '000001', 20, 1000);
      const hold: HoldRecord | undefined = store.holdingOf('50012345', '000001');
      expect(hold !== undefined ? hold.qty : 0).assertEqual(2000);
      expect(hold !== undefined ? hold.costPrice : 0).assertEqual(15);
    });

    it('sell_fill_releases_cash_and_qty', 0, async () => {
      const store: TradeAccountStore = new TradeAccountStore();
      await store.load();
      await store.resetAll();
      await store.applyFill('50012345', 'buy', '000001', 10, 1000);
      await store.applyFill('50012345', 'sell', '000001', 12, 400);
      const hold: HoldRecord | undefined = store.holdingOf('50012345', '000001');
      expect(hold !== undefined ? hold.qty : 0).assertEqual(600);
      expect(store.availableOf('50012345')).assertEqual(490000 + 4800);
    });

    it('open_and_close_account', 0, async () => {
      const store: TradeAccountStore = new TradeAccountStore();
      await store.load();
      await store.resetAll();
      await store.setOpened('50012345', false);
      const record: AccountRecord | undefined = store.record('50012345');
      expect(record !== undefined ? record.opened : true).assertFalse();
      expect(store.infos()[1].opened).assertTrue();
      await store.open('50012345');
      expect(store.record('50012345')?.opened).assertTrue();
    });

    it('persists_across_instances', 0, async () => {
      const first: TradeAccountStore = new TradeAccountStore();
      await first.load();
      await first.resetAll();
      await first.applyFill('50012345', 'buy', '600519', 100, 100);
      await first.flush();

      const second: TradeAccountStore = new TradeAccountStore();
      await second.load();
      expect(second.holdingOf('50012345', '600519') !== undefined).assertTrue();
      await second.resetAll();
    });
  });

  describe('TradeOrderStore', () => {
    it('upsert_and_get', 0, async () => {
      const store: TradeOrderStore = new TradeOrderStore();
      await store.load();
      await store.clear();
      await store.upsert(order('c1', 'o1', 'accepted', 1000));
      expect(store.size()).assertEqual(1);
      expect(store.get('c1') !== undefined).assertTrue();
      expect(store.getByOrderId('o1') !== undefined).assertTrue();
    });

    it('upsert_same_key_replaces', 0, async () => {
      const store: TradeOrderStore = new TradeOrderStore();
      await store.load();
      await store.clear();
      await store.upsert(order('c1', 'o1', 'accepted', 1000));
      await store.upsert(order('c1', 'o1', 'filled', 1000));
      expect(store.size()).assertEqual(1);
      expect(store.get('c1')?.state).assertEqual('filled');
    });

    it('sorts_newest_first', 0, async () => {
      const store: TradeOrderStore = new TradeOrderStore();
      await store.load();
      await store.clear();
      await store.upsert(order('old', 'o1', 'accepted', 1000));
      await store.upsert(order('new', 'o2', 'accepted', 2000));
      const page: OrderPage = store.list(new OrderQuery(0, 20));
      expect(page.items[0].clientOrderId).assertEqual('new');
    });

    it('paging_and_filter', 0, async () => {
      const store: TradeOrderStore = new TradeOrderStore();
      await store.load();
      await store.clear();
      for (let i = 0; i < 25; i++) {
        await store.upsert(order(`k${i}`, `o${i}`, 'accepted', 1000 + i));
      }
      const first: OrderPage = store.list(new OrderQuery(0, 20));
      expect(first.items.length).assertEqual(20);
      expect(first.total).assertEqual(25);
      expect(first.hasMore).assertTrue();
      const second: OrderPage = store.list(new OrderQuery(1, 20));
      expect(second.items.length).assertEqual(5);
      expect(second.hasMore).assertFalse();

      await store.upsert(order('f1', 'of1', 'filled', 3000));
      const filled: OrderPage = store.list(new OrderQuery(0, 20, 'filled'));
      expect(filled.total).assertEqual(1);
      expect(filled.items[0].clientOrderId).assertEqual('f1');
    });

    it('open_orders_excludes_final', 0, async () => {
      const store: TradeOrderStore = new TradeOrderStore();
      await store.load();
      await store.clear();
      await store.upsert(order('a', 'oa', 'pending', 1000));
      await store.upsert(order('b', 'ob', 'filled', 1100));
      expect(store.openOrders().length).assertEqual(1);
      expect(store.openOrders()[0].clientOrderId).assertEqual('a');
    });

    it('caps_to_max', 0, async () => {
      const store: TradeOrderStore = new TradeOrderStore();
      await store.load();
      await store.clear();
      for (let i = 0; i < 205; i++) {
        await store.upsert(order(`x${i}`, `ox${i}`, 'accepted', 1000 + i));
      }
      expect(store.size()).assertEqual(200);
      await store.clear();
    });
  });
}
