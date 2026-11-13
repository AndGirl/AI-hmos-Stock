import { describe, expect, it } from '@ohos/hypium';
import { JournalEntry, OrderJournalStore } from '../main/ets/store/OrderJournalStore';
import { StorageAdapter } from '../main/ets/store/StorageAdapter';

function entry(id: string, status: string): JournalEntry {
  return new JournalEntry(id, '600519', 'buy', 10.5, 100, status, Date.now());
}

/**
 * M10-2 / AC-113 委托流水单测：
 * 提交前落盘、同键覆盖、状态更新、未终态补偿列表、20 条上限、跨实例可读。
 * 未注入 context 时 `StorageAdapter` 退化为内存，因此可直接 new。
 */
export default function orderJournalStoreTest(): void {
  describe('OrderJournalStore', () => {
    it('put_and_get', 0, async () => {
      const store: OrderJournalStore = new OrderJournalStore();
      await store.load();
      await store.clear();
      await store.put(entry('c1', 'submitted'));
      expect(store.size()).assertEqual(1);
      const found: JournalEntry | undefined = store.get('c1');
      expect(found !== undefined).assertTrue();
      expect(found !== undefined ? found.status : '').assertEqual('submitted');
    });

    it('same_key_overwrites', 0, async () => {
      const store: OrderJournalStore = new OrderJournalStore();
      await store.load();
      await store.clear();
      await store.put(entry('c1', 'submitted'));
      await store.put(entry('c1', 'accepted'));
      expect(store.size()).assertEqual(1);
      const found: JournalEntry | undefined = store.get('c1');
      expect(found !== undefined ? found.status : '').assertEqual('accepted');
    });

    it('mark_updates_status', 0, async () => {
      const store: OrderJournalStore = new OrderJournalStore();
      await store.load();
      await store.clear();
      await store.put(entry('c2', 'submitted'));
      await store.mark('c2', 'filled');
      const found: JournalEntry | undefined = store.get('c2');
      expect(found !== undefined ? found.status : '').assertEqual('filled');
    });

    it('mark_missing_is_noop', 0, async () => {
      const store: OrderJournalStore = new OrderJournalStore();
      await store.load();
      await store.clear();
      await store.mark('nope', 'filled');
      expect(store.size()).assertEqual(0);
    });

    it('pending_lists_only_unfinished', 0, async () => {
      const store: OrderJournalStore = new OrderJournalStore();
      await store.load();
      await store.clear();
      await store.put(entry('a', 'submitted'));
      await store.put(entry('b', 'filled'));
      await store.put(entry('c', 'partial'));
      await store.put(entry('d', 'rejected'));
      const pending: JournalEntry[] = store.pending();
      expect(pending.length).assertEqual(2);
      expect(pending[0].clientOrderId).assertEqual('a');
      expect(pending[1].clientOrderId).assertEqual('c');
    });

    it('caps_to_twenty', 0, async () => {
      const store: OrderJournalStore = new OrderJournalStore();
      await store.load();
      await store.clear();
      for (let i = 0; i < 25; i++) {
        await store.put(entry(`k${i}`, 'submitted'));
      }
      expect(store.size()).assertEqual(20);
      // 最旧的 5 条被淘汰
      expect(store.get('k0') === undefined).assertTrue();
      expect(store.get('k24') !== undefined).assertTrue();
    });

    it('persists_across_instances', 0, async () => {
      const first: OrderJournalStore = new OrderJournalStore();
      await first.load();
      await first.clear();
      await first.put(entry('p1', 'submitted'));

      const second: OrderJournalStore = new OrderJournalStore();
      await second.load();
      const found: JournalEntry | undefined = second.get('p1');
      expect(found !== undefined).assertTrue();
      expect(found !== undefined ? found.code : '').assertEqual('600519');
      await first.clear();
    });

    it('clear_empties_storage', 0, async () => {
      const store: OrderJournalStore = new OrderJournalStore();
      await store.load();
      await store.put(entry('x', 'submitted'));
      await store.clear();
      expect(store.size()).assertEqual(0);
      const raw: string = await StorageAdapter.getString('order_journal_v1', '');
      expect(raw.length).assertEqual(0);
    });
  });
}
