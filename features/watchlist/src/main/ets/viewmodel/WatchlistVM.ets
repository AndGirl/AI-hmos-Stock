import {
  ConnectionState,
  DataServices,
  MockFaults,
  NetFault,
  QuotePatch,
  QuoteSink,
  QuoteSnapshot,
  SinkSubscription,
  WatchItem,
  WatchlistChange,
  WatchlistChangeListener,
  WatchlistStore
} from 'commons_data';
import { ConnectionHost, ConnectionHub } from 'commons_basic';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { compareRows, nextSortDir, SortDir, SortKey } from '../repository/SortRules';
import { computeTableMetrics, TableMetrics } from '../repository/TableMetrics';
import { WatchlistData, WatchlistRepository } from '../repository/WatchlistRepository';
import { IndexBarDataSource } from './IndexBarDataSource';
import { WatchRowVM } from './WatchRowVM';

export type WatchPageState = 'loading' | 'content' | 'empty' | 'error';

/**
 * 空态范围（M6 追加）：
 * 'all' 自选一只都没有（引导式空态，隐藏指数条/分组页签）；
 * 'group' 当前分组为空但其它分组有票（「该分组暂无股票」+ 查看全部）；
 * 'none' 非空态。
 */
export type WatchEmptyKind = 'none' | 'all' | 'group';

/** 分组 Tab：文案由 View 按 id 走 i18n。 */
@ObservedV2
export class GroupTabVM {
  id: string = '';
  @Trace count: number = 0;
  @Trace selected: boolean = false;

  constructor(id: string) {
    this.id = id;
  }
}

/** VM 侧 sink：把 bus 回调转成 VM 内部方法，避免未声明类型的对象字面量。 */
class VmSink implements QuoteSink {
  private patchHandler: (patch: QuotePatch) => void;
  private statusHandler: (state: ConnectionState) => void;

  constructor(patchHandler: (patch: QuotePatch) => void, statusHandler: (state: ConnectionState) => void) {
    this.patchHandler = patchHandler;
    this.statusHandler = statusHandler;
  }

  onPatch(patch: QuotePatch): void {
    this.patchHandler(patch);
  }

  onStatus(state: ConnectionState): void {
    this.statusHandler(state);
  }
}

/**
 * 自选列表 VM（L3）：状态、分组、排序、布局度量、订阅生命周期。
 * 推送只改行对象（@Trace），不重建数组；排序为「快照序」，切组/点列头时才重排，避免行跳动。
 */
@ObservedV2
export class WatchlistVM {
  @Trace state: WatchPageState = 'loading';
  /** 空态范围：区分「自选全空」与「当前分组为空」，两者文案与结构不同。 */
  @Trace emptyKind: WatchEmptyKind = 'none';
  @Trace rows: WatchRowVM[] = [];
  @Trace groups: GroupTabVM[] = [];
  @Trace selectedGroupId: string = 'all';
  @Trace sortKey: SortKey | null = null;
  @Trace sortDir: SortDir = 'none';
  @Trace metrics: TableMetrics = computeTableMetrics(360, 1);
  @Trace hOffset: number = 0;
  @Trace vOffset: number = 0;
  @Trace rowCount: number = 0;
  /** 指数条数据版本：集合/顺序/布局变化时 +1，视图侧据此把横向 List 复位到首项。 */
  @Trace stripVersion: number = 0;
  /** 多选比价（FR-08.1 第三入口）：长按进入，2–3 只，顺序即 PK 窗序。 */
  @Trace selectMode: boolean = false;
  @Trace selectedCodes: string[] = [];
  /** 新增行定位（M7-4 提前）：自选页据此 scrollToIndex 并高亮新行。 */
  @Trace scrollIndex: number = -1;
  @Trace scrollSeq: number = 0;

  private repo: WatchlistRepository = new WatchlistRepository();
  private store: WatchlistStore = DataServices.watchlistStore();
  private storeListener: WatchlistChangeListener = (change: WatchlistChange): void => {
    this.onStoreChanged(change);
  };
  private storeAttached: boolean = false;
  private syncing: boolean = false;
  private pendingFocus: string = '';
  private allRows: WatchRowVM[] = [];
  private rowByCode: Map<string, WatchRowVM> = new Map<string, WatchRowVM>();
  private indexBar: IndexBarDataSource = new IndexBarDataSource();
  private sub: SinkSubscription | undefined = undefined;
  private viewport: number = 360;
  private fontScale: number = 1;
  private loading: boolean = false;
  private loaded: boolean = false;
  private frozen: boolean = false;
  /** 加载令牌：页面在 await 期间销毁时，回执不得再建订阅。 */
  private loadToken: number = 0;

  /** 指数条数据源：与 rows 同序、同集合（逐股票）。 */
  indexBarSource(): IndexBarDataSource {
    return this.indexBar;
  }

  updateLayout(viewport: number, fontScale: number): void {
    const width: number = Math.max(0, Math.round(viewport));
    if (width === this.viewport && fontScale === this.fontScale) {
      return;
    }
    this.viewport = width;
    this.fontScale = fontScale;
    this.metrics = computeTableMetrics(this.viewport, this.fontScale);
    this.stripVersion++;
  }

  async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.state = 'loading';
    this.dispose();
    const token: number = this.loadToken;
    try {
      const data: WatchlistData = await this.repo.load();
      if (token !== this.loadToken) {
        return;
      }
      this.applyData(data);
      this.loaded = true;
      this.subscribe();
      this.attachStore();
    } catch (err) {
      if (token !== this.loadToken) {
        return;
      }
      this.state = 'error';
    } finally {
      this.loading = false;
    }
  }

  retry(): void {
    if (this.state === 'loading') {
      return;
    }
    this.load();
  }

  /** 调试面板用：强制重新加载（空态/失败态/恢复数据）。 */
  reload(): void {
    if (this.state === 'loading') {
      return;
    }
    this.load();
  }

  /**
   * 调试面板用：注入「自选加载失败」。
   * 放在 VM 是为了让 view 不直接依赖 commons_data（R-07）。
   */
  applyMockFault(fail: boolean): void {
    MockFaults.failWatchlist = fail;
    this.reload();
  }

  /**
   * 调试面板用：**真实清空**自选数据（2026-11-13 需求变更）。
   * 不只做展示层置空：Store 立即落盘，杀进程/重启后仍为空；分组定义保留。
   */
  async clearAll(): Promise<void> {
    const removed: number = await this.store.clear();
    hilog.info(0x0001, 'WatchLog', 'clear_all removed=%{public}d', removed);
    if (this.loaded) {
      this.syncFromStore('');
    }
  }

  /** 调试面板用：「重置」把自选恢复为 45 只 Mock 种子并落盘。 */
  async resetAll(): Promise<void> {
    MockFaults.failWatchlist = false;
    await this.store.resetToSeeds();
    hilog.info(0x0001, 'WatchLog', 'reset_seeds');
    if (!this.loaded) {
      // 「模拟加载失败」后 loaded=false：重置必须重新走一次正常加载，否则停在错误态。
      await this.load();
      return;
    }
    this.syncFromStore('');
  }

  /**
   * 调试面板用：注入网络故障（M5-1）。写 MockFaults 后立刻把 ConnectionHub 打到目标态，
   * 不必等下一个心跳；恢复用 reset()，避免退避计时器残留。
   */
  applyNetFault(fault: NetFault): void {
    MockFaults.netFault = fault;
    const hub: ConnectionHub = ConnectionHost.getService();
    if (fault === 'none') {
      hub.reset();
    } else if (fault === 'offline') {
      hub.force('offline');
    } else {
      hub.force(fault);
    }
    hilog.info(0x0001, 'ConnLog', 'net_fault=%{public}s state=%{public}s', fault, hub.state);
  }

  /**
   * Tab 重新可见（或页面恢复）时调用：
   * 重订阅行情 + 补订阅 Store + 重读一次 Store（覆盖隐藏期间的变更）。
   */
  resume(): void {
    if (!this.loaded) {
      return;
    }
    this.subscribe();
    this.attachStore();
    this.syncFromStore('');
  }

  dispose(): void {
    this.loadToken++;
    this.disposeQuotes();
    this.detachStore();
  }

  selectGroup(id: string): void {
    if (id === this.selectedGroupId) {
      return;
    }
    this.selectedGroupId = id;
    this.updateGroupSelection();
    this.rebuild();
    // 横滑/竖向偏移保留（设计 §5.2.5：切分组、进详情返回后恢复原位置）。
  }

  cycleSort(key: SortKey): void {
    if (this.sortKey === key) {
      this.sortDir = nextSortDir(this.sortDir);
    } else {
      this.sortKey = key;
      this.sortDir = 'desc';
    }
    if (this.sortDir === 'none') {
      this.sortKey = null;
    }
    this.rebuild();
  }

  onVerticalOffset(offset: number): void {
    this.vOffset = offset;
  }

  onHorizontalOffset(offset: number): void {
    this.hOffset = offset;
  }

  /** 多选上限（FR-08.3：PK 最多 3 窗）。 */
  static readonly MAX_SELECT: number = 3;

  isSelected(code: string): boolean {
    return this.selectedCodes.indexOf(code) >= 0;
  }

  /** 长按行进入多选并选中该行；已选满则不入多选（返回 false 由视图提示）。 */
  enterSelect(code: string): boolean {
    if (this.selectMode) {
      return this.toggleSelect(code);
    }
    this.selectMode = true;
    this.selectedCodes = [code];
    hilog.info(0x0001, 'PkLog', 'watch_select_enter code=%{public}s', code);
    return true;
  }

  /** 点行切换选中：int 为 false 表示已达 3 只上限（视图提示「最多选 3 只」）。 */
  toggleSelect(code: string): boolean {
    const index: number = this.selectedCodes.indexOf(code);
    if (index >= 0) {
      this.selectedCodes.splice(index, 1);
      hilog.info(0x0001, 'PkLog', 'watch_select_toggle code=%{public}s on=false n=%{public}d',
        code, this.selectedCodes.length);
      return true;
    }
    if (this.selectedCodes.length >= WatchlistVM.MAX_SELECT) {
      return false;
    }
    this.selectedCodes.push(code);
    hilog.info(0x0001, 'PkLog', 'watch_select_toggle code=%{public}s on=true n=%{public}d',
      code, this.selectedCodes.length);
    return true;
  }

  cancelSelect(): void {
    this.selectMode = false;
    this.selectedCodes = [];
    hilog.info(0x0001, 'PkLog', 'watch_select_cancel');
  }

  /** 确认比价：少于 2 只不进 PK（返回 null，由视图提示「至少选择 2 只」）。 */
  confirmSelect(): string[] | null {
    if (this.selectedCodes.length < 2) {
      return null;
    }
    const codes: string[] = this.selectedCodes.slice(0, WatchlistVM.MAX_SELECT);
    hilog.info(0x0001, 'PkLog', 'watch_select_confirm n=%{public}d', codes.length);
    this.selectMode = false;
    this.selectedCodes = [];
    return codes;
  }

  private applyData(data: WatchlistData): void {
    const previousRows: Map<string, WatchRowVM> = this.rowByCode;
    this.allRows = [];
    this.rowByCode = new Map<string, WatchRowVM>();
    for (let i = 0; i < data.items.length; i++) {
      const item: WatchItem = data.items[i];
      // 复用已有行对象：ForEach 以 code 为 key，替换实例会让旧 key 的节点继续读旧对象（表现为数据不刷新）。
      const reused: WatchRowVM | undefined = previousRows.get(item.code);
      const row: WatchRowVM = reused !== undefined ? reused : new WatchRowVM(item.code, item.code, item.groups);
      row.groups = item.groups;
      const snapshot: QuoteSnapshot | undefined = data.quotes.get(item.code);
      if (snapshot !== undefined) {
        row.updateFromSnapshot(snapshot);
      }
      this.allRows.push(row);
      this.rowByCode.set(row.code, row);
    }
    const previousGroups: GroupTabVM[] = this.groups;
    this.groups = [];
    for (let i = 0; i < data.groups.length; i++) {
      const id: string = data.groups[i].id;
      let group: GroupTabVM | undefined = undefined;
      for (let j = 0; j < previousGroups.length; j++) {
        if (previousGroups[j].id === id) {
          group = previousGroups[j];
          break;
        }
      }
      this.groups.push(group !== undefined ? group : new GroupTabVM(id));
    }
    this.updateGroupCounts();
    this.updateGroupSelection();
    this.rebuild();
  }

  private subscribe(): void {
    // 只清理行情订阅：不能复用 dispose()，否则会连同 Store 监听一起摘掉（多只添加只同步第一只的根因）
    this.disposeQuotes();
    const codes: string[] = [];
    for (let i = 0; i < this.allRows.length; i++) {
      codes.push(this.allRows[i].code);
    }
    const sink: QuoteSink = new VmSink(
      (patch: QuotePatch): void => {
        this.onPatch(patch);
      },
      (state: ConnectionState): void => {
        // 连接态由 M5 的 ConnectionHub 统一驱动全局 banner，列表只冻结刷新。
        this.frozen = state === 'offline';
      }
    );
    this.sub = this.repo.subscribe(codes, sink);
  }

  /** 仅退订行情；页面级 dispose 才解绑 Store 监听。 */
  private disposeQuotes(): void {
    if (this.sub !== undefined) {
      this.sub.unsubscribe();
      this.sub = undefined;
    }
  }

  private onPatch(patch: QuotePatch): void {
    const row: WatchRowVM | undefined = this.rowByCode.get(patch.code);
    if (row !== undefined && !this.frozen) {
      row.applyPatch(patch);
    }
  }

  /** P0 数据同源：订阅 Store 变更，搜索页加自选 / 撤出自选后自选页即时刷新。 */
  private attachStore(): void {
    if (this.storeAttached) {
      return;
    }
    this.store.subscribe(this.storeListener);
    this.storeAttached = true;
  }

  private detachStore(): void {
    if (!this.storeAttached) {
      return;
    }
    this.store.unsubscribe(this.storeListener);
    this.storeAttached = false;
  }

  private onStoreChanged(change: WatchlistChange): void {
    if (!this.loaded) {
      return;
    }
    // 只有「新增」才定位高亮；删除后不滚动、不切分组（避免把用户从当前分组踢回全部）。
    const added: string[] = change.added;
    const focus: string = added.length > 0 ? added[added.length - 1] : '';
    this.syncFromStore(focus);
  }

  /**
   * 增量同步（不切骨架）：重读 Store 快照 → 复用旧行、补新行 → 重订阅 → 定位并高亮新行。
   * 等同 M7-4 的「乐观插入 + 滚动高亮」，此处 Store 为本地写，延迟可忽略。
   */
  private async syncFromStore(focusCode: string): Promise<void> {
    if (this.syncing) {
      this.pendingFocus = focusCode;
      return;
    }
    this.syncing = true;
    const token: number = this.loadToken;
    try {
      const data: WatchlistData = await this.repo.load();
      if (token !== this.loadToken || !this.loaded) {
        return;
      }
      this.applyData(data);
      this.subscribe();
      if (focusCode.length > 0) {
        this.focusRow(focusCode);
      }
    } catch (err) {
      // 同步失败保留旧列表，不打断阅读（下次变更/进入页面再试）
    } finally {
      this.syncing = false;
      const pending: string = this.pendingFocus;
      this.pendingFocus = '';
      if (pending.length > 0) {
        this.syncFromStore(pending);
      }
    }
  }

  /** 定位新行：当前分组看不到时回落到「全部」，最终滚动 + 一次 320ms 高亮。 */
  private focusRow(code: string): void {
    let index: number = -1;
    for (let i = 0; i < this.rows.length; i++) {
      if (this.rows[i].code === code) {
        index = i;
        break;
      }
    }
    if (index < 0) {
      if (this.selectedGroupId !== 'all') {
        this.selectedGroupId = 'all';
        this.updateGroupSelection();
        this.rebuild();
        this.focusRow(code);
      }
      return;
    }
    this.scrollIndex = index;
    this.scrollSeq++;
    this.rows[index].quote.flashSeq++;
  }

  private updateGroupCounts(): void {
    for (let i = 0; i < this.groups.length; i++) {
      const group: GroupTabVM = this.groups[i];
      if (group.id === 'all') {
        group.count = this.allRows.length;
        continue;
      }
      let count: number = 0;
      for (let j = 0; j < this.allRows.length; j++) {
        if (this.allRows[j].groups.indexOf(group.id) >= 0) {
          count++;
        }
      }
      group.count = count;
    }
  }

  private updateGroupSelection(): void {
    for (let i = 0; i < this.groups.length; i++) {
      this.groups[i].selected = this.groups[i].id === this.selectedGroupId;
    }
  }

  private rebuild(): void {
    const source: WatchRowVM[] = [];
    for (let i = 0; i < this.allRows.length; i++) {
      const row: WatchRowVM = this.allRows[i];
      if (this.selectedGroupId === 'all' || row.groups.indexOf(this.selectedGroupId) >= 0) {
        source.push(row);
      }
    }
    const key: SortKey | null = this.sortKey;
    const dir: SortDir = this.sortDir;
    if (key !== null && dir !== 'none') {
      source.sort((a: WatchRowVM, b: WatchRowVM): number => compareRows(a.quote, b.quote, key, dir));
    }
    this.rows = source;
    this.rowCount = source.length;
    this.state = source.length === 0 ? 'empty' : 'content';
    // 全空与分组空要分开：全空走引导式空态，分组空只提示换分组，不能误报「暂无自选」。
    this.emptyKind = source.length > 0 ? 'none' : (this.allRows.length === 0 ? 'all' : 'group');
    // 指数条与列表逐股票一一对应：集合与顺序都由 rows 驱动。
    this.indexBar.setItems(source);
    this.stripVersion++;
  }
}

/** View 组件的度量默认值（避免组件直接依赖 repository，R-07）。 */
export function emptyMetrics(): TableMetrics {
  return computeTableMetrics(360, 1);
}

export { SortDir, SortKey } from '../repository/SortRules';
export { TableMetrics, NUMERIC_SORT_KEYS } from '../repository/TableMetrics';
