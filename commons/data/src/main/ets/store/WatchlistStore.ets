import { GroupType, WatchGroup, WatchItem } from '../entities/WatchEntities';
import { buildStockSeeds, buildWatchGroups, buildWatchItems } from '../mock/MarketSeeds';
import {
  countUserGroups,
  GroupEditReason,
  normalizeGroupName,
  resolveGroupMembership,
  systemGroupsOf,
  validateGroupName,
  WATCHLIST_ALL_GROUP,
  WATCHLIST_MAX_ITEMS,
  WATCHLIST_MAX_USER_GROUPS
} from '../rules/WatchlistRules';
import { StorageAdapter } from './StorageAdapter';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'WatchStore';
const WATCHLIST_KEY: string = 'watchlist_v1';
const MIGRATED_KEY: string = 'watchlist_migrated_v1';
const WRITE_DEBOUNCE_MS: number = 200;
/**
 * Mock 迁移条数：比 50 上限少 5 条，留出空位验证「就地加自选 / 部分成功」（AC-91/96）。
 * 50 只上限逻辑本身不变（MAX_ITEMS 仍为 50，M7 用例可继续压测超限）。
 */
const MOCK_SEED_ITEMS: number = 45;

/** 落盘结构（§5.5）：version + items + groups；pending 供离线待同步使用（M7-1 起真正持久化）。 */
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

/** 添加输入：逐股票给目标分组（M7-2/3 由添加页计算好，Store 只做容量与去重）。 */
export class WatchAddInput {
  code: string;
  groups: string[];

  constructor(code: string, groups: string[]) {
    this.code = code;
    this.groups = groups;
  }
}

export class WatchlistAddOutcome {
  added: string[] = [];
  existed: string[] = [];
  rejectedLimit: string[] = [];
  /** 离线加入、已标待同步的 code（AC-96）。 */
  pending: string[] = [];

  total(): number {
    return this.added.length + this.existed.length + this.rejectedLimit.length;
  }

  succeeded(): boolean {
    return this.added.length > 0;
  }
}

/** 移除快照：撤销（AC-97）恢复原位置 + 原分组 + 原 addedAt/pending 所需的最小信息。 */
export class RemoveSnapshot {
  code: string;
  index: number;
  groups: string[];
  addedAt: number;
  pending: boolean;

  constructor(code: string, index: number, groups: string[], addedAt: number, pending: boolean) {
    this.code = code;
    this.index = index;
    this.groups = groups;
    this.addedAt = addedAt;
    this.pending = pending;
  }
}

/** 移除结果：removed 实际删除，missing 本地已不存在（幂等），snapshots 供 5s 撤销。 */
export class WatchlistRemoveOutcome {
  removed: string[] = [];
  missing: string[] = [];
  snapshots: RemoveSnapshot[] = [];

  succeeded(): boolean {
    return this.removed.length > 0 || this.missing.length > 0;
  }
}

/** 分组编辑结果：reason 为 'ok' 才生效；reassigned 为删除组后回落到系统组的 code。 */
export class WatchlistGroupOutcome {
  reason: GroupEditReason = 'ok';
  groupId: string = '';
  reassigned: string[] = [];

  succeeded(): boolean {
    return this.reason === 'ok';
  }
}

/**
 * 一次变更的内容：added 用于自选页「新增行定位 + 高亮」，removed 只做重建；
 * groupsChanged 为分组定义/归属变化（分组管理、撤销、更新归属），只需重建不定位；
 * pendingSynced 为联网后清零的待同步条数（视图提示用）。
 */
export class WatchlistChange {
  added: string[] = [];
  removed: string[] = [];
  groupsChanged: boolean = false;
  pendingSynced: number = 0;
}

/** 变更监听：M7 的自选页 / 搜索页「已添加」态按增量刷新（AC-91 / AC-97）。 */
export type WatchlistChangeListener = (change: WatchlistChange) => void;

/** 自选快照（读侧统一入口）：仓储与 VM 都从这里拿集合，避免再读 Mock Provider。 */
export class WatchlistSnapshot {
  groups: WatchGroup[] = [];
  items: WatchItem[] = [];
}

/**
 * 自选存储（M7-1）：自选集合与分组定义的唯一来源。
 * - 首次启动把 Mock 种子迁到 `watchlist_v1` 并写迁移标记，之后以磁盘为准；
 * - 50 只上限与用户组 7 个上限都在 Store 内判定（不只在 UI）；
 * - 写合并 200ms，避免连点写盘；需要立即可见的操作用 writeNow；
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

  /** 用户组数量（添加页/分组管理展示容量用）。 */
  userGroupCount(): number {
    return countUserGroups(this.groups);
  }

  pendingCount(): number {
    let count: number = 0;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].pending) {
        count++;
      }
    }
    return count;
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
        this.items[i].addedAt, this.items[i].pending));
    }
    return snap;
  }

  /**
   * 添加（M6 兼容入口）：同一组目标分组应用到所有 code。
   * 目标分组会被 `resolveGroupMembership` 补上派生的系统组，保证 INV-1。
   */
  async add(codes: string[], groups: string[]): Promise<WatchlistAddOutcome> {
    const inputs: WatchAddInput[] = [];
    for (let i = 0; i < codes.length; i++) {
      inputs.push(new WatchAddInput(codes[i], groups));
    }
    return this.addMany(inputs, false);
  }

  /**
   * 批量添加（M7-3）：逐项判定「新增 / 已存在 / 超上限」，部分成功不整批失败。
   * `pending=true` 表示离线加入，落盘后由同步服务清零（AC-96）。
   */
  async addMany(inputs: WatchAddInput[], pending: boolean): Promise<WatchlistAddOutcome> {
    await this.load();
    const outcome: WatchlistAddOutcome = new WatchlistAddOutcome();
    for (let i = 0; i < inputs.length; i++) {
      const code: string = inputs[i].code;
      if (code.length === 0) {
        continue;
      }
      if (this.indexOf(code) >= 0) {
        outcome.existed.push(code);
        continue;
      }
      if (this.items.length >= WATCHLIST_MAX_ITEMS) {
        outcome.rejectedLimit.push(code);
        continue;
      }
      const groups: string[] = resolveGroupMembership(code, inputs[i].groups);
      this.items.push(new WatchItem(code, groups, Date.now(), pending));
      outcome.added.push(code);
      if (pending) {
        outcome.pending.push(code);
      }
    }
    if (outcome.added.length > 0) {
      if (pending) {
        // 离线标记必须立即落盘：200ms 合并窗口内杀进程会丢掉「待同步」语义。
        await this.writeNow();
      } else {
        this.scheduleWrite();
      }
      this.notifyChange(outcome.added, [], false, 0);
    }
    return outcome;
  }

  /** 更新单只股票的分组归属（添加页「再次加入更多分组」/自选设置用）。 */
  async updateGroups(code: string, groups: string[]): Promise<boolean> {
    await this.load();
    const index: number = this.indexOf(code);
    if (index < 0) {
      return false;
    }
    const next: string[] = resolveGroupMembership(code, groups);
    if (WatchlistStore.sameGroups(this.items[index].groups, next)) {
      return true;
    }
    this.items[index].groups = next;
    this.scheduleWrite();
    this.notifyChange([], [], true, 0);
    return true;
  }

  /**
   * 移除（AC-97）：只删自选集合，不动分组定义；幂等（本地不存在记 missing）；
   * 同时返回快照，供 5s 撤销恢复原位置与原分组。
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
      const item: WatchItem = this.items[index];
      outcome.snapshots.push(new RemoveSnapshot(item.code, index, item.groups.slice(),
        item.addedAt, item.pending));
      this.items.splice(index, 1);
      outcome.removed.push(code);
    }
    if (outcome.removed.length > 0) {
      this.scheduleWrite();
      this.notifyChange([], outcome.removed, false, 0);
    }
    return outcome;
  }

  /**
   * 撤销移除（AC-97）：按快照的原始下标插回，已存在则跳过；不触发定位滚动。
   * 注意下标语义：`remove` 逐条删除时记录的是「删除当时」的下标，前面的删除已让后面元素前移，
   * 所以必须**按移除逆序**插回（最后删的先插），否则多只撤销会整体倒序。
   * 同时恢复受 50 上限约束（否则先移出再在别处加满，撤销可把自选顶到 50 以上并落盘）。
   */
  async restore(snapshots: RemoveSnapshot[]): Promise<number> {
    await this.load();
    let restored: number = 0;
    for (let i = snapshots.length - 1; i >= 0; i--) {
      const snap: RemoveSnapshot = snapshots[i];
      if (snap.code.length === 0 || this.indexOf(snap.code) >= 0) {
        continue;
      }
      if (this.items.length >= WATCHLIST_MAX_ITEMS) {
        hilog.warn(DOMAIN, TAG, 'restore_dropped_limit code=%{public}s', snap.code);
        continue;
      }
      const at: number = Math.min(Math.max(0, snap.index), this.items.length);
      this.items.splice(at, 0, new WatchItem(snap.code, snap.groups.slice(), snap.addedAt, snap.pending));
      restored++;
    }
    if (restored > 0) {
      await this.writeNow();
      this.notifyChange([], [], true, 0);
    }
    return restored;
  }

  /** 新建用户组（M7-6）：≤7、非空、≤8 字、禁 emoji、不重名。 */
  async createGroup(rawName: string): Promise<WatchlistGroupOutcome> {
    await this.load();
    const outcome: WatchlistGroupOutcome = new WatchlistGroupOutcome();
    if (countUserGroups(this.groups) >= WATCHLIST_MAX_USER_GROUPS) {
      outcome.reason = 'limit';
      return outcome;
    }
    const issue: GroupEditReason = validateGroupName(rawName, this.userGroupNames(''), '');
    if (issue !== 'ok') {
      outcome.reason = issue;
      return outcome;
    }
    const id: string = this.nextGroupId();
    this.groups.push(new WatchGroup(id, 'user', this.nextGroupOrder(), normalizeGroupName(rawName)));
    outcome.groupId = id;
    this.scheduleWrite();
    this.notifyChange([], [], true, 0);
    return outcome;
  }

  /** 重命名用户组：系统组 / 「全部」只读（CC-2.1）。 */
  async renameGroup(id: string, rawName: string): Promise<WatchlistGroupOutcome> {
    await this.load();
    const outcome: WatchlistGroupOutcome = new WatchlistGroupOutcome();
    outcome.groupId = id;
    const index: number = this.groupIndexOf(id);
    if (index < 0) {
      outcome.reason = 'not_found';
      return outcome;
    }
    if (this.groups[index].type !== 'user') {
      outcome.reason = 'system_readonly';
      return outcome;
    }
    // 按 id 排除自身（不能用名字排除：磁盘里若存在同名组，按名字排除会漏判重名）。
    const issue: GroupEditReason = validateGroupName(rawName, this.userGroupNames(id), '');
    if (issue !== 'ok') {
      outcome.reason = issue;
      return outcome;
    }
    this.groups[index].name = normalizeGroupName(rawName);
    this.scheduleWrite();
    this.notifyChange([], [], true, 0);
    return outcome;
  }

  /**
   * 删除用户组（M7-6）：只删归属不删股票；失去全部非「全部」分组的股票回落到派生的系统组，
   * 保证 INV-1（不允许无组股票）。
   */
  async deleteGroup(id: string): Promise<WatchlistGroupOutcome> {
    await this.load();
    const outcome: WatchlistGroupOutcome = new WatchlistGroupOutcome();
    outcome.groupId = id;
    const index: number = this.groupIndexOf(id);
    if (index < 0) {
      outcome.reason = 'not_found';
      return outcome;
    }
    if (this.groups[index].type !== 'user') {
      outcome.reason = 'system_readonly';
      return outcome;
    }
    this.groups.splice(index, 1);
    for (let i = 0; i < this.items.length; i++) {
      const item: WatchItem = this.items[i];
      const at: number = item.groups.indexOf(id);
      if (at < 0) {
        continue;
      }
      item.groups.splice(at, 1);
      if (!WatchlistStore.hasMembership(item.groups)) {
        const fallback: string[] = systemGroupsOf(item.code);
        for (let j = 0; j < fallback.length; j++) {
          item.groups.push(fallback[j]);
        }
        outcome.reassigned.push(item.code);
      }
    }
    this.scheduleWrite();
    this.notifyChange([], [], true, 0);
    hilog.info(DOMAIN, TAG, 'group_delete id=%{public}s reassigned=%{public}d',
      id, outcome.reassigned.length);
    return outcome;
  }

  /** 分组顺序（M7-1 预留：本期无拖拽 UI，仅提供稳定写入口）；重复 id 只取第一次。 */
  async setGroupOrder(ids: string[]): Promise<void> {
    await this.load();
    const ordered: WatchGroup[] = [];
    const seen: string[] = [];
    for (let i = 0; i < ids.length; i++) {
      const id: string = ids[i];
      if (seen.indexOf(id) >= 0) {
        continue;
      }
      const index: number = this.groupIndexOf(id);
      if (index >= 0) {
        seen.push(id);
        ordered.push(this.groups[index]);
      }
    }
    for (let i = 0; i < this.groups.length; i++) {
      if (ordered.indexOf(this.groups[i]) < 0) {
        ordered.push(this.groups[i]);
      }
    }
    for (let i = 0; i < ordered.length; i++) {
      ordered[i].order = i;
    }
    this.groups = ordered;
    this.scheduleWrite();
    this.notifyChange([], [], true, 0);
  }

  /** 联网后一次性清掉待同步标记（§5.5 规则 4）：失败保留标记，下次再试。 */
  async syncPending(): Promise<number> {
    await this.load();
    let synced: number = 0;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].pending) {
        this.items[i].pending = false;
        synced++;
      }
    }
    if (synced > 0) {
      await this.writeNow();
      this.notifyChange([], [], false, synced);
      hilog.info(DOMAIN, TAG, 'pending_synced n=%{public}d', synced);
    }
    return synced;
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
    this.notifyChange([], removed, false, 0);
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
    this.notifyChange([], [], true, 0);
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

  private groupIndexOf(id: string): number {
    for (let i = 0; i < this.groups.length; i++) {
      if (this.groups[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  /** 其它用户组名（重名判定用，excludeId 排除自身）。 */
  private userGroupNames(excludeId: string): string[] {
    const names: string[] = [];
    for (let i = 0; i < this.groups.length; i++) {
      const group: WatchGroup = this.groups[i];
      if (group.type !== 'user' || group.id === excludeId || group.name.length === 0) {
        continue;
      }
      names.push(group.name);
    }
    return names;
  }

  /** 新用户组 id：`ug<N>`，取现有最大序号 +1，避免与系统 id 冲突且重启稳定。 */
  private nextGroupId(): string {
    let max: number = 0;
    for (let i = 0; i < this.groups.length; i++) {
      const id: string = this.groups[i].id;
      if (!id.startsWith('ug')) {
        continue;
      }
      const seq: number = Number(id.substring(2));
      if (!isNaN(seq) && seq > max) {
        max = seq;
      }
    }
    return `ug${max + 1}`;
  }

  private nextGroupOrder(): number {
    let max: number = -1;
    for (let i = 0; i < this.groups.length; i++) {
      if (this.groups[i].order > max) {
        max = this.groups[i].order;
      }
    }
    return max + 1;
  }

  private static hasMembership(groups: string[]): boolean {
    for (let i = 0; i < groups.length; i++) {
      if (groups[i] !== WATCHLIST_ALL_GROUP) {
        return true;
      }
    }
    return false;
  }

  private static sameGroups(a: string[], b: string[]): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }

  private notifyChange(added: string[], removed: string[], groupsChanged: boolean,
    pendingSynced: number): void {
    const change: WatchlistChange = new WatchlistChange();
    change.added = added;
    change.removed = removed;
    change.groupsChanged = groupsChanged;
    change.pendingSynced = pendingSynced;
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

  /** 清空/重置/撤销/同步要「立刻可见地持久化」：不等 200ms 合并，直接写盘并把迁移标记置真。 */
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
        pending: store.items[i].pending
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
        item.addedAt !== undefined ? item.addedAt : 0,
        item.pending !== undefined ? item.pending : false));
    }
    return items;
  }
}
