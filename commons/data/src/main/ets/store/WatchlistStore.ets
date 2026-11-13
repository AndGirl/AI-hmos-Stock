import { GroupType, WatchGroup, WatchItem } from '../entities/WatchEntities';
import { buildStockSeeds, buildWatchGroups, buildWatchItems } from '../mock/MarketSeeds';
import { StorageAdapter } from './StorageAdapter';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'WatchStore';
const WATCHLIST_KEY: string = 'watchlist_v1';
const MIGRATED_KEY: string = 'watchlist_migrated_v1';
const WRITE_DEBOUNCE_MS: number = 200;
const MAX_ITEMS: number = 50;
/**
 * Mock 迁移条数：比 50 上限少 5 条，留出空位验证「就地加自选 / 部分成功」（AC-91/96）。
 * 50 只上限逻辑本身不变（MAX_ITEMS 仍为 50，M7 用例可继续压测超限）。
 */
const MOCK_SEED_ITEMS: number = 45;

/** 落盘结构（§5.5）：version + items + groups，pending 供 M7 离线待同步使用。 */
interface WatchlistDiskItem {
  code: string;
  groups: string[];
  addedAt: number;
  pending: boolean;
}

interface WatchlistDiskGroup {
  id: string;
  type: string;
  order: number;
  name: string;
}

interface WatchlistDiskData {
  version: number;
  items: WatchlistDiskItem[];
  groups: WatchlistDiskGroup[];
}

export class WatchlistAddOutcome {
  added: string[] = [];
  existed: string[] = [];
  rejectedLimit: string[] = [];

  total(): number {
    return this.added.length + this.existed.length + this.rejectedLimit.length;
  }

  succeeded(): boolean {
    return this.added.length > 0;
  }
}

/** 移除结果：removed 实际删除，missing 本地已不存在（幂等）。 */
export class WatchlistRemoveOutcome {
  removed: string[] = [];
  missing: string[] = [];

  succeeded(): boolean {
    return this.removed.length > 0 || this.missing.length > 0;
  }
}

/**
 * 一次变更的内容：added 用于自选页「新增行定位 + 高亮」，removed 只做重建
 * （删除后不能再去定位已不存在的行，也不能把用户从当前分组切走）。
 */
export class WatchlistChange {
  added: string[] = [];
  removed: string[] = [];
}

/** 变更监听：M7 的自选页 / 搜索页「已添加」态按增量刷新（AC-91 / AC-97）。 */
export type WatchlistChangeListener = (change: WatchlistChange) => void;

/** 自选快照（读侧统一入口）：仓储与 VM 都从这里拿集合，避免再读 Mock Provider。 */
export class WatchlistSnapshot {
  groups: WatchGroup[] = [];
  items: WatchItem[] = [];
}

/**
 * 自选存储（M7-1 的最小版，M6-7 就地加自选先落地）：
 * - 首次启动把 Mock 种子迁到 `watchlist_v1` 并写迁移标记，之后以磁盘为准；
 * - 50 只上限在 Store 内判定（不只在 UI）；
 * - 写合并 200ms，避免连点写盘；
 * - 只做数据，不出现 UI 文案与路由。
 */
export class WatchlistStore {
  private groups: WatchGroup[] = [];
  private items: WatchItem[] = [];
  private loaded: boolean = false;
  private loading: Promise<void> | undefined = undefined;
  private writeTimer: number = -1;
  private listeners: WatchlistChangeListener[] = [];

  async load(): Promise<void> {
    if (this.loaded) {
      return;
    }
    if (this.loading !== undefined) {
      return this.loading;
    }
    this.loading = this.doLoad();
    return this.loading;
  }

  isLoaded(): boolean {
    return this.loaded;
  }

  count(): number {
    return this.items.length;
  }

  async codes(): Promise<string[]> {
    await this.load();
    const result: string[] = [];
    for (let i = 0; i < this.items.length; i++) {
      result.push(this.items[i].code);
    }
    return result;
  }

  async has(code: string): Promise<boolean> {
    await this.load();
    return this.indexOf(code) >= 0;
  }

  /**
   * 读侧快照（P0 数据同源）：返回拷贝，调用方不能改 Store 内部状态。
   * 自选仓储改用本方法后，「搜索加自选 → 自选页」共用同一份数据。
   */
  async snapshot(): Promise<WatchlistSnapshot> {
    await this.load();
    const snap: WatchlistSnapshot = new WatchlistSnapshot();
    for (let i = 0; i < this.groups.length; i++) {
      snap.groups.push(new WatchGroup(this.groups[i].id, this.groups[i].type,
        this.groups[i].order, this.groups[i].name));
    }
    for (let i = 0; i < this.items.length; i++) {
      snap.items.push(new WatchItem(this.items[i].code, this.items[i].groups.slice(),
        this.items[i].addedAt));
    }
    return snap;
  }

  /** 添加：已存在计入 existed，超 50 只计入 rejectedLimit，其余生效（AC-96 部分成功）。 */
  async add(codes: string[], groups: string[]): Promise<WatchlistAddOutcome> {
    await this.load();
    const outcome: WatchlistAddOutcome = new WatchlistAddOutcome();
    const targetGroups: string[] = groups.length > 0 ? groups : ['all'];
    for (let i = 0; i < codes.length; i++) {
      const code: string = codes[i];
      if (code.length === 0) {
        continue;
      }
      if (this.indexOf(code) >= 0) {
        outcome.existed.push(code);
        continue;
      }
      if (this.items.length >= MAX_ITEMS) {
        outcome.rejectedLimit.push(code);
        continue;
      }
      this.items.push(new WatchItem(code, targetGroups.slice(), Date.now()));
      outcome.added.push(code);
    }
    if (outcome.added.length > 0) {
      this.scheduleWrite();
      this.notifyChange(outcome.added, []);
    }
    return outcome;
  }

  /**
   * 移除（M6 追加：行情页「已添加」再点一次 = 撤出该行，AC-91 变更）：
   * - 只删自选集合，不动分组定义；
   * - 幂等：本地已不存在的 code 记 missing，不报错；
   * - 与 add 共用 200ms 合并写盘，并通知变更（自选页据此计数 -1、行消失）。
   */
  async remove(codes: string[]): Promise<WatchlistRemoveOutcome> {
    await this.load();
    const outcome: WatchlistRemoveOutcome = new WatchlistRemoveOutcome();
    for (let i = 0; i < codes.length; i++) {
      const code: string = codes[i];
      if (code.length === 0) {
        continue;
      }
      const index: number = this.indexOf(code);
      if (index < 0) {
        outcome.missing.push(code);
        continue;
      }
      this.items.splice(index, 1);
      outcome.removed.push(code);
    }
    if (outcome.removed.length > 0) {
      this.scheduleWrite();
      this.notifyChange([], outcome.removed);
    }
    return outcome;
  }

  /**
   * 清空全部自选（debug「清空自选（空态）」用，2026-11-13）：
   * 真删数据并**立即落盘**，不是展示层置空；重启后仍是空。
   * 只清 items，分组定义保留（否则分组页签会整体消失）。
   */
  async clear(): Promise<number> {
    await this.load();
    if (this.items.length === 0) {
      return 0;
    }
    const removed: string[] = [];
    for (let i = 0; i < this.items.length; i++) {
      removed.push(this.items[i].code);
    }
    this.items = [];
    this.notifyChange([], removed);
    await this.writeNow();
    return removed.length;
  }

  /**
   * 恢复 Mock 种子（debug「重置」用）：分组 + 45 只种子整体重建并落盘。
   * 与首次迁移同口径（50 上限留 5 个空位）。
   */
  async resetToSeeds(): Promise<void> {
    this.groups = buildWatchGroups();
    this.items = buildWatchItems(buildStockSeeds()).slice(0, MOCK_SEED_ITEMS);
    this.loaded = true;
    this.loading = undefined;
    await this.writeNow();
    this.notifyChange([], []);
  }

  subscribe(listener: WatchlistChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unsubscribe(listener: WatchlistChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  private indexOf(code: string): number {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].code === code) {
        return i;
      }
    }
    return -1;
  }

  private notifyChange(added: string[], removed: string[]): void {
    const change: WatchlistChange = new WatchlistChange();
    change.added = added;
    change.removed = removed;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i](change);
    }
  }

  private async doLoad(): Promise<void> {
    const text: string = await StorageAdapter.getString(WATCHLIST_KEY, '');
    const migrated: string = await StorageAdapter.getString(MIGRATED_KEY, 'false');
    if (text.length === 0 || migrated !== 'true') {
      // 首次启动迁移：Mock 种子落盘一次（§5.5 规则 3）。
      this.groups = buildWatchGroups();
      this.items = buildWatchItems(buildStockSeeds()).slice(0, MOCK_SEED_ITEMS);
      this.loaded = true;
      this.loading = undefined;
      await StorageAdapter.putString(WATCHLIST_KEY, JSON.stringify(WatchlistStore.toDisk(this)));
      await StorageAdapter.putString(MIGRATED_KEY, 'true');
      return;
    }
    const parsed: WatchlistDiskData | undefined = WatchlistStore.parseDisk(text);
    if (parsed === undefined) {
      hilog.warn(DOMAIN, TAG, 'disk_corrupt fallback=seeds');
      this.groups = buildWatchGroups();
      this.items = buildWatchItems(buildStockSeeds()).slice(0, MOCK_SEED_ITEMS);
    } else {
      this.groups = WatchlistStore.groupsOf(parsed);
      this.items = WatchlistStore.itemsOf(parsed);
    }
    this.loaded = true;
    this.loading = undefined;
  }

  private scheduleWrite(): void {
    if (this.writeTimer !== -1) {
      clearTimeout(this.writeTimer);
    }
    this.writeTimer = setTimeout((): void => {
      this.writeTimer = -1;
      this.flush();
    }, WRITE_DEBOUNCE_MS);
  }

  private async flush(): Promise<void> {
    await StorageAdapter.putString(WATCHLIST_KEY, JSON.stringify(WatchlistStore.toDisk(this)));
  }

  /** 清空/重置要「立刻可见地持久化」：不等 200ms 合并，直接写盘（并把迁移标记置真）。 */
  private async writeNow(): Promise<void> {
    if (this.writeTimer !== -1) {
      clearTimeout(this.writeTimer);
      this.writeTimer = -1;
    }
    await StorageAdapter.putString(WATCHLIST_KEY, JSON.stringify(WatchlistStore.toDisk(this)));
    await StorageAdapter.putString(MIGRATED_KEY, 'true');
  }

  private static toDisk(store: WatchlistStore): WatchlistDiskData {
    const items: WatchlistDiskItem[] = [];
    for (let i = 0; i < store.items.length; i++) {
      items.push({
        code: store.items[i].code,
        groups: store.items[i].groups.slice(),
        addedAt: store.items[i].addedAt,
        pending: false
      });
    }
    const groups: WatchlistDiskGroup[] = [];
    for (let i = 0; i < store.groups.length; i++) {
      groups.push({
        id: store.groups[i].id,
        type: store.groups[i].type,
        order: store.groups[i].order,
        name: store.groups[i].name
      });
    }
    return { version: 1, items: items, groups: groups };
  }

  private static parseDisk(text: string): WatchlistDiskData | undefined {
    try {
      const data: WatchlistDiskData = JSON.parse(text) as WatchlistDiskData;
      if (data === null || data.items === undefined || !Array.isArray(data.items)) {
        return undefined;
      }
      return data;
    } catch (err) {
      return undefined;
    }
  }

  private static groupsOf(data: WatchlistDiskData): WatchGroup[] {
    const groups: WatchGroup[] = [];
    const list: WatchlistDiskGroup[] = data.groups !== undefined ? data.groups : [];
    for (let i = 0; i < list.length; i++) {
      groups.push(new WatchGroup(list[i].id, list[i].type as GroupType, list[i].order,
        list[i].name !== undefined ? list[i].name : ''));
    }
    if (groups.length === 0) {
      return buildWatchGroups();
    }
    return groups;
  }

  private static itemsOf(data: WatchlistDiskData): WatchItem[] {
    const items: WatchItem[] = [];
    for (let i = 0; i < data.items.length; i++) {
      const item: WatchlistDiskItem = data.items[i];
      if (item === undefined || item.code === undefined) {
        continue;
      }
      items.push(new WatchItem(item.code, item.groups !== undefined ? item.groups : ['all'],
        item.addedAt !== undefined ? item.addedAt : 0));
    }
    return items;
  }
}
