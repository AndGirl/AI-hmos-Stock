import {
  AnalyticsHost,
  AnalyticsHub,
  AnalyticsParam,
  ConnectionHost,
  ConnectionHub
} from 'commons_basic';
import {
  ConnectionState,
  DataServices,
  MockFaults,
  QuotePatch,
  QuoteSink,
  SEARCH_BROWSE_PAGE_SIZE,
  SEARCH_RATE_LIMIT_COOLDOWN_MS,
  SearchFault,
  SearchHit,
  SearchKind,
  SearchProvider,
  SearchResult,
  SearchSection,
  SinkSubscription,
  StockBrowsePage,
  WatchlistAddOutcome,
  WatchlistChange,
  WatchlistChangeListener,
  WatchlistRemoveOutcome,
  WatchlistStore
} from 'commons_data';
import { SearchHistoryStore } from 'commons_data';
import { SearchQuery } from '../repository/SearchQuery';
import { SearchRowVM } from './SearchRowVM';
import { SearchItemVM, SearchSectionVM } from './SearchSectionVM';

/**
 * 搜索面状态（M6-3 / CK-3）：
 * 'results' 是「有结果且在正常网络下」的常规面，其余六个值即 AC-92 的六态
 * （initial / searching / empty / error / offline / rateLimited）。
 */
export type SearchState = 'initial' | 'searching' | 'results' | 'empty' | 'error' | 'offline' | 'rateLimited';

/** 热搜三态：失败整块隐藏（AC-90），不占位、不报错。 */
export type SearchHotState = 'loading' | 'ready' | 'hidden';

/** 空关键词「全部股票」列表状态（M6 追加）。 */
export type BrowseState = 'loading' | 'ready' | 'error' | 'empty';

/** 行点击结果：详情 / 板块二次搜索 / 无动作（指数行不跳转）。 */
export type SearchRowAction = 'detail' | 'sector' | 'none';

/**
 * 就地加/撤自选结果（M6-7 / M6 追加）：
 * 'added' 加入成功，'removed' 撤出成功，'existed' 本地已有（不改 UI），
 * 'limit' 触顶 50 只，'failed' 失败（UI 回滚 pending）。
 */
export type SearchAddResult = 'added' | 'removed' | 'existed' | 'limit' | 'failed';

/**
 * 搜索 VM（M6-3）：六态编排、防抖、seq 作废、缓存、历史、热搜、分栏选中。
 * 约束：不出现 UI 副作用（不弹窗、不路由），中文一律在 View 侧拼（§5.6 红线）。
 */
@ObservedV2
export class SearchVM {
  @Trace state: SearchState = 'initial';
  @Trace term: string = '';
  @Trace sections: SearchSectionVM[] = [];
  /** 拍平后的列表项（段标题 / 行 / 展开）：视图只消费这一条数组。 */
  @Trace items: SearchItemVM[] = [];
  @Trace history: string[] = [];
  @Trace hot: string[] = [];
  @Trace suggestions: string[] = [];
  @Trace hotState: SearchHotState = 'loading';
  @Trace offline: boolean = false;
  @Trace showOfflineBanner: boolean = false;
  @Trace searching: boolean = false;
  @Trace cooldownLeft: number = 0;
  @Trace resultCount: number = 0;
  @Trace costMs: number = 0;
  @Trace selectedCode: string = '';
  /** 空关键词「全部股票」列表（M6 追加）：下拉刷新 + 上拉分页。 */
  @Trace browseRows: SearchRowVM[] = [];
  @Trace browseTotal: number = 0;
  @Trace browseState: BrowseState = 'loading';
  @Trace browseVersion: number = 0;
  @Trace refreshing: boolean = false;
  @Trace loadingMore: boolean = false;

  private query: SearchQuery;
  private store: WatchlistStore;
  private historyStore: SearchHistoryStore;
  private hub: ConnectionHub;
  private analytics: AnalyticsHub;
  private cooldownTimer: number = -1;
  private itemVersion: number = 0;
  private browseSeq: number = 0;
  private browseLoading: boolean = false;
  /** 已向 provider 取到的位置（≠ browseRows.length：去重会丢行）。 */
  private browseOffset: number = 0;
  /** P1 行情同步：当前列表所有股票统一走 QuoteBus（与自选页同一路推送）。 */
  private quoteSub: SinkSubscription | undefined = undefined;
  private quoteKey: string = '';
  private browseRowByCode: Map<string, SearchRowVM> = new Map<string, SearchRowVM>();
  private resultRowByCode: Map<string, SearchRowVM> = new Map<string, SearchRowVM>();
  /** 自选变更监听：清空 / M7 删除等外部改动也要把「已添加」纠正回来。 */
  private storeListener: WatchlistChangeListener = (change: WatchlistChange): void => {
    this.remarkAll();
  };
  private storeAttached: boolean = false;
  private remarkToken: number = 0;
  private initialized: boolean = false;
  private disposed: boolean = false;

  constructor() {
    this.query = new SearchQuery(DataServices.searchProvider());
    this.store = DataServices.watchlistStore();
    this.historyStore = DataServices.searchHistory();
    this.hub = ConnectionHost.getService();
    this.analytics = AnalyticsHost.get();
  }

  /** 页面出现时调用一次：历史/热搜/离线态。 */
  init(): void {
    // Tab 切换可能销毁再创建视图；VM 被 dispose 后在这里重新激活（保留 term/结果）。
    if (this.disposed) {
      this.disposed = false;
      this.query = new SearchQuery(DataServices.searchProvider());
    }
    this.refreshOffline();
    // 页面重建（dispose 后回收）时恢复本地行索引与行情订阅
    this.rebuildBrowseRowMap();
    this.rebuildResultRowMap();
    this.syncQuotes();
    this.attachStore();
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    this.loadHistory();
    this.loadHot();
    this.ensureBrowse();
  }

  /** 连接态变化（GlobalBanner 之外，搜索结果页顶部还要一条 28vp 提示条）。 */
  refreshOffline(): void {
    this.showOfflineBanner = this.hub.isOffline();
    if (this.showOfflineBanner && this.term.trim().length > 0 && this.sections.length > 0) {
      this.state = 'offline';
    }
  }

  /** 输入变化：首字符立即查，其余 300ms 防抖（AC-87）。 */
  onTermChange(raw: string): void {
    const previousHadText: boolean = this.term.trim().length > 0;
    this.term = raw;
    if (raw.trim().length === 0) {
      this.resetToInitial();
      return;
    }
    const immediate: boolean = !previousHadText;
    this.query.schedule((): void => {
      this.execute(false);
    }, immediate);
  }

  /** Enter：立即查并写历史（FR-05.3 / M6-3）。 */
  submit(): void {
    if (this.term.trim().length === 0) {
      return;
    }
    this.query.cancelDebounce();
    this.execute(true);
  }

  retry(): void {
    if (this.cooldownLeft > 0 || this.term.trim().length === 0) {
      return;
    }
    this.execute(false);
  }

  /** 点历史 / 热搜 / 空态建议词：回填并立即查。 */
  pickQuery(text: string): void {
    this.term = text;
    this.query.cancelDebounce();
    this.execute(true);
  }

  /** 行点击：股票进详情（带 rank），板块按名称二次搜索，指数无动作。 */
  pickRow(row: SearchRowVM): SearchRowAction {
    if (row.kind === 'stock') {
      // 只有股票才是右栏详情的标的；板块/指数 code 传给详情会 404（lg/xl 分栏）。
      this.selectedCode = row.code;
      this.pushHistory(this.term);
      this.trackClick(row);
      return 'detail';
    }
    if (row.kind === 'sector') {
      this.term = row.name;
      this.query.cancelDebounce();
      this.execute(true);
      return 'sector';
    }
    return 'none';
  }

  /**
   * 行尾点击（AC-91 变更，M6 追加）：
   * 未添加 → 加自选；已添加 → 撤出自选（直接移除，二次确认由产品口径决定不做）。
   */
  async toggleWatch(row: SearchRowVM): Promise<SearchAddResult> {
    if (row.kind !== 'stock') {
      return 'failed';
    }
    if (row.pending) {
      return 'existed';
    }
    if (row.added) {
      return this.removeRow(row);
    }
    return this.addRow(row);
  }

  /** 就地加自选：成功后行变「已添加」并同步同 code 的另一处行对象。 */
  private async addRow(row: SearchRowVM): Promise<SearchAddResult> {
    if (row.added) {
      return 'existed';
    }
    if (row.kind !== 'stock') {
      return 'failed';
    }
    row.pending = true;
    try {
      const outcome: WatchlistAddOutcome = await this.store.add([row.code], []);
      row.pending = false;
      if (outcome.added.length > 0) {
        this.setAdded(row.code, true);
        this.trackAdd(row);
        return 'added';
      }
      if (outcome.existed.length > 0) {
        this.setAdded(row.code, true);
        return 'existed';
      }
      if (outcome.rejectedLimit.length > 0) {
        return 'limit';
      }
      return 'failed';
    } catch (err) {
      row.pending = false;
      return 'failed';
    }
  }

  /** 就地撤出自选：Store 删除成功后行回「＋」，自选页由 Store 变更监听同步。 */
  private async removeRow(row: SearchRowVM): Promise<SearchAddResult> {
    row.pending = true;
    try {
      const outcome: WatchlistRemoveOutcome = await this.store.remove([row.code]);
      row.pending = false;
      if (outcome.succeeded()) {
        this.setAdded(row.code, false);
        this.trackRemove(row);
        return 'removed';
      }
      return 'failed';
    } catch (err) {
      row.pending = false;
      return 'failed';
    }
  }

  /**
   * 同一个 code 在「搜索结果」和「全部股票」里是两个行对象：
   * 只改被点的那一处会出现「清空搜索后仍显示已添加」的错位，这里两处一起翻转。
   */
  private setAdded(code: string, added: boolean): void {
    for (let i = 0; i < this.sections.length; i++) {
      const rows: SearchRowVM[] = this.sections[i].rows;
      for (let j = 0; j < rows.length; j++) {
        if (rows[j].code === code && rows[j].kind === 'stock') {
          SearchVM.applyAdded(rows[j], added);
        }
      }
    }
    for (let i = 0; i < this.browseRows.length; i++) {
      if (this.browseRows[i].code === code && this.browseRows[i].kind === 'stock') {
        SearchVM.applyAdded(this.browseRows[i], added);
      }
    }
  }

  private static applyAdded(row: SearchRowVM, added: boolean): void {
    if (added) {
      row.markAdded();
    } else {
      row.markRemoved();
    }
  }

  /** 订阅自选变更：外部清空 / 删除后，行情页的「已添加」不能停留在旧状态。 */
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

  /**
   * 全量重算「已添加」：变更可能来自本页，也可能来自调试清空 / M7 删除，
   * 逐行以 Store 为准纠正（行对象按 code 分处两份，不能只改被点的那一处）。
   * remarkToken 防止多次变更交错时旧结果覆盖新结果。
   */
  private async remarkAll(): Promise<void> {
    const token: number = ++this.remarkToken;
    const rows: SearchRowVM[] = [];
    for (let i = 0; i < this.sections.length; i++) {
      const sectionRows: SearchRowVM[] = this.sections[i].rows;
      for (let j = 0; j < sectionRows.length; j++) {
        if (sectionRows[j].kind === 'stock') {
          rows.push(sectionRows[j]);
        }
      }
    }
    for (let i = 0; i < this.browseRows.length; i++) {
      if (this.browseRows[i].kind === 'stock') {
        rows.push(this.browseRows[i]);
      }
    }
    if (rows.length === 0) {
      return;
    }
    try {
      await this.store.load();
    } catch (err) {
      return;
    }
    for (let i = 0; i < rows.length; i++) {
      if (this.disposed || token !== this.remarkToken) {
        return;
      }
      try {
        const has: boolean = await this.store.has(rows[i].code);
        SearchVM.applyAdded(rows[i], has);
      } catch (err) {
        return;
      }
    }
  }

  toggleSection(index: number): void {
    if (index < 0 || index >= this.sections.length) {
      return;
    }
    this.sections[index].expanded = !this.sections[index].expanded;
    this.rebuildItems();
  }

  async removeHistory(text: string): Promise<void> {
    this.history = await this.historyStore.remove(text);
  }

  async clearHistory(): Promise<void> {
    await this.historyStore.clear();
    this.history = [];
  }

  hasQuery(): boolean {
    return this.term.trim().length > 0;
  }

  /**
   * 仅 debug 可达的故障注入（AC-92 六态复现）：
   * 'fail' 失败 / 'rate' 429 / 'offline' 离线 / 'hot' 热搜失败 / 'reset' 恢复。
   */
  applyDebugFault(kind: string): void {
    // 先清缓存：否则同 term 命中 LRU，故障注入会被绕过（验收时踩过）。
    this.query.clearCache();
    MockFaults.failSearch = false;
    MockFaults.searchRateLimited = false;
    MockFaults.failHot = false;
    MockFaults.searchSlow = false;
    MockFaults.netFault = 'none';
    this.hub.reset();
    if (kind === 'fail') {
      MockFaults.failSearch = true;
    } else if (kind === 'rate') {
      MockFaults.searchRateLimited = true;
    } else if (kind === 'slow') {
      MockFaults.searchSlow = true;
    } else if (kind === 'offline') {
      // 同时置 MockFaults.netFault：否则 ConnectionHub 的探活会在首个重试即恢复在线。
      MockFaults.netFault = 'offline';
      this.hub.force('offline');
      this.showOfflineBanner = true;
      this.runDebugQuery();
      return;
    } else if (kind === 'hot') {
      MockFaults.failHot = true;
      this.hotState = 'loading';
      this.hot = [];
      this.loadHot();
    }
    this.runDebugQuery();
  }

  private runDebugQuery(): void {
    this.cooldownLeft = 0;
    this.stopCooldown();
    if (this.term.trim().length > 0) {
      this.execute(false);
    } else {
      this.resetToInitial();
    }
  }

  dispose(): void {
    this.disposed = true;
    this.remarkToken++;
    this.browseSeq++;
    this.browseLoading = false;
    this.refreshing = false;
    this.loadingMore = false;
    this.disposeQuotes();
    this.detachStore();
    this.query.dispose();
    this.stopCooldown();
    this.analytics.flush();
  }

  private resetToInitial(): void {
    this.query.invalidate();
    this.state = 'initial';
    this.sections = [];
    this.items = [];
    this.resultCount = 0;
    this.searching = false;
    this.costMs = 0;
    this.cooldownLeft = 0;
    this.stopCooldown();
    this.refreshOffline();
    this.ensureBrowse();
    this.syncQuotes();
  }

  /** 是否已加载完全部股票（空关键词列表）。 */
  allLoaded(): boolean {
    return this.browseTotal > 0 && this.browseOffset >= this.browseTotal;
  }

  /** 首次进入/清空输入时确保首屏加载（已加载过则直接复用）。 */
  ensureBrowse(): void {
    if (this.browseLoading) {
      return;
    }
    if (this.browseState === 'ready' || this.browseState === 'empty') {
      return;
    }
    this.fetchBrowsePage(0, SEARCH_BROWSE_PAGE_SIZE, true, false);
  }

  /** 下拉刷新：保留已加载条数，整段重取（价格为最新快照）。 */
  refreshBrowse(): void {
    if (this.refreshing) {
      return;
    }
    if (this.browseLoading) {
      return;
    }
    this.refreshing = true;
    const limit: number = Math.max(SEARCH_BROWSE_PAGE_SIZE, this.browseOffset);
    this.fetchBrowsePage(0, limit, true, true);
  }

  /** 上拉加载更多：仅 ready 且未加载完时触发，防重入。 */
  loadMore(): void {
    if (this.loadingMore || this.browseLoading) {
      return;
    }
    if (this.browseState !== 'ready' || this.allLoaded()) {
      return;
    }
    this.loadingMore = true;
    // offset 必须独立于 browseRows.length：列表按实时成交额排序且按 code 去重，
    // 排序抖动会让两者不一致，导致漏行或到底后原地反复请求同一页。
    this.fetchBrowsePage(this.browseOffset, SEARCH_BROWSE_PAGE_SIZE, false, false);
  }

  /** 底部「加载失败，点击重试」：无数据时重取首屏，有数据时续页。 */
  retryBrowse(): void {
    if (this.browseRows.length === 0) {
      this.browseState = 'loading';
      this.fetchBrowsePage(0, SEARCH_BROWSE_PAGE_SIZE, true, false);
      return;
    }
    this.browseState = 'ready';
    this.loadMore();
  }

  private fetchBrowsePage(offset: number, limit: number, replace: boolean,
    isRefresh: boolean): void {
    const provider: SearchProvider = DataServices.searchProvider();
    if (provider.browse === undefined) {
      this.browseState = 'empty';
      this.browseLoading = false;
      this.refreshing = false;
      this.loadingMore = false;
      return;
    }
    this.browseSeq++;
    const seq: number = this.browseSeq;
    this.browseLoading = true;
    if (replace && !isRefresh) {
      this.browseState = 'loading';
    }
    provider.browse(offset, limit, seq).then((page: StockBrowsePage): void => {
      if (this.disposed || seq !== this.browseSeq) {
        return;
      }
      this.browseLoading = false;
      this.applyBrowsePage(page, replace);
    }).catch((err: Error): void => {
      if (this.disposed || seq !== this.browseSeq) {
        return;
      }
      this.browseLoading = false;
      this.refreshing = false;
      this.loadingMore = false;
      if (!replace && this.browseRows.length > 0) {
        // 续页失败：保留已有行，底部显示「加载失败，点击重试」
        this.browseState = 'error';
      } else if (replace && this.browseRows.length > 0) {
        // 刷新失败：保留旧数据，不打断阅读（静默）
        this.browseState = 'ready';
      } else {
        this.browseState = 'error';
      }
    });
  }

  private applyBrowsePage(page: StockBrowsePage, replace: boolean): void {
    const rows: SearchRowVM[] = replace ? [] : this.browseRows.slice();
    const existing: Set<string> = new Set<string>();
    for (let i = 0; i < rows.length; i++) {
      existing.add(rows[i].code);
    }
    for (let i = 0; i < page.items.length; i++) {
      const hit: SearchHit = page.items[i];
      if (existing.has(hit.code)) {
        continue;
      }
      existing.add(hit.code);
      const row: SearchRowVM = new SearchRowVM();
      row.apply(hit, rows.length);
      rows.push(row);
    }
    this.browseRows = rows;
    this.browseTotal = page.total;
    // 记录「已向 provider 取到哪一页」，与去重后的行数解耦；翻页只在追加时不需要重建整段。
    this.browseOffset = page.offset + page.items.length;
    if (replace) {
      this.browseVersion++;
    }
    this.browseState = page.total === 0 ? 'empty' : 'ready';
    this.refreshing = false;
    this.loadingMore = false;
    this.markRowsAdded(rows);
    this.rebuildBrowseRowMap();
    this.syncQuotes();
  }

  private rebuildBrowseRowMap(): void {
    const map: Map<string, SearchRowVM> = new Map<string, SearchRowVM>();
    for (let i = 0; i < this.browseRows.length; i++) {
      const row: SearchRowVM = this.browseRows[i];
      if (row.kind === 'stock') {
        map.set(row.code, row);
      }
    }
    this.browseRowByCode = map;
  }

  private rebuildResultRowMap(): void {
    const map: Map<string, SearchRowVM> = new Map<string, SearchRowVM>();
    for (let i = 0; i < this.sections.length; i++) {
      const rows: SearchRowVM[] = this.sections[i].rows;
      for (let j = 0; j < rows.length; j++) {
        if (rows[j].kind === 'stock') {
          map.set(rows[j].code, rows[j]);
        }
      }
    }
    this.resultRowByCode = map;
  }

  /**
   * P1 行情同步：按当前可见面（结果 or 全部股票）维护一条 QuoteBus 订阅。
   * 只订阅股票（指数/板块无实时推送）；代码集合变化时才重订阅。
   */
  private syncQuotes(): void {
    const map: Map<string, SearchRowVM> = this.hasQuery() ? this.resultRowByCode : this.browseRowByCode;
    const codes: string[] = [];
    map.forEach((row: SearchRowVM): void => {
      codes.push(row.code);
    });
    codes.sort();
    const key: string = codes.join(',');
    if (key === this.quoteKey) {
      return;
    }
    this.quoteKey = key;
    if (this.quoteSub !== undefined) {
      this.quoteSub.unsubscribe();
      this.quoteSub = undefined;
    }
    if (codes.length === 0) {
      return;
    }
    const sink: QuoteSink = new SearchQuoteSink((patch: QuotePatch): void => {
      this.onQuotePatch(patch);
    });
    this.quoteSub = DataServices.quoteBus().subscribe(codes, sink);
  }

  private onQuotePatch(patch: QuotePatch): void {
    const row: SearchRowVM | undefined = this.resultRowByCode.get(patch.code);
    const target: SearchRowVM | undefined = row !== undefined ? row : this.browseRowByCode.get(patch.code);
    if (target !== undefined) {
      target.applyQuote(patch);
    }
  }

  private disposeQuotes(): void {
    if (this.quoteSub !== undefined) {
      this.quoteSub.unsubscribe();
      this.quoteSub = undefined;
    }
    this.quoteKey = '';
    this.resultRowByCode.clear();
    this.browseRowByCode.clear();
  }

  private execute(writeHistory: boolean): void {
    const term: string = this.term.trim();
    if (term.length === 0 || this.disposed) {
      return;
    }
    if (this.cooldownLeft > 0) {
      return;
    }
    const seq: number = this.query.nextSeq();
    this.offline = this.hub.isOffline();
    this.showOfflineBanner = this.offline;
    this.searching = true;
    if (this.sections.length === 0) {
      this.state = 'searching';
    }
    this.track('search_query', [
      new AnalyticsParam('len', `${term.length}`),
      new AnalyticsParam('seq', `${seq}`),
      new AnalyticsParam('offline', this.offline ? '1' : '0')
    ]);
    this.query.run(term, seq, this.offline).then((result: SearchResult): void => {
      if (this.disposed || !this.query.isLatest(seq)) {
        return;
      }
      this.applyResult(result);
      if (writeHistory) {
        this.pushHistory(term);
      }
    }).catch((err: Error): void => {
      if (this.disposed || !this.query.isLatest(seq)) {
        return;
      }
      this.searching = false;
      this.handleError(err);
    });
  }

  private applyResult(result: SearchResult): void {
    this.searching = false;
    this.costMs = result.costMs;
    this.offline = result.offline || this.hub.isOffline();
    this.showOfflineBanner = this.offline;
    const sections: SearchSectionVM[] = [];
    let count: number = 0;
    for (let i = 0; i < result.sections.length; i++) {
      const section: SearchSection = result.sections[i];
      sections.push(SearchSectionVM.from(section));
      count += section.hits.length;
    }
    this.sections = sections;
    this.resultCount = count;
    this.rebuildItems();
    if (this.offline) {
      this.state = 'offline';
    } else if (count === 0) {
      this.state = 'empty';
    } else {
      this.state = 'results';
    }
    this.suggestions = count === 0 ? this.hot.slice(0, 3) : [];
    this.track('search_result', [
      new AnalyticsParam('count', `${count}`),
      new AnalyticsParam('cost', `${result.costMs}`),
      new AnalyticsParam('offline', this.offline ? '1' : '0')
    ]);
    this.rebuildResultRowMap();
    this.syncQuotes();
    this.markAddedAsync(sections);
  }

  /**
   * 生成拍平列表项（含唯一 key）。
   * key 带版本号：结果刷新 / 展开收起都会换 key，ForEach 才会重建子组件，
   * 避免「旧帧结果残留」这类只有 key 相同才出现的渲染问题。
   */
  private rebuildItems(): void {
    this.itemVersion++;
    const version: number = this.itemVersion;
    const items: SearchItemVM[] = [];
    for (let i = 0; i < this.sections.length; i++) {
      const section: SearchSectionVM = this.sections[i];
      const header: SearchItemVM = new SearchItemVM();
      header.kind = 'header';
      header.key = `${version}-h-${i}`;
      header.sectionKind = section.kind;
      header.sectionIndex = i;
      header.total = section.total;
      items.push(header);
      const rows: SearchRowVM[] = section.visibleRows();
      for (let j = 0; j < rows.length; j++) {
        const rowItem: SearchItemVM = new SearchItemVM();
        rowItem.kind = 'row';
        rowItem.key = `${version}-r-${i}-${rows[j].code}`;
        rowItem.sectionKind = section.kind;
        rowItem.sectionIndex = i;
        rowItem.row = rows[j];
        items.push(rowItem);
      }
      if (section.canExpand() || section.canCollapse()) {
        const toggleItem: SearchItemVM = new SearchItemVM();
        toggleItem.kind = section.expanded ? 'less' : 'expand';
        toggleItem.key = `${version}-t-${i}`;
        toggleItem.sectionKind = section.kind;
        toggleItem.sectionIndex = i;
        items.push(toggleItem);
      }
    }
    this.items = items;
  }

  private handleError(err: Error): void {    let reason: string = 'failed';
    if (err instanceof SearchFault) {
      reason = err.reason;
    }
    this.track('search_result', [
      new AnalyticsParam('state', reason)
    ]);
    if (reason === 'rate_limited') {
      this.state = 'rateLimited';
      const waitMs: number = err instanceof SearchFault && err.retryAfterMs > 0 ?
        err.retryAfterMs : SEARCH_RATE_LIMIT_COOLDOWN_MS;
      this.startCooldown(waitMs);
      return;
    }
    if (reason === 'offline' || this.hub.isOffline()) {
      this.state = 'offline';
      this.showOfflineBanner = true;
      return;
    }
    this.state = 'error';
  }

  private startCooldown(waitMs: number): void {
    this.stopCooldown();
    this.cooldownLeft = Math.ceil(waitMs / 1000);
    if (this.cooldownLeft <= 0) {
      this.cooldownLeft = 1;
    }
    this.cooldownTimer = setInterval((): void => {
      this.cooldownLeft--;
      if (this.cooldownLeft <= 0) {
        this.cooldownLeft = 0;
        this.stopCooldown();
      }
    }, 1000);
  }

  private stopCooldown(): void {
    if (this.cooldownTimer !== -1) {
      clearInterval(this.cooldownTimer);
      this.cooldownTimer = -1;
    }
  }

  private loadHistory(): void {
    this.historyStore.load().then((items: string[]): void => {
      if (!this.disposed) {
        this.history = items;
      }
    }).catch((): void => {
    });
  }

  private loadHot(): void {
    const provider: SearchProvider = DataServices.searchProvider();
    this.hotState = 'loading';
    provider.hot().then((words: string[]): void => {
      if (this.disposed) {
        return;
      }
      this.hot = words;
      this.hotState = words.length > 0 ? 'ready' : 'hidden';
    }).catch((): void => {
      if (!this.disposed) {
        this.hot = [];
        this.hotState = 'hidden';
      }
    });
  }

  private pushHistory(term: string): void {
    this.historyStore.add(term).then((items: string[]): void => {
      if (!this.disposed) {
        this.history = items;
      }
    }).catch((): void => {
    });
  }

  /** 结果的「已添加」态读自选仓储（不单独缓存，CC-3.7）。 */
  private async markAddedAsync(sections: SearchSectionVM[]): Promise<void> {
    const rows: SearchRowVM[] = [];
    for (let i = 0; i < sections.length; i++) {
      const sectionRows: SearchRowVM[] = sections[i].rows;
      for (let j = 0; j < sectionRows.length; j++) {
        rows.push(sectionRows[j]);
      }
    }
    await this.markRowsAdded(rows);
  }

  /** 空关键词列表复用同一套「已添加」回填逻辑。 */
  private async markRowsAdded(rows: SearchRowVM[]): Promise<void> {
    try {
      await this.store.load();
    } catch (err) {
      return;
    }
    for (let j = 0; j < rows.length; j++) {
      if (rows[j].added || this.disposed) {
        continue;
      }
      try {
        const has: boolean = await this.store.has(rows[j].code);
        if (has) {
          rows[j].markAdded();
        }
      } catch (err) {
        return;
      }
    }
  }

  private trackClick(row: SearchRowVM): void {
    this.track('search_click', [
      new AnalyticsParam('code', row.code),
      new AnalyticsParam('rank', `${row.rank}`),
      new AnalyticsParam('kind', row.kind)
    ]);
  }

  private trackAdd(row: SearchRowVM): void {
    this.track('search_add_watchlist', [
      new AnalyticsParam('code', row.code),
      new AnalyticsParam('rank', `${row.rank}`)
    ]);
  }

  private trackRemove(row: SearchRowVM): void {
    this.track('search_remove_watchlist', [
      new AnalyticsParam('code', row.code),
      new AnalyticsParam('rank', `${row.rank}`)
    ]);
  }

  private track(event: string, params: AnalyticsParam[]): void {
    this.analytics.track(event, params);
  }
}

/** 供 View 判断段标题 key：kind → 资源名映射集中在 View（VM 不出中文）。 */
export function isStockKind(kind: SearchKind): boolean {
  return kind === 'stock';
}

/** View 需要的高亮区间类型从 VM 侧再导出（R-07：view 不许直接 import commons_data）。 */
export { HitRange } from '../repository/MatchRules';


/** 命中列表转行 VM（单测/调试可用）。 */
export function toRows(hits: SearchHit[]): SearchRowVM[] {
  const rows: SearchRowVM[] = [];
  for (let i = 0; i < hits.length; i++) {
    const row: SearchRowVM = new SearchRowVM();
    row.apply(hits[i], i);
    rows.push(row);
  }
  return rows;
}

/** QuoteBus sink：把行情回调转成 VM 方法，避免未声明类型的对象字面量。 */
class SearchQuoteSink implements QuoteSink {
  private handler: (patch: QuotePatch) => void;

  constructor(handler: (patch: QuotePatch) => void) {
    this.handler = handler;
  }

  onPatch(patch: QuotePatch): void {
    this.handler(patch);
  }

  onStatus(state: ConnectionState): void {
    // 连接态由 ConnectionHub / GlobalBanner 统一处理，搜索行不各自维护状态
  }
}
