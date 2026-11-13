import {
  applyWeights,
  computePosition,
  ConnectionState,
  DataServices,
  MockFaults,
  nextPositionSortDir,
  Position,
  PositionBasis,
  PositionSortDir,
  PositionSortKey,
  PositionSummary,
  QuotePatch,
  QuoteSink,
  SinkSubscription,
  sortPositions,
  summarizePositions,
  WatchlistChange,
  WatchlistChangeListener,
  WatchlistStore
} from 'commons_data';
import { AnalyticsHost, AnalyticsParam } from 'commons_basic';
import { PositionRowVM } from './PositionRowVM';

/** 持仓页状态：加载 / 有内容 / 空（无持仓）/ 失败可重试（AC-119）。 */
export type PositionState = 'loading' | 'content' | 'empty' | 'error';

/** 加自选结果（View 映射文案）。 */
export type PositionAddOutcome = 'added' | 'existed' | 'limit' | 'failed';

/** 排序类型对 View 再导出：View 不得 import commons_data（R-07），从 VM 取类型。 */
export { PositionSortDir, PositionSortKey } from 'commons_data';

/** 行情 sink：只把 patch 转给 VM（连接态由 GlobalBanner 统一，不在页面各维护一份）。 */
class PositionQuoteSink implements QuoteSink {
  private handler: (patch: QuotePatch) => void;

  constructor(handler: (patch: QuotePatch) => void) {
    this.handler = handler;
  }

  onPatch(patch: QuotePatch): void {
    this.handler(patch);
  }

  onStatus(state: ConnectionState): void {
  }
}

/**
 * 持仓页 VM（M11-2 / M11-3）。
 *
 * 口径：
 * - 数据只走 `DataServices.positionProvider()`（主账户）与 `QuoteBus`（不新建通道）；
 * - 盈亏/市值/仓位全部由 `commons/data/rules/PositionRules` 计算，VM 不重复公式；
 * - 排序是快照序（点 chip 时排一次），行情刷新只改数值不重排，避免列表跳动；
 * - 行情 patch 原地更新行对象，`List` 以 code 为 key，滚动位置不动。
 */
@ObservedV2
export class PositionVM {
  @Trace state: PositionState = 'loading';
  @Trace rows: PositionRowVM[] = [];
  @Trace sortKey: PositionSortKey | null = null;
  @Trace sortDir: PositionSortDir = 'none';
  /** 主账户脱敏号（口径透明：持仓页只展示主账户）。 */
  @Trace accountMask: string = '';
  @Trace marketValue: number = 0;
  @Trace dayPnl: number = 0;
  @Trace totalPnl: number = 0;
  @Trace costTotal: number = 0;
  @Trace pnlRatio: number | null = null;
  @Trace count: number = 0;
  @Trace unvalued: number = 0;
  @Trace busy: boolean = false;

  private positions: Position[] = [];
  private bases: PositionBasis[] = [];
  private rowByCode: Map<string, PositionRowVM> = new Map<string, PositionRowVM>();
  private quoteSub: SinkSubscription | undefined = undefined;
  private sink: QuoteSink | undefined = undefined;
  private token: number = 0;
  private attached: boolean = false;
  private trackedOpen: boolean = false;
  private storeListener: WatchlistChangeListener = (change: WatchlistChange): void => {
    this.refreshAdded();
  };

  /** 首次进入 / 下拉刷新 / 重试：重新读持仓 + 行情快照。 */
  async load(): Promise<void> {
    this.token++;
    const token: number = this.token;
    this.busy = true;
    if (this.positions.length === 0) {
      this.state = 'loading';
    }
    try {
      const list: Position[] = await DataServices.positionProvider().positions();
      if (token !== this.token) {
        return;
      }
      this.positions = list;
      this.bases = [];
      this.rowByCode = new Map<string, PositionRowVM>();
      const rows: PositionRowVM[] = [];
      for (let i = 0; i < list.length; i++) {
        const item: Position = list[i];
        this.bases.push(this.basisOf(item));
        const row: PositionRowVM = PositionRowVM.of(item);
        this.rowByCode.set(item.code, row);
        rows.push(row);
      }
      this.rows = rows;
      this.attachStore();
      this.accountMask = await this.accountMaskOf();
      if (token !== this.token) {
        return;
      }
      await this.refreshAdded();
      this.applySort();
      this.recomputeSummary();
      this.subscribeQuotes();
      this.state = list.length === 0 ? 'empty' : 'content';
      this.trackOpen();
    } catch (err) {
      if (token === this.token) {
        this.state = 'error';
      }
    } finally {
      if (token === this.token) {
        this.busy = false;
      }
    }
  }

  /** 排序 chip：同一字段循环 降 → 升 → 取消；换字段从降序开始。 */
  cycleSort(key: PositionSortKey): void {
    if (this.sortKey === key) {
      this.sortDir = nextPositionSortDir(this.sortDir);
    } else {
      this.sortKey = key;
      this.sortDir = 'desc';
    }
    if (this.sortDir === 'none') {
      this.sortKey = null;
    }
    this.applySort();
  }

  /** 清除排序（回到默认：市值降序，与 Provider 一致）。 */
  clearSort(): void {
    this.sortKey = null;
    this.sortDir = 'none';
    this.applySort();
  }

  /** 行尾「＋」/「已添加」（AC-120）：写 `WatchlistStore`，结果交 View 映射文案。 */
  async toggleWatch(row: PositionRowVM): Promise<PositionAddOutcome> {
    if (row.added) {
      return 'existed';
    }
    try {
      const store: WatchlistStore = DataServices.watchlistStore();
      const outcome = await store.add([row.code], []);
      // 离线加入会落在 pending（AC-96），同样算「已添加」，避免提示失败但实际已入自选。
      if (outcome.added.length > 0 || outcome.pending.length > 0) {
        row.setAdded(true);
        this.track('position_add_watchlist', row.code);
        return 'added';
      }
      if (outcome.existed.length > 0) {
        row.setAdded(true);
        return 'existed';
      }
      if (outcome.rejectedLimit.length > 0) {
        return 'limit';
      }
      return 'failed';
    } catch (err) {
      return 'failed';
    }
  }

  /** 页面销毁：退订行情与自选变更（不清理全局 store）。 */
  dispose(): void {
    if (this.quoteSub !== undefined) {
      this.quoteSub.unsubscribe();
      this.quoteSub = undefined;
    }
    if (this.attached) {
      DataServices.watchlistStore().unsubscribe(this.storeListener);
      this.attached = false;
    }
  }

  // ---------- 调试（仅 debug 入口调用） ----------

  /** 模拟持仓加载失败（AC-119 失败态与重试）。 */
  async debugFail(on: boolean): Promise<void> {
    MockFaults.failPositions = on;
    await this.load();
  }

  /** 重置账户与委托（回到种子：现金/持仓/开户标记）。 */
  async debugResetAccount(): Promise<void> {
    const trade = DataServices.localTrade();
    if (trade !== undefined) {
      await trade.resetAll();
    }
    await this.load();
  }

  /** 清空主账户持仓（验空态；现金不变，可用「重置账户」恢复）。 */
  async debugClearHoldings(): Promise<void> {
    const store = DataServices.tradeAccount();
    await store.load();
    await store.clearHoldings(store.primaryId());
    await this.load();
  }

  // ---------- 私有 ----------

  private basisOf(item: Position): PositionBasis {
    // 停牌时 item.last 已是「最近有效价」，作为 lastKnown 继续兜底。
    return new PositionBasis(item.code, item.name, item.qty, item.available, item.costPrice,
      item.last, item.last, item.prevClose, item.status, item.accountId, 'withoutFee');
  }

  private applySort(): void {
    const key: PositionSortKey | null = this.sortKey;
    const dir: PositionSortDir = this.sortDir;
    let ordered: Position[] = this.positions;
    if (key !== null && dir !== 'none') {
      ordered = sortPositions(this.positions, key, dir);
    }
    const rows: PositionRowVM[] = [];
    for (let i = 0; i < ordered.length; i++) {
      const row: PositionRowVM | undefined = this.rowByCode.get(ordered[i].code);
      if (row !== undefined) {
        rows.push(row);
      }
    }
    this.rows = rows;
  }

  private recomputeSummary(): void {
    const summary: PositionSummary = summarizePositions(this.positions);
    this.marketValue = summary.marketValue;
    this.dayPnl = summary.dayPnl;
    this.totalPnl = summary.totalPnl;
    this.costTotal = summary.costTotal;
    this.count = summary.count;
    this.unvalued = summary.unvalued;
    this.pnlRatio = summary.ratio();
  }

  private subscribeQuotes(): void {
    if (this.quoteSub !== undefined) {
      this.quoteSub.unsubscribe();
      this.quoteSub = undefined;
    }
    const codes: string[] = [];
    for (let i = 0; i < this.positions.length; i++) {
      codes.push(this.positions[i].code);
    }
    if (codes.length === 0) {
      return;
    }
    if (this.sink === undefined) {
      this.sink = new PositionQuoteSink((patch: QuotePatch): void => {
        this.handlePatch(patch);
      });
    }
    this.quoteSub = DataServices.quoteBus().subscribe(codes, this.sink);
  }

  /** 行情 patch：只更新对应行 + 重新分摊仓位 + 汇总，不重排、不重建行对象。 */
  private handlePatch(patch: QuotePatch): void {
    if (patch.last === undefined || patch.last === null) {
      return;
    }
    const index: number = this.indexOf(patch.code);
    if (index < 0) {
      return;
    }
    const basis: PositionBasis = this.bases[index];
    basis.last = patch.last;
    if (patch.status !== undefined) {
      basis.status = patch.status;
    }
    this.positions[index] = computePosition(basis);
    applyWeights(this.positions);
    for (let i = 0; i < this.positions.length; i++) {
      const row: PositionRowVM | undefined = this.rowByCode.get(this.positions[i].code);
      if (row !== undefined) {
        row.copy(this.positions[i]);
      }
    }
    this.recomputeSummary();
  }

  private indexOf(code: string): number {
    for (let i = 0; i < this.positions.length; i++) {
      if (this.positions[i].code === code) {
        return i;
      }
    }
    return -1;
  }

  private attachStore(): void {
    if (this.attached) {
      return;
    }
    this.attached = true;
    DataServices.watchlistStore().subscribe(this.storeListener);
  }

  private async refreshAdded(): Promise<void> {
    try {
      const store: WatchlistStore = DataServices.watchlistStore();
      await store.load();
      const codes: string[] = await store.codes();
      const set: Set<string> = new Set<string>(codes);
      this.rowByCode.forEach((row: PositionRowVM): void => {
        row.setAdded(set.has(row.code));
      });
    } catch (err) {
      // 自选读失败不影响持仓主链路：按钮保持「＋」，用户再点会重试。
    }
  }

  private async accountMaskOf(): Promise<string> {
    try {
      const store = DataServices.tradeAccount();
      await store.load();
      const record = store.record(store.primaryId());
      return record !== undefined ? record.maskNo : '';
    } catch (err) {
      return '';
    }
  }

  private trackOpen(): void {
    if (this.trackedOpen) {
      return;
    }
    this.trackedOpen = true;
    this.track('position_open', `${this.count}`);
  }

  private track(event: string, value: string): void {
    const key: string = event === 'position_open' ? 'count' : 'code';
    AnalyticsHost.get().track(event, [new AnalyticsParam(key, value)]);
  }
}
