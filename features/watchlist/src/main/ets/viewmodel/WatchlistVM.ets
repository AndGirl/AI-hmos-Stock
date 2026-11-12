import {
  ConnectionState,
  MockFaults,
  NetFault,
  QuotePatch,
  QuoteSink,
  QuoteSnapshot,
  SinkSubscription,
  WatchItem
} from 'commons_data';
import { ConnectionHost, ConnectionHub } from 'commons_basic';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { compareRows, nextSortDir, SortDir, SortKey } from '../repository/SortRules';
import { computeTableMetrics, TableMetrics } from '../repository/TableMetrics';
import { WatchlistData, WatchlistRepository } from '../repository/WatchlistRepository';
import { IndexBarDataSource } from './IndexBarDataSource';
import { WatchRowVM } from './WatchRowVM';

export type WatchPageState = 'loading' | 'content' | 'empty' | 'error';

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

  private repo: WatchlistRepository = new WatchlistRepository();
  private allRows: WatchRowVM[] = [];
  private rowByCode: Map<string, WatchRowVM> = new Map<string, WatchRowVM>();
  private indexBar: IndexBarDataSource = new IndexBarDataSource();
  private sub: SinkSubscription | undefined = undefined;
  private viewport: number = 360;
  private fontScale: number = 1;
  private loading: boolean = false;
  private loaded: boolean = false;
  private frozen: boolean = false;

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
    try {
      const data: WatchlistData = await this.repo.load();
      this.applyData(data);
      this.loaded = true;
      this.subscribe();
    } catch (err) {
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
   * 调试面板用：注入 Mock 故障（空自选 / 加载失败）。
   * 放在 VM 是为了让 view 不直接依赖 commons_data（R-07）。
   */
  applyMockFault(empty: boolean, fail: boolean): void {
    MockFaults.emptyWatchlist = empty;
    MockFaults.failWatchlist = fail;
    this.reload();
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

  resume(): void {
    if (this.loaded) {
      this.subscribe();
    }
  }

  dispose(): void {
    if (this.sub !== undefined) {
      this.sub.unsubscribe();
      this.sub = undefined;
    }
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
    this.dispose();
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

  private onPatch(patch: QuotePatch): void {
    const row: WatchRowVM | undefined = this.rowByCode.get(patch.code);
    if (row !== undefined && !this.frozen) {
      row.applyPatch(patch);
    }
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
