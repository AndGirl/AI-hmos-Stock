import { ConnectionState, MockFaults, QuotePatch, QuoteSink, QuoteSnapshot, SinkSubscription, WatchItem } from 'commons_data';
import { compareRows, nextSortDir, SortDir, SortKey } from '../repository/SortRules';
import { computeTableMetrics, TableMetrics } from '../repository/TableMetrics';
import { WatchlistData, WatchlistRepository } from '../repository/WatchlistRepository';
import { DIR_DOWN, DIR_FLAT, DIR_UP, WatchRowVM } from './WatchRowVM';

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

/** 指数条单项。 */
@ObservedV2
export class IndexItemVM {
  code: string = '';
  @Trace name: string = '';
  @Trace pctText: string = '--';
  @Trace dir: number = DIR_FLAT;

  constructor(code: string) {
    this.code = code;
  }

  update(name: string, pct: number | null): void {
    this.name = name;
    this.pctText = pct === null ? '--' : `${pct > 0 ? '+' : ''}${pct.toFixed(2)}%`;
    this.dir = pct === null ? DIR_FLAT : (pct > 0 ? DIR_UP : (pct < 0 ? DIR_DOWN : DIR_FLAT));
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
  @Trace indexItems: IndexItemVM[] = [];
  @Trace selectedGroupId: string = 'all';
  @Trace sortKey: SortKey | null = null;
  @Trace sortDir: SortDir = 'none';
  @Trace metrics: TableMetrics = computeTableMetrics(360, 1);
  @Trace hOffset: number = 0;
  @Trace vOffset: number = 0;
  @Trace rowCount: number = 0;

  private repo: WatchlistRepository = new WatchlistRepository();
  private allRows: WatchRowVM[] = [];
  private rowByCode: Map<string, WatchRowVM> = new Map<string, WatchRowVM>();
  private indexByCode: Map<string, IndexItemVM> = new Map<string, IndexItemVM>();
  private indexSet: Map<string, string[]> = new Map<string, string[]>();
  private indexSnapshots: Map<string, QuoteSnapshot> = new Map<string, QuoteSnapshot>();
  private sub: SinkSubscription | undefined = undefined;
  private viewport: number = 360;
  private fontScale: number = 1;
  private indexCount: number = 3;
  private loading: boolean = false;
  private loaded: boolean = false;
  private frozen: boolean = false;

  updateLayout(viewport: number, fontScale: number, indexCount: number): void {
    const width: number = Math.max(0, Math.round(viewport));
    let changed: boolean = false;
    if (width !== this.viewport) {
      this.viewport = width;
      this.metrics = computeTableMetrics(this.viewport, this.fontScale);
      changed = true;
    }
    if (fontScale !== this.fontScale) {
      this.fontScale = fontScale;
      this.metrics = computeTableMetrics(this.viewport, this.fontScale);
      changed = true;
    }
    if (indexCount !== this.indexCount) {
      this.indexCount = indexCount;
      changed = true;
    }
    if (changed) {
      this.rebuildIndex();
    }
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
    this.rebuildIndex();
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

  private applyData(data: WatchlistData): void {
    const previousRows: Map<string, WatchRowVM> = this.rowByCode;
    this.allRows = [];
    this.rowByCode = new Map<string, WatchRowVM>();
    this.indexSnapshots = new Map<string, QuoteSnapshot>();
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
    data.quotes.forEach((snapshot: QuoteSnapshot): void => {
      if (!this.rowByCode.has(snapshot.code)) {
        this.indexSnapshots.set(snapshot.code, snapshot);
      }
    });
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
    this.indexSet = data.indexSet;
    this.updateGroupCounts();
    this.updateGroupSelection();
    this.rebuild();
    this.rebuildIndex();
  }

  private subscribe(): void {
    this.dispose();
    const codes: string[] = [];
    for (let i = 0; i < this.allRows.length; i++) {
      codes.push(this.allRows[i].code);
    }
    this.indexSet.forEach((list: string[]): void => {
      for (let i = 0; i < list.length; i++) {
        if (codes.indexOf(list[i]) < 0) {
          codes.push(list[i]);
        }
      }
    });
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
    if (row !== undefined) {
      if (!this.frozen) {
        row.applyPatch(patch);
      }
      return;
    }
    const index: IndexItemVM | undefined = this.indexByCode.get(patch.code);
    if (index !== undefined && patch.pct !== undefined) {
      index.update(index.name, patch.pct);
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
  }

  private rebuildIndex(): void {
    const codes: string[] = this.indexSet.get(this.selectedGroupId) ?? [];
    const previous: Map<string, IndexItemVM> = this.indexByCode;
    const items: IndexItemVM[] = [];
    this.indexByCode = new Map<string, IndexItemVM>();
    const limit: number = Math.min(this.indexCount, codes.length);
    for (let i = 0; i < limit; i++) {
      const reused: IndexItemVM | undefined = previous.get(codes[i]);
      const item: IndexItemVM = reused !== undefined ? reused : new IndexItemVM(codes[i]);
      const snapshot: QuoteSnapshot | undefined = this.indexSnapshots.get(codes[i]);
      if (snapshot !== undefined) {
        item.update(snapshot.name, snapshot.pct);
      }
      items.push(item);
      this.indexByCode.set(codes[i], item);
    }
    this.indexItems = items;
  }
}

/** View 组件的度量默认值（避免组件直接依赖 repository，R-07）。 */
export function emptyMetrics(): TableMetrics {
  return computeTableMetrics(360, 1);
}

export { SortDir, SortKey } from '../repository/SortRules';
export { TableMetrics, NUMERIC_SORT_KEYS } from '../repository/TableMetrics';
