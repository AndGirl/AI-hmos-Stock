import { describe, it, expect } from '@ohos/hypium';
import {
  RemoveSnapshot,
  WatchAddInput,
  WatchlistAddOutcome,
  WatchlistGroupOutcome,
  WatchlistRemoveOutcome,
  WatchlistSnapshot,
  WatchlistStore,
  WatchItem
} from 'commons_data';

/**
 * M7 Store 行为单测（Hypium Local Test）：
 * `StorageAdapter` 在未注入 context 时退化为纯内存，因此可直接 new WatchlistStore()。
 * 每个用例先 `resetToSeeds()` 回到 45 只种子，保证与执行顺序无关。
 */
function codesOfSnapshot(snap: WatchlistSnapshot): string[] {
  const codes: string[] = [];
  for (let i = 0; i < snap.items.length; i++) {
    codes.push(snap.items[i].code);
  }
  return codes;
}

function findItem(snap: WatchlistSnapshot, code: string): WatchItem | undefined {
  for (let i = 0; i < snap.items.length; i++) {
    if (snap.items[i].code === code) {
      return snap.items[i];
    }
  }
  return undefined;
}

export default function watchlistStoreTest(): void {
  describe('WatchlistStore', () => {
    it('restore_keeps_original_order', 0, async () => {
      const store: WatchlistStore = new WatchlistStore();
      await store.load();
      await store.resetToSeeds();
      const before: WatchlistSnapshot = await store.snapshot();
      const expected: string[] = codesOfSnapshot(before);
      // 连续移出第 2~4 行（模拟编辑态勾选相邻 3 行）
      const removeCodes: string[] = [expected[1], expected[2], expected[3]];
      const removed: WatchlistRemoveOutcome = await store.remove(removeCodes);
      expect(removed.removed.length).assertEqual(3);
      expect(removed.snapshots.length).assertEqual(3);
      const restored: number = await store.restore(removed.snapshots);
      expect(restored).assertEqual(3);
      const after: WatchlistSnapshot = await store.snapshot();
      const actual: string[] = codesOfSnapshot(after);
      expect(actual.length).assertEqual(expected.length);
      for (let i = 0; i < expected.length; i++) {
        expect(actual[i]).assertEqual(expected[i]);
      }
    });

    it('restore_does_not_exceed_limit', 0, async () => {
      const store: WatchlistStore = new WatchlistStore();
      await store.load();
      await store.resetToSeeds();
      // 45 → 填到 50
      const fill: WatchAddInput[] = [];
      for (let i = 0; i < 5; i++) {
        fill.push(new WatchAddInput(`9000${i}`, []));
      }
      const filled: WatchlistAddOutcome = await store.addMany(fill, false);
      expect(filled.added.length).assertEqual(5);
      expect(store.count()).assertEqual(50);
      // 移出 2 只 → 48
      const snap: WatchlistSnapshot = await store.snapshot();
      const removed: WatchlistRemoveOutcome = await store.remove([snap.items[0].code, snap.items[1].code]);
      expect(removed.removed.length).assertEqual(2);
      expect(store.count()).assertEqual(48);
      // 在别处补回 2 只 → 50
      const refill: WatchAddInput[] = [new WatchAddInput('900010', []), new WatchAddInput('900011', [])];
      await store.addMany(refill, false);
      expect(store.count()).assertEqual(50);
      // 再撤销：不得突破 50
      const restored: number = await store.restore(removed.snapshots);
      expect(restored).assertEqual(0);
      expect(store.count()).assertEqual(50);
    });

    it('add_many_partial_limit', 0, async () => {
      const store: WatchlistStore = new WatchlistStore();
      await store.load();
      await store.resetToSeeds();
      const inputs: WatchAddInput[] = [];
      for (let i = 0; i < 10; i++) {
        inputs.push(new WatchAddInput(`9100${i}`, []));
      }
      const outcome: WatchlistAddOutcome = await store.addMany(inputs, false);
      expect(outcome.added.length).assertEqual(5);
      expect(outcome.rejectedLimit.length).assertEqual(5);
      expect(store.count()).assertEqual(50);
    });

    it('add_many_skips_existing', 0, async () => {
      const store: WatchlistStore = new WatchlistStore();
      await store.load();
      await store.resetToSeeds();
      const outcome: WatchlistAddOutcome = await store.addMany([
        new WatchAddInput('600519', []),
        new WatchAddInput('920001', [])
      ], false);
      expect(outcome.existed.length).assertEqual(1);
      expect(outcome.added.length).assertEqual(1);
      const added: WatchItem | undefined = findItem(await store.snapshot(), '920001');
      // 新增按板块派生系统组：主板 → fin
      expect(added !== undefined).assertTrue();
      if (added !== undefined) {
        expect(added.groups.indexOf('fin') >= 0).assertTrue();
      }
    });

    it('group_crud_and_limits', 0, async () => {
      const store: WatchlistStore = new WatchlistStore();
      await store.load();
      await store.resetToSeeds();
      // 先建一个具名用户组，用于验证大小写不敏感去重（种子里的「我的关注」没有存 name）
      const first: WatchlistGroupOutcome = await store.createGroup('g0');
      expect(first.succeeded()).assertTrue();
      const dup: WatchlistGroupOutcome = await store.createGroup('G0');
      expect(dup.reason).assertEqual('duplicate');
      const long: WatchlistGroupOutcome = await store.createGroup('123456789');
      expect(long.reason).assertEqual('too_long');
      const emoji: WatchlistGroupOutcome = await store.createGroup('long🚀');
      expect(emoji.reason).assertEqual('emoji');
      const empty: WatchlistGroupOutcome = await store.createGroup('   ');
      expect(empty.reason).assertEqual('empty');
      // 种子里已有 1 个用户组，加上 g0 已有 2 个；再建 5 个到 7 个上限
      for (let i = 1; i <= 5; i++) {
        const created: WatchlistGroupOutcome = await store.createGroup(`g${i}`);
        expect(created.succeeded()).assertTrue();
      }
      const over: WatchlistGroupOutcome = await store.createGroup('g6');
      expect(over.reason).assertEqual('limit');
      // 系统组只读
      const sysRename: WatchlistGroupOutcome = await store.renameGroup('fin', 'x');
      expect(sysRename.reason).assertEqual('system_readonly');
      const sysDelete: WatchlistGroupOutcome = await store.deleteGroup('kcb');
      expect(sysDelete.reason).assertEqual('system_readonly');
    });

    it('delete_group_keeps_stocks_and_membership', 0, async () => {
      const store: WatchlistStore = new WatchlistStore();
      await store.load();
      await store.resetToSeeds();
      const before: WatchlistSnapshot = await store.snapshot();
      const total: number = before.items.length;
      const deleted: WatchlistGroupOutcome = await store.deleteGroup('user');
      expect(deleted.succeeded()).assertTrue();
      const after: WatchlistSnapshot = await store.snapshot();
      // 只删归属不删股
      expect(after.items.length).assertEqual(total);
      // 不允许无组股票：每只至少有一个非「全部」分组
      for (let i = 0; i < after.items.length; i++) {
        let hasReal: boolean = false;
        for (let j = 0; j < after.items[i].groups.length; j++) {
          if (after.items[i].groups[j] !== 'all') {
            hasReal = true;
            break;
          }
        }
        expect(hasReal).assertTrue();
        expect(after.items[i].groups.indexOf('user') < 0).assertTrue();
      }
    });

    it('pending_marks_and_sync', 0, async () => {
      const store: WatchlistStore = new WatchlistStore();
      await store.load();
      await store.resetToSeeds();
      const outcome: WatchlistAddOutcome = await store.addMany([
        new WatchAddInput('930001', []),
        new WatchAddInput('930002', [])
      ], true);
      expect(outcome.pending.length).assertEqual(2);
      const pendingSnap: WatchlistSnapshot = await store.snapshot();
      let pendingCount: number = 0;
      for (let i = 0; i < pendingSnap.items.length; i++) {
        if (pendingSnap.items[i].pending) {
          pendingCount++;
        }
      }
      expect(pendingCount).assertEqual(2);
      const synced: number = await store.syncPending();
      expect(synced).assertEqual(2);
      expect(store.pendingCount()).assertEqual(0);
    });

    it('update_groups_resolves_membership', 0, async () => {
      const store: WatchlistStore = new WatchlistStore();
      await store.load();
      await store.resetToSeeds();
      const ok: boolean = await store.updateGroups('600519', ['ug-test']);
      expect(ok).assertTrue();
      const snap: WatchlistSnapshot = await store.snapshot();
      const item: WatchItem | undefined = findItem(snap, '600519');
      expect(item !== undefined).assertTrue();
      if (item !== undefined) {
        expect(item.groups.indexOf('fin') >= 0).assertTrue();
        expect(item.groups.indexOf('ug-test') >= 0).assertTrue();
        // 虚拟组不落库
        expect(item.groups.indexOf('all') < 0).assertTrue();
      }
    });
  });
}
