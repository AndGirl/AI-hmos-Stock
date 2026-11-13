import {
  ConnectionState,
  DataServices,
  GroupEditReason,
  MockFaults,
  NetFault,
  QuotePatch,
  QuoteSink,
  QuoteSnapshot,
  QuoteChannel,
  RemoveSnapshot,
  SearchProvider,
  SessionMode,
  SinkSubscription,
  StockBrowsePage,
  TradingSession,
  ViewPrefStore,
  WatchAddInput,
  WatchGroup,
  WatchItem,
  WatchlistAddOutcome,
  WatchlistChange,
  WatchlistChangeListener,
  WatchlistGroupOutcome,
  WatchlistRemoveOutcome,
  WatchlistStore
} from 'commons_data';
import { AnalyticsHost, AnalyticsHub, AnalyticsParam, ConfigHost, ConnectionHost, ConnectionHub } from 'commons_basic';
import { nextViewMode, ViewMode } from 'commons_basic';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { compareRows, nextSortDir, SortDir, SortKey } from '../repository/SortRules';
import { computeTableMetrics, TableMetrics } from '../repository/TableMetrics';
import { WatchlistData, WatchlistRepository } from '../repository/WatchlistRepository';
import { IndexBarDataSource } from './IndexBarDataSource';
import { CardVM } from './CardVM';
import { WatchRowVM } from './WatchRowVM';

export type WatchPageState = 'loading' | 'content' | 'empty' | 'error';

/** 采样导出用：空值按 -1 输出（保持 JSON 合法且脚本可判停牌）。 */
function numText(value: number | null | undefined): string {
  if (value === null || value === undefined) {
    return '-1';
  }
  return value.toFixed(2);
}

/** 昨收要 4 位：涨跌停由它乘出来，两位小数会让脚本复算产生 1 分钱的假差异。 */
function numText4(value: number | null | undefined): string {
  if (value === null || value === undefined) {
    return '-1';
  }
  return value.toFixed(4);
}

/** 视图切换节流窗（M8-3：快速连点只生效一次）。 */
const VIEW_TOGGLE_THROTTLE_MS: number = 200;
/** 调试 200 卡压测条数（M8-7，超出 50 上限但只活在内存里，不落盘）。 */
const STRESS_CARD_COUNT: number = 200;

/**
 * 空态范围（M6 追加）：
 * 'all' 自选一只都没有（引导式空态，隐藏指数条/分组页签）；
 * 'group' 当前分组为空但其它分组有票（「该分组暂无股票」+ 查看全部）；
 * 'none' 非空态。
 */
export type WatchEmptyKind = 'none' | 'all' | 'group';

/** 分组 Tab：系统组的文案由 View 按 id 走 i18n；用户组直接用 name（M7-6 修 T-03）。 */
@ObservedV2
export class GroupTabVM {
  id: string = '';
  @Trace name: string = '';
  @Trace system: boolean = false;
  @Trace isUser: boolean = false;
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
  /** 编辑模式（M7-5）：行前勾选、底部「移出（N）」，与比价多选互斥。 */
  @Trace editMode: boolean = false;
  @Trace editSelected: string[] = [];
  /** 撤销条（M7-4）：5s 内可恢复原位置与原分组。 */
  @Trace undoVisible: boolean = false;
  @Trace undoCount: number = 0;
  @Trace undoLeft: number = 0;
  /** 联网后清零的待同步条数（视图提示一次）。 */
  @Trace syncedCount: number = 0;
  /** 视图形态（M8-3）：列表 / 卡片；切换不重建 VM，行数据与排序共享（AC-103）。 */
  @Trace viewMode: ViewMode = 'list';
  /** 卡片几何与呈现口径（M8-1/M8-2）。 */
  @Trace card: CardVM = new CardVM();
  /**
   * 两个视图各自的首行下标（无选中时切回来恢复原位，M8-3）。
   * **刻意不加 `@Trace`**：它们随滚动每帧变化，一旦被 build 读到就会让整页反复重渲染；
   * 只在「切换视图」那一刻被 `anchorIndex` 读取（此时 viewMode 已变，页面本来就要重渲染）。
   */
  listIndex: number = 0;
  cardIndex: number = 0;
  /** 调试 200 卡压测行（M8-7）：非空时卡片视图渲染它，不写 Store、不订阅行情。 */
  @Trace stressRows: WatchRowVM[] = [];

  private repo: WatchlistRepository = new WatchlistRepository();
  private store: WatchlistStore = DataServices.watchlistStore();
  private pref: ViewPrefStore = DataServices.viewPref();
  private analytics: AnalyticsHub = AnalyticsHost.get();
  private lastToggleAt: number = 0;
  private undoSnapshots: RemoveSnapshot[] = [];
  private undoTimer: number = -1;
  private storeListener: WatchlistChangeListener = (change: WatchlistChange): void => {
    this.onStoreChanged(change);
  };
  private storeAttached: boolean = false;
  private syncing: boolean = false;
  private pendingFocus: string = '';
  /** 同步进行中又来了变更：结束后必须再同步一次（分组变更没有焦点 code，不能只靠 pendingFocus）。 */
  private pendingSync: boolean = false;
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

  /**
   * 卡片几何（M8-1）：容器宽取**页面可用宽**（卡片视图在 xl 走整宽，见 `WatchlistPage.splitPane`），
   * 与列表的 `TableMetrics` 各自独立计算，互不影响。
   */
  updateCardLayout(viewport: number, bp: string, fontScale: number): void {
    this.card.update(viewport, bp, fontScale);
  }

  /** 视图形态落定：VM 是唯一持有者，`ConfigService` 只是「首帧预热副本」。 */
  private applyViewMode(mode: ViewMode): void {
    const next: ViewMode = mode === 'card' ? 'card' : 'list';
    if (next !== this.viewMode) {
      this.viewMode = next;
    }
    ConfigHost.getService().applyViewMode(next);
  }

  /**
   * 切换视图（AC-103）：不重建 VM、不重新拉数据、不改分组与排序。
   * 返回 false 表示命中了 200ms 节流（视图无需动画）。
   * `anchorCode` 为右栏当前标的（页面传入），优先级：右栏标的 → 多选/编辑首项 → 该视图上次首行。
   */
  toggleViewMode(anchorCode: string): boolean {
    const now: number = Date.now();
    if (now - this.lastToggleAt < VIEW_TOGGLE_THROTTLE_MS) {
      return false;
    }
    this.lastToggleAt = now;
    const index: number = this.anchorIndex(anchorCode);
    const next: ViewMode = nextViewMode(this.viewMode);
    if (next === 'card') {
      this.cardIndex = index;
    } else {
      this.listIndex = index;
    }
    this.viewMode = next;
    // 目标视图按同一位置落位（列表/卡片都以首行 index 对齐）。
    this.scrollIndex = index;
    this.scrollSeq++;
    this.persistViewMode(next);
    ConfigHost.getService().applyViewMode(next);
    this.analytics.track('card_view_switch', [new AnalyticsParam('mode', next)]);
    hilog.info(0x0001, 'WatchLog', 'view_mode=%{public}s anchor=%{public}d', next, index);
    return true;
  }

  /** 切换锚点：优先「看得见的那一行」，否则回到该视图上次首行。 */
  private anchorIndex(anchorCode: string): number {
    let code: string = anchorCode;
    if (code.length === 0 && this.editSelected.length > 0) {
      code = this.editSelected[0];
    }
    if (code.length === 0 && this.selectedCodes.length > 0) {
      code = this.selectedCodes[0];
    }
    if (code.length > 0) {
      for (let i = 0; i < this.rows.length; i++) {
        if (this.rows[i].code === code) {
          return i;
        }
      }
    }
    if (this.rows.length === 0) {
      return 0;
    }
    const last: number = this.viewMode === 'card' ? this.cardIndex : this.listIndex;
    return Math.min(Math.max(0, last), this.rows.length - 1);
  }

  private async persistViewMode(mode: ViewMode): Promise<void> {
    try {
      await this.pref.setMode(mode);
    } catch (err) {
      // 写失败保留内存态，不阻塞切换（下次切换再写）。
      hilog.warn(0x0001, 'WatchLog', 'view_mode_write_fail');
    }
  }

  /** 排序 chip 清除（AC-102）：回到默认序（保持分组与选中不变）。 */
  clearSort(): void {
    if (this.sortKey === null && this.sortDir === 'none') {
      return;
    }
    this.sortKey = null;
    this.sortDir = 'none';
    this.rebuild();
    this.analytics.track('card_sort_clear', []);
    hilog.info(0x0001, 'WatchLog', 'card_sort_clear');
  }

  /** 卡片视图渲染的行集（压测时用合成行，不影响 Store 与订阅）。 */
  cardRows(): WatchRowVM[] {
    return this.stressRows.length > 0 ? this.stressRows : this.rows;
  }

  stressActive(): boolean {
    return this.stressRows.length > 0;
  }

  /** 调试（M8-7）：生成 200 条合成卡（只复制行情，不落盘、不订阅）。 */
  debugBuildStressRows(): number {
    if (this.allRows.length === 0) {
      return 0;
    }
    const rows: WatchRowVM[] = [];
    for (let i = 0; i < STRESS_CARD_COUNT; i++) {
      const origin: WatchRowVM = this.allRows[i % this.allRows.length];
      const row: WatchRowVM = new WatchRowVM(`S${i}`, origin.name, origin.groups);
      row.copyQuoteFrom(origin);
      rows.push(row);
    }
    this.stressRows = rows;
    hilog.info(0x0001, 'WatchLog', 'card_stress rows=%{public}d', rows.length);
    return rows.length;
  }

  debugClearStressRows(): void {
    if (this.stressRows.length === 0) {
      return;
    }
    this.stressRows = [];
    hilog.info(0x0001, 'WatchLog', 'card_stress cleared');
  }

  /** 调试（M8-4）：清除视图记忆并回列表。 */
  async debugClearViewPref(): Promise<void> {
    await this.pref.clear();
    this.applyViewMode('list');
    this.scrollIndex = 0;
    this.scrollSeq++;
    hilog.info(0x0001, 'WatchLog', 'view_pref_cleared');
  }

  async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.state = 'loading';
    this.dispose();
    const token: number = this.loadToken;
    const startedAt: number = Date.now();
    try {
      // 视图偏好先读（M8-4）：出内容前必须知道列表还是卡片，否则冷启会「先列表后卡片」。
      const prefTask: Promise<void> = this.pref.load();
      const data: WatchlistData = await this.repo.load();
      await prefTask;
      if (token !== this.loadToken) {
        return;
      }
      this.applyViewMode(this.pref.current());
      this.applyData(data);
      this.loaded = true;
      this.subscribe();
      this.attachStore();
      // M9-6 / AC-111：出内容耗时打点（冷启命中缓存时应显著小于网络路径）。
      hilog.info(0x0001, 'QuoteLog', 'watchlist_ready ms=%{public}d quotes=%{public}d',
        Date.now() - startedAt, data.quotes.size);
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
   * 调试（M9-4）：注入行情限流。`retryAfterMs` 为 0 时按 5s 下限。
   * 通道的下一个 1s tick 会把它变成「已降频」，并写 QuoteHealth 驱动提示条。
   */
  applyQuoteRateLimit(on: boolean, retryAfterMs: number): void {
    MockFaults.quoteRateLimited = on;
    MockFaults.quoteRetryAfterMs = on ? retryAfterMs : 0;
    hilog.info(0x0001, 'QuoteLog', 'quote_rate_limit on=%{public}s retryAfter=%{public}d',
      `${on}`, retryAfterMs);
  }

  /** 调试（M9-2）：注入鉴权失败（401 → 刷新一次 → 仍失败 → 未授权）。 */
  applyQuoteUnauthorized(on: boolean): void {
    MockFaults.quoteUnauthorized = on;
    hilog.info(0x0001, 'QuoteLog', 'quote_unauthorized on=%{public}s', `${on}`);
  }

  /** 调试（M9-5）：注入异常帧（时间回退/价格越界/超涨跌停/空帧轮转）。 */
  applyQuoteBadFrames(on: boolean): void {
    MockFaults.quoteBadFrames = on;
    hilog.info(0x0001, 'QuoteLog', 'quote_bad_frames on=%{public}s', `${on}`);
  }

  /** 调试：恢复行情通道（清限流 + 清鉴权锁定 + 重订阅），返回**恢复前**的统计串。 */
  recoverQuoteChannel(): string {
    MockFaults.quoteRateLimited = false;
    MockFaults.quoteRetryAfterMs = 0;
    MockFaults.quoteUnauthorized = false;
    MockFaults.quoteBadFrames = false;
    const channel: QuoteChannel | undefined = DataServices.quoteChannel();
    if (channel === undefined) {
      return 'quote_source=mock（未启用通道）';
    }
    // 先取统计再恢复：recover 会清帧校验计数，取晚了就看不到丢弃数（AC-110 取证要它）。
    const before: string = channel.stats();
    channel.recover(Date.now());
    hilog.info(0x0001, 'QuoteLog', 'quote_recover before[%{public}s] after[%{public}s]',
      before, channel.stats());
    return before;
  }

  /** 调试：行情通道统计（AC-106/107/109/110 的断言来源）。 */
  quoteChannelStats(): string {
    const channel: QuoteChannel | undefined = DataServices.quoteChannel();
    if (channel === undefined) {
      return 'quote_source=mock（未启用通道）';
    }
    return channel.stats();
  }

  /** 调试（M9-6）：清空行情缓存（`quote_cache_v1`）。 */
  async clearQuoteCache(): Promise<void> {
    await DataServices.quoteCache().clear();
    hilog.info(0x0001, 'QuoteLog', 'quote_cache_cleared');
  }

  /**
   * 调试（M9）：切换交易时段（盘前/竞价/午休/收盘/全部停牌/自动/演示开盘）。
   * 行情状态与交易弹窗的时段限制同源（交易侧直接读 `quote.status`），切换后立刻拉一帧刷新。
   */
  applySessionMode(mode: SessionMode): void {
    TradingSession.setMode(mode);
    hilog.info(0x0001, 'QuoteLog', 'session_mode=%{public}s', mode);
    this.refreshQuotesOnce();
  }

  /** 当前时段模式（调试面板展示）。 */
  sessionMode(): SessionMode {
    return TradingSession.current();
  }

  /** 拉一帧快照更新现有行（不重建数组，避免列表位置抖动）。 */
  private refreshQuotesOnce(): void {
    if (!this.loaded || this.allRows.length === 0) {
      return;
    }
    const codes: string[] = [];
    for (let i = 0; i < this.allRows.length; i++) {
      codes.push(this.allRows[i].code);
    }
    DataServices.quoteProvider().getSnapshots(codes).then((list: QuoteSnapshot[]): void => {
      for (let i = 0; i < list.length; i++) {
        const row: WatchRowVM | undefined = this.rowByCode.get(list[i].code);
        if (row !== undefined) {
          row.updateFromSnapshot(list[i]);
        }
      }
    }).catch((): void => {
    });
  }

  /**
   * 调试（M9-7）：导出当前行情采样到 hilog（`QUOTE_SAMPLE {json}`），
   * 供 `scripts/compare-quote.mjs` 做涨跌停/价格区间的独立复算比对。
   */
  async debugExportQuoteSamples(): Promise<number> {
    if (this.allRows.length === 0) {
      return 0;
    }
    const codes: string[] = [];
    for (let i = 0; i < this.allRows.length; i++) {
      codes.push(this.allRows[i].code);
    }
    const snaps: QuoteSnapshot[] = await DataServices.quoteProvider().getSnapshots(codes);
    for (let i = 0; i < snaps.length; i++) {
      const s: QuoteSnapshot = snaps[i];
      // hilog 不支持 %f：数值先格式化成字符串，再用 %s 输出（保持 JSON 可被脚本解析）。
      const json: string = '{"code":"' + s.code + '","status":"' + s.status +
        '","prevClose":' + numText4(s.prevClose) +
        ',"last":' + numText(s.last) +
        ',"limitUp":' + numText(s.limitUp) +
        ',"limitDown":' + numText(s.limitDown) + '}';
      hilog.info(0x0001, 'QuoteSample', 'QUOTE_SAMPLE %{public}s', json);
    }
    hilog.info(0x0001, 'QuoteSample', 'QUOTE_SAMPLE_DONE count=%{public}d', snaps.length);
    return snaps.length;
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
    // 回到前台补一次待同步（网络恢复时页面可能不在前台）。
    DataServices.watchlistSync().trySync();
  }

  /** 编辑模式开关（M7-5）：与比价多选互斥，退出时清空勾选。 */
  toggleEdit(): void {
    if (this.editMode) {
      this.exitEdit();
      return;
    }
    this.selectMode = false;
    this.selectedCodes = [];
    this.editMode = true;
    this.editSelected = [];
    hilog.info(0x0001, 'WatchLog', 'edit_mode=on');
  }

  exitEdit(): void {
    if (!this.editMode && this.editSelected.length === 0) {
      return;
    }
    this.editMode = false;
    this.editSelected = [];
    hilog.info(0x0001, 'WatchLog', 'edit_mode=off');
  }

  isEditSelected(code: string): boolean {
    return this.editSelected.indexOf(code) >= 0;
  }

  /** 编辑态点行 = 勾选（AC-98），不跳详情。 */
  toggleEditSelect(code: string): void {
    const index: number = this.editSelected.indexOf(code);
    if (index >= 0) {
      this.editSelected.splice(index, 1);
      return;
    }
    this.editSelected.push(code);
  }

  /** 全选/取消全选：只作用于当前分组可见行；「是否全选」按包含关系判断（不是数量相等）。 */
  selectAllRows(): void {
    if (this.isAllSelected()) {
      this.editSelected = [];
      return;
    }
    const codes: string[] = [];
    for (let i = 0; i < this.rows.length; i++) {
      codes.push(this.rows[i].code);
    }
    this.editSelected = codes;
  }

  /** 当前分组可见行是否已全选（两个分组行数相同时不能只看长度）。 */
  isAllSelected(): boolean {
    if (this.rows.length === 0) {
      return false;
    }
    for (let i = 0; i < this.rows.length; i++) {
      if (this.editSelected.indexOf(this.rows[i].code) < 0) {
        return false;
      }
    }
    return true;
  }

  clearEditSelection(): void {
    this.editSelected = [];
  }

  /**
   * 移出所选中（AC-98）：确认框在 View，成功后排一条 5s 撤销（AC-97）。
   * 返回实际移出条数。
   */
  async removeEditSelected(): Promise<number> {
    if (this.editSelected.length === 0) {
      return 0;
    }
    const codes: string[] = this.editSelected.slice();
    const outcome: WatchlistRemoveOutcome = await this.store.remove(codes);
    this.exitEdit();
    if (outcome.removed.length > 0) {
      this.startUndo(outcome.snapshots);
      this.analytics.track('watch_remove_batch', [
        new AnalyticsParam('count', `${outcome.removed.length}`)
      ]);
    }
    this.syncFromStore('');
    return outcome.removed.length;
  }

  /** 撤销移出（AC-97）：恢复原位置 + 原分组 + 原 addedAt/pending。 */
  async undoRemove(): Promise<boolean> {
    if (!this.undoVisible) {
      return false;
    }
    const snapshots: RemoveSnapshot[] = this.undoSnapshots.slice();
    this.stopUndo();
    const restored: number = await this.store.restore(snapshots);
    // 恢复的条目可能带着旧 pending：在线时立刻清一次，避免"待同步"残留到下次进页面。
    DataServices.watchlistSync().trySync();
    this.syncFromStore('');
    return restored > 0;
  }

  /** 分组管理（M7-6）：返回值直接是拒绝原因，文案在 View 翻译。 */
  async createGroup(name: string): Promise<GroupEditReason> {
    const outcome: WatchlistGroupOutcome = await this.store.createGroup(name);
    if (outcome.succeeded()) {
      this.analytics.track('watch_group_create', []);
      this.syncFromStore('');
    }
    return outcome.reason;
  }

  async renameGroup(id: string, name: string): Promise<GroupEditReason> {
    const outcome: WatchlistGroupOutcome = await this.store.renameGroup(id, name);
    if (outcome.succeeded()) {
      this.analytics.track('watch_group_rename', []);
      this.syncFromStore('');
    }
    return outcome.reason;
  }

  async deleteGroup(id: string): Promise<GroupEditReason> {
    const outcome: WatchlistGroupOutcome = await this.store.deleteGroup(id);
    if (outcome.succeeded()) {
      if (this.selectedGroupId === id) {
        this.selectedGroupId = 'all';
        this.updateGroupSelection();
      }
      this.analytics.track('watch_group_delete', [
        new AnalyticsParam('reassigned', `${outcome.reassigned.length}`)
      ]);
      this.syncFromStore('');
    }
    return outcome.reason;
  }

  /** 用户组数量（分组管理页头 / ≤7 判断）。 */
  userGroupCount(): number {
    return this.store.userGroupCount();
  }

  /**
   * 调试面板：把自选填到 50 上限（AC-96 上限/部分成功用例需要确定初态）。
   * 只加真实存在的股票（搜索结果里的股票），保证列表显示正常。
   */
  async debugFillToLimit(): Promise<number> {
    const provider: SearchProvider = DataServices.searchProvider();
    if (provider.browse === undefined) {
      return 0;
    }
    const page: StockBrowsePage = await provider.browse(0, 100, 0);
    const inputs: WatchAddInput[] = [];
    for (let i = 0; i < page.items.length; i++) {
      if (page.items[i].kind === 'stock') {
        inputs.push(new WatchAddInput(page.items[i].code, []));
      }
    }
    const outcome: WatchlistAddOutcome = await this.store.addMany(inputs, false);
    this.syncFromStore('');
    hilog.info(0x0001, 'WatchLog', 'debug_fill added=%{public}d', outcome.added.length);
    return outcome.added.length;
  }

  private startUndo(snapshots: RemoveSnapshot[]): void {
    this.stopUndo();
    if (snapshots.length === 0) {
      return;
    }
    this.undoSnapshots = snapshots;
    this.undoCount = snapshots.length;
    this.undoLeft = 5;
    this.undoVisible = true;
    this.undoTimer = setInterval((): void => {
      this.undoLeft--;
      if (this.undoLeft <= 0) {
        this.stopUndo();
      }
    }, 1000);
  }

  private stopUndo(): void {
    if (this.undoTimer !== -1) {
      clearInterval(this.undoTimer);
      this.undoTimer = -1;
    }
    this.undoVisible = false;
    this.undoCount = 0;
    this.undoLeft = 0;
    this.undoSnapshots = [];
  }

  dispose(): void {
    this.loadToken++;
    this.stopUndo();
    this.disposeQuotes();
    this.detachStore();
  }

  selectGroup(id: string): void {
    if (id === this.selectedGroupId) {
      return;
    }
    // 编辑态切分组会留下"看不见的勾选"（移出会删掉屏幕上没有的行）：先退出编辑。
    if (this.editMode) {
      this.exitEdit();
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
    // 卡片视图的 chip 复用同一套状态（CK-2：不新增第三套排序态），点 chip 本体也走这里。
    if (this.viewMode === 'card' && this.sortKey !== null) {
      this.analytics.track('card_sort_by', [
        new AnalyticsParam('key', `${this.sortKey}`),
        new AnalyticsParam('dir', this.sortDir)
      ]);
    }
    this.rebuild();
  }

  onVerticalOffset(offset: number): void {
    this.vOffset = offset;
    const height: number = this.metrics.rowHeight;
    this.listIndex = height > 0 ? Math.floor(offset / height) : 0;
  }

  /** 卡片区首个可见行（M8-3 锚定用）。 */
  onCardIndex(first: number): void {
    this.cardIndex = Math.max(0, first);
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
      row.pending = item.pending;
      const snapshot: QuoteSnapshot | undefined = data.quotes.get(item.code);
      if (snapshot !== undefined) {
        row.updateFromSnapshot(snapshot);
      }
      this.allRows.push(row);
      this.rowByCode.set(row.code, row);
    }
    const previousGroups: GroupTabVM[] = this.groups;
    this.groups = [];
    let selectionFound: boolean = false;
    for (let i = 0; i < data.groups.length; i++) {
      const group: WatchGroup = data.groups[i];
      const id: string = group.id;
      let tab: GroupTabVM | undefined = undefined;
      for (let j = 0; j < previousGroups.length; j++) {
        if (previousGroups[j].id === id) {
          tab = previousGroups[j];
          break;
        }
      }
      const next: GroupTabVM = tab !== undefined ? tab : new GroupTabVM(id);
      next.name = group.name;
      next.system = group.type === 'system';
      next.isUser = group.type === 'user';
      this.groups.push(next);
      if (id === this.selectedGroupId) {
        selectionFound = true;
      }
    }
    // 当前分组被删除（M7-6）：回落到「全部」，不能停在已不存在的分组。
    if (!selectionFound) {
      this.selectedGroupId = 'all';
    }
    // P3（M6 评审遗留）：撤出/删除后清掉多选与编辑态里已不存在的 code，
    // 否则比价会把已删标的带进 PK、编辑「移出」会带着幽灵项。
    this.pruneSelection();
    this.updateGroupCounts();
    this.updateGroupSelection();
    this.rebuild();
  }

  /** 选中集合与现有行对齐（只保留仍存在且在当前可见集合里的 code）。 */
  private pruneSelection(): void {
    if (this.selectedCodes.length > 0) {
      const next: string[] = [];
      for (let i = 0; i < this.selectedCodes.length; i++) {
        if (this.rowByCode.has(this.selectedCodes[i])) {
          next.push(this.selectedCodes[i]);
        }
      }
      if (next.length !== this.selectedCodes.length) {
        this.selectedCodes = next;
      }
    }
    if (this.editSelected.length > 0) {
      const nextEdit: string[] = [];
      for (let i = 0; i < this.editSelected.length; i++) {
        if (this.rowByCode.has(this.editSelected[i])) {
          nextEdit.push(this.editSelected[i]);
        }
      }
      if (nextEdit.length !== this.editSelected.length) {
        this.editSelected = nextEdit;
      }
    }
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
    if (change.pendingSynced > 0) {
      this.syncedCount = change.pendingSynced;
    }
    // 只有「新增」才定位高亮；删除/分组变更后不滚动、不切分组（避免把用户从当前分组踢回全部）。
    // 有排序时不滚动（AC-97：有排序按序落位、不动滚动）。
    const added: string[] = change.added;
    let focus: string = '';
    if (added.length > 0 && this.sortKey === null) {
      focus = added[added.length - 1];
    }
    this.syncFromStore(focus);
  }

  /**
   * 增量同步（不切骨架）：重读 Store 快照 → 复用旧行、补新行 → 重订阅 → 定位并高亮新行。
   * 等同 M7-4 的「乐观插入 + 滚动高亮」，此处 Store 为本地写，延迟可忽略。
   */
  private async syncFromStore(focusCode: string): Promise<void> {
    if (this.syncing) {
      this.pendingSync = true;
      if (focusCode.length > 0) {
        this.pendingFocus = focusCode;
      }
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
      const needAgain: boolean = this.pendingSync;
      this.pendingFocus = '';
      this.pendingSync = false;
      if (needAgain || pending.length > 0) {
        this.syncFromStore(pending);
      }
    }
  }

  /** 定位新行：当前分组看不到时回落到「全部」，最终滚动 + 一次 320ms 高亮。 */
  private focusRow(code: string): void {
    // 有排序时不滚动（AC-97：按序落位、不打断当前手势）。
    if (this.sortKey !== null) {
      return;
    }
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
export { CardVM } from './CardVM';
export { ViewMode } from 'commons_basic';
// 分组容量/组名长度：View 不直接 import commons_data（R-07），由 VM 转出常量与类型。
export type { GroupEditReason } from 'commons_data';
export { WATCHLIST_GROUP_NAME_MAX, WATCHLIST_MAX_USER_GROUPS } from 'commons_data';
