import {
  DataServices,
  WATCHLIST_ALL_GROUP,
  WATCHLIST_MAX_ITEMS,
  WatchAddInput,
  WatchGroup,
  WatchItem,
  WatchlistAddOutcome,
  WatchlistSnapshot,
  WatchlistStore
} from 'commons_data';
import { AnalyticsHost, AnalyticsHub, AnalyticsParam, ConnectionHost, ConnectionHub } from 'commons_basic';
import { SearchRowVM } from './SearchRowVM';
import { SearchVM } from './SearchVM';

/** 提交结论：'none' 未选、'partial' 有超限项、'failed' 异常、'ok' 全部处理完。 */
export type AddSubmitReason = 'ok' | 'none' | 'partial' | 'failed';

/** 一次批量提交的结果（M7-3：逐项成功/已存在/超限/待同步）。 */
export class AddSubmitResult {
  reason: AddSubmitReason = 'ok';
  added: number = 0;
  existed: number = 0;
  limit: number = 0;
  pending: number = 0;
  /** 全部处理完（可关闭添加页）；有超限项时为 false，停留页内可重试。 */
  done: boolean = false;
}

/** 目标分组 chip（M7-2）：系统组用 id 映射文案，用户组直接显示 name。 */
@ObservedV2
export class AddGroupVM {
  id: string = '';
  @Trace name: string = '';
  @Trace system: boolean = false;
  @Trace count: number = 0;
  @Trace selected: boolean = false;

  constructor(id: string, name: string, system: boolean) {
    this.id = id;
    this.name = name;
    this.system = system;
  }
}

/**
 * 添加自选 VM（M7-2/M7-3）：
 * - 复用 `SearchVM` 的输入/防抖/六态/浏览列表，只叠加「勾选 + 目标分组 + 批量提交」；
 * - 提交走 `WatchlistStore.addMany`，由 Store 判定重复/上限/待同步（部分成功不整批失败）；
 * - 不出现 UI 副作用（不弹窗、不路由），中文在 View 侧（§5.6 红线）。
 */
@ObservedV2
export class AddWatchlistVM {
  /** 自选当前总数（页头 N/50）。 */
  @Trace count: number = 0;
  @Trace pickedCount: number = 0;
  @Trace groups: AddGroupVM[] = [];
  @Trace submitting: boolean = false;
  @Trace offline: boolean = false;
  @Trace limitReached: boolean = false;
  /** 详情入口带进来的预置标的（"已在自选"直接展示）。 */
  @Trace presetCode: string = '';
  @Trace presetName: string = '';
  @Trace presetAdded: boolean = false;
  @Trace presetGroups: string[] = [];
  /** 预置标的所属分组数（不含「全部」虚拟组，与新增股票口径一致）。 */
  @Trace presetGroupCount: number = 0;
  /** 容量上限（View 不直接 import commons_data，由 VM 转出）。 */
  readonly maxItems: number = WATCHLIST_MAX_ITEMS;
  search: SearchVM = new SearchVM();

  private store: WatchlistStore = DataServices.watchlistStore();
  private hub: ConnectionHub = ConnectionHost.getService();
  private analytics: AnalyticsHub = AnalyticsHost.get();
  private pickedCodes: string[] = [];
  /** 入口来源（埋点维度，来自 AddWatchlistParam.from）。 */
  private fromSource: string = '';

  /** 页面出现时调用：初始化搜索面、读到分组与容量、预置详情带来的 code。 */
  async init(currentGroupId: string, presetCode: string, from: string = ''): Promise<void> {
    this.search.init();
    this.fromSource = from;
    this.presetCode = presetCode.trim();
    if (this.presetCode.length > 0) {
      // 预置 code 不写搜索历史（用户没搜过）
      this.search.presetQuery(this.presetCode);
    }
    await this.refresh();
    if (currentGroupId.length > 0 && currentGroupId !== WATCHLIST_ALL_GROUP) {
      this.setGroupSelected(currentGroupId, true);
    }
  }

  /** 重读 Store：分组 chip（含只数）、容量、预置标的归属、离线态。 */
  async refresh(): Promise<void> {
    const snap: WatchlistSnapshot = await this.store.snapshot();
    this.count = snap.items.length;
    this.limitReached = snap.items.length >= WATCHLIST_MAX_ITEMS;
    this.offline = this.hub.isOffline();
    const next: AddGroupVM[] = [];
    for (let i = 0; i < snap.groups.length; i++) {
      const group: WatchGroup = snap.groups[i];
      if (group.type === 'all') {
        continue;
      }
      const vm: AddGroupVM = new AddGroupVM(group.id, group.name, group.type === 'system');
      vm.count = AddWatchlistVM.countItems(snap.items, group.id);
      vm.selected = this.isGroupSelected(group.id);
      next.push(vm);
    }
    this.groups = next;
    if (this.presetCode.length > 0) {
      let found: boolean = false;
      for (let i = 0; i < snap.items.length; i++) {
        if (snap.items[i].code === this.presetCode) {
          found = true;
          this.presetGroups = snap.items[i].groups.slice();
          break;
        }
      }
      if (!found) {
        this.presetGroups = [];
      }
      this.presetAdded = found;
      this.presetGroupCount = AddWatchlistVM.countRealGroups(this.presetGroups);
      this.refreshPresetName();
    }
  }

  toggleGroup(id: string): void {
    this.setGroupSelected(id, !this.isGroupSelected(id));
  }

  isGroupSelected(id: string): boolean {
    for (let i = 0; i < this.groups.length; i++) {
      if (this.groups[i].id === id) {
        return this.groups[i].selected;
      }
    }
    return false;
  }

  /** 勾选/取消勾选一行（AC-95）：已添加行不可复选；同一 code 在两处列表同步。 */
  togglePick(row: SearchRowVM): void {
    if (row.kind !== 'stock' || row.added || row.pending) {
      return;
    }
    const at: number = this.pickedCodes.indexOf(row.code);
    const on: boolean = at < 0;
    if (on) {
      this.pickedCodes.push(row.code);
    } else {
      this.pickedCodes.splice(at, 1);
    }
    this.applyPicked(row.code, on);
    this.pickedCount = this.pickedCodes.length;
  }

  /** 结果集重建后把勾选态刷回新行对象（SearchVM.resultVersion 触发）。 */
  reapplyPicks(): void {
    for (let i = 0; i < this.search.sections.length; i++) {
      const rows: SearchRowVM[] = this.search.sections[i].rows;
      for (let j = 0; j < rows.length; j++) {
        if (rows[j].kind === 'stock') {
          rows[j].markPicked(this.pickedCodes.indexOf(rows[j].code) >= 0);
        }
      }
    }
    for (let i = 0; i < this.search.browseRows.length; i++) {
      const row: SearchRowVM = this.search.browseRows[i];
      if (row.kind === 'stock') {
        row.markPicked(this.pickedCodes.indexOf(row.code) >= 0);
      }
    }
    this.refreshPresetName();
  }

  /**
   * 批量加入（AC-95/96）：目标分组为空时由 Store 按板块派生；离线加入标待同步。
   * 成功（含已存在）的项从勾选中摘掉并标「已添加」；超限项保留可重试。
   */
  async submit(): Promise<AddSubmitResult> {
    const result: AddSubmitResult = new AddSubmitResult();
    if (this.submitting || this.pickedCodes.length === 0) {
      result.reason = 'none';
      return result;
    }
    this.submitting = true;
    try {
      const targets: string[] = this.selectedTargets();
      const inputs: WatchAddInput[] = [];
      for (let i = 0; i < this.pickedCodes.length; i++) {
        inputs.push(new WatchAddInput(this.pickedCodes[i], targets));
      }
      const pending: boolean = this.hub.isOffline();
      const outcome: WatchlistAddOutcome = await this.store.addMany(inputs, pending);
      result.added = outcome.added.length;
      result.existed = outcome.existed.length;
      result.limit = outcome.rejectedLimit.length;
      result.pending = outcome.pending.length;
      const settled: string[] = outcome.added.concat(outcome.existed);
      this.removePicks(settled);
      this.markAdded(settled);
      await this.refresh();
      result.done = outcome.added.length > 0 && outcome.rejectedLimit.length === 0;
      result.reason = result.limit > 0 ? 'partial' : 'ok';
      this.track(result);
    } catch (err) {
      result.reason = 'failed';
    } finally {
      this.submitting = false;
    }
    return result;
  }

  /** 详情入口「已在自选」：把当前勾选的目标分组并进该标的（多归属叠加）。 */
  async updatePresetGroups(): Promise<boolean> {
    if (this.presetCode.length === 0) {
      return false;
    }
    const merged: string[] = this.presetGroups.slice();
    const targets: string[] = this.selectedTargets();
    for (let i = 0; i < targets.length; i++) {
      if (merged.indexOf(targets[i]) < 0) {
        merged.push(targets[i]);
      }
    }
    const ok: boolean = await this.store.updateGroups(this.presetCode, merged);
    await this.refresh();
    return ok;
  }

  dispose(): void {
    this.search.dispose();
    this.pickedCodes = [];
    this.pickedCount = 0;
  }

  private setGroupSelected(id: string, on: boolean): void {
    for (let i = 0; i < this.groups.length; i++) {
      if (this.groups[i].id === id) {
        this.groups[i].selected = on;
        return;
      }
    }
  }

  private selectedTargets(): string[] {
    const targets: string[] = [];
    for (let i = 0; i < this.groups.length; i++) {
      if (this.groups[i].selected) {
        targets.push(this.groups[i].id);
      }
    }
    return targets;
  }

  private applyPicked(code: string, on: boolean): void {
    for (let i = 0; i < this.search.sections.length; i++) {
      const rows: SearchRowVM[] = this.search.sections[i].rows;
      for (let j = 0; j < rows.length; j++) {
        if (rows[j].code === code && rows[j].kind === 'stock') {
          rows[j].markPicked(on);
        }
      }
    }
    for (let i = 0; i < this.search.browseRows.length; i++) {
      const row: SearchRowVM = this.search.browseRows[i];
      if (row.code === code && row.kind === 'stock') {
        row.markPicked(on);
      }
    }
  }

  private removePicks(codes: string[]): void {
    for (let i = 0; i < codes.length; i++) {
      const at: number = this.pickedCodes.indexOf(codes[i]);
      if (at >= 0) {
        this.pickedCodes.splice(at, 1);
      }
      this.applyPicked(codes[i], false);
    }
    this.pickedCount = this.pickedCodes.length;
  }

  private markAdded(codes: string[]): void {
    if (codes.length === 0) {
      return;
    }
    for (let i = 0; i < this.search.sections.length; i++) {
      const rows: SearchRowVM[] = this.search.sections[i].rows;
      for (let j = 0; j < rows.length; j++) {
        if (rows[j].kind === 'stock' && codes.indexOf(rows[j].code) >= 0) {
          rows[j].markAdded();
        }
      }
    }
    for (let i = 0; i < this.search.browseRows.length; i++) {
      const row: SearchRowVM = this.search.browseRows[i];
      if (row.kind === 'stock' && codes.indexOf(row.code) >= 0) {
        row.markAdded();
      }
    }
  }

  /** 预置标的名称从搜索结果行取（Store 只存 code）；取不到就只显示 code。 */
  private refreshPresetName(): void {
    if (this.presetCode.length === 0) {
      return;
    }
    for (let i = 0; i < this.search.sections.length; i++) {
      const rows: SearchRowVM[] = this.search.sections[i].rows;
      for (let j = 0; j < rows.length; j++) {
        if (rows[j].code === this.presetCode) {
          this.presetName = rows[j].name;
          return;
        }
      }
    }
    for (let i = 0; i < this.search.browseRows.length; i++) {
      if (this.search.browseRows[i].code === this.presetCode) {
        this.presetName = this.search.browseRows[i].name;
        return;
      }
    }
  }

  private track(result: AddSubmitResult): void {
    this.analytics.track('watch_add_batch', [
      new AnalyticsParam('added', `${result.added}`),
      new AnalyticsParam('existed', `${result.existed}`),
      new AnalyticsParam('limit', `${result.limit}`),
      new AnalyticsParam('pending', `${result.pending}`),
      new AnalyticsParam('groups', `${this.selectedTargets().length}`),
      new AnalyticsParam('from', this.fromSource)
    ]);
    this.analytics.flush();
  }

  private static countRealGroups(groups: string[]): number {
    let count: number = 0;
    for (let i = 0; i < groups.length; i++) {
      if (groups[i] !== WATCHLIST_ALL_GROUP) {
        count++;
      }
    }
    return count;
  }

  private static countItems(items: WatchItem[], groupId: string): number {
    let count: number = 0;
    for (let i = 0; i < items.length; i++) {
      if (items[i].groups.indexOf(groupId) >= 0) {
        count++;
      }
    }
    return count;
  }
}
