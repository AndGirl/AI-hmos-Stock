import { hilog } from '@kit.PerformanceAnalysisKit';
import { detailSubscriptionStats } from 'detail';
import { computeLayout, layoutViolations, PkLayoutKind, PK_MAX_WINDOWS, SlotLayout } from '../repository/PkLayout';
import { PkRepository } from '../repository/PkRepository';
import { PkSavedGroup, PkStore } from '../repository/PkStore';

const DOMAIN: number = 0x0001;
const TAG: string = 'PkLog';

/** 窗推送档位（与 detail 的 DetailTier 同形，避免 features 之间传类型）。 */
export type PkWindowTier = 'focus' | 'normal' | 'background';

/** PK 入口来源（FR-08.1 三入口，埋点用）。 */
export type PkEntrySource = 'detail' | 'icon' | 'watchlist';

/** 提示条/ toast 码（文案在 view 的 PkText 组装，VM 零中文）。 */
export type PkToastCode = 'max_windows' | 'already_open' | 'swapped' | 'degrade_throttle' |
  'degrade_close' | 'restore_failed' | 'restored' | 'sync_done' | 'single_window';

/** 换股候选项（已取名称/价格，视图直接展示）。 */
export class PkCandidate {
  code: string;
  name: string;
  last: number | null;
  pct: number | null;

  constructor(code: string, name: string, last: number | null, pct: number | null) {
    this.code = code;
    this.name = name;
    this.last = last;
    this.pct = pct;
  }
}

/**
 * 单窗状态（INV-W1）：只持有 code / 周期同步序列，行情、缩放、滚动都在窗内 DetailVM 与图表对象里。
 * `period` 是该窗当前生效周期（由内容侧上报），用于「同步周期」与换股保留周期。
 */
@ObservedV2
export class PkWindowVM {
  id: number;
  @Trace code: string = '';
  @Trace period: string = '';
  /** 请求内容侧应用 period（换股/同步/恢复时 +1）。 */
  @Trace syncSeq: number = 0;
  @Trace focused: boolean = false;

  constructor(id: number, code: string, period: string) {
    this.id = id;
    this.code = code;
    this.period = period;
  }
}

/**
 * 多窗编排 VM（L3，INV-W5：只持有 code 与布局参数，不持有页面内容引用）。
 * 负责：窗集合与窗序、焦点、换股（含交换）、同步周期、关窗、降级链、持久化与埋点。
 */
@ObservedV2
export class PkVM {
  @Trace windows: PkWindowVM[] = [];
  @Trace focus: number = 0;
  @Trace viewport: number = 360;
  @Trace pickerOpen: boolean = false;
  /** 换股目标窗下标；-1 表示「新增窗」。 */
  @Trace pickerTarget: number = -1;
  @Trace candidates: PkCandidate[] = [];
  @Trace toastCode: PkToastCode | '' = '';
  @Trace toastSeq: number = 0;
  /** 空 PK 页（无参数进入）：显示「选择标的 / 恢复上次对比」。 */
  @Trace emptyState: boolean = false;
  @Trace hasSaved: boolean = false;
  /** 关掉最后一窗 → 由宿主退栈（FR-08.5）。 */
  @Trace exitRequested: boolean = false;
  @Trace candidatesLoading: boolean = false;

  private store: PkStore = PkStore.get();
  private repo: PkRepository = new PkRepository();
  private nextId: number = 1;
  private source: PkEntrySource = 'detail';
  private layoutChecked: boolean = false;

  /** 建立 PK 会话：codes 顺序即窗序，去重后截断到 3（AC-77）。 */
  attach(codes: string[], focus: number, source: PkEntrySource): void {
    this.source = source;
    this.windows = [];
    const saved: PkSavedGroup = this.store.load();
    const seen: Set<string> = new Set<string>();
    const unique: string[] = [];
    for (let i = 0; i < codes.length && unique.length < PK_MAX_WINDOWS; i++) {
      const code: string = codes[i];
      if (code.length === 0 || seen.has(code)) {
        continue;
      }
      seen.add(code);
      unique.push(code);
    }
    for (let i = 0; i < unique.length; i++) {
      const stored: string = saved.periodOf(unique[i]);
      this.windows.push(new PkWindowVM(this.nextId++, unique[i], stored));
    }
    this.focus = clampIndex(focus, this.windows.length);
    this.updateFocusFlags();
    this.emptyState = this.windows.length === 0;
    this.hasSaved = saved.usable();
    this.exitRequested = false;
    this.logEntry();
    this.checkLayout();
    this.persist();
    if (this.windows.length === 1) {
      // 详情入口只带 1 只：自动拉起选择器补齐对比标的（AC-77「单只不进 PK」的可用化处理）。
      this.openPicker(-1);
    }
  }

  /** 空会话（无参数进入 PK 页）：可恢复上一组或自行选择标的。 */
  attachEmpty(): void {
    this.windows = [];
    this.focus = 0;
    this.emptyState = true;
    this.hasSaved = this.store.load().usable();
    this.source = 'detail';
    hilog.info(DOMAIN, TAG, 'pk_entry source=empty');
  }

  updateViewport(width: number): void {
    const next: number = width > 0 ? Math.round(width) : 360;
    if (next === this.viewport) {
      return;
    }
    this.viewport = next;
    this.checkLayout();
  }

  layout(): SlotLayout[] {
    return computeLayout(this.windows.length, this.viewport);
  }

  kind(): PkLayoutKind {
    return this.windows.length >= 3 ? 'deck' : (this.windows.length === 2 ? 'split' : 'single');
  }

  /** 焦点窗 1s、非焦点窗 5s；单窗按普通档（FR-08.7）。 */
  tierOf(index: number): PkWindowTier {
    if (this.windows.length <= 1) {
      return 'normal';
    }
    return index === this.focus ? 'focus' : 'background';
  }

  focusWindow(index: number): void {
    if (index < 0 || index >= this.windows.length || index === this.focus) {
      return;
    }
    this.focus = index;
    this.updateFocusFlags();
    hilog.info(DOMAIN, TAG, 'pk_focus index=%{public}d code=%{public}s',
      index, this.windows[index].code);
    this.persist();
  }

  /** 「+」/空态新增窗：达上限只提示不挤掉已有窗（FR-08.9）。 */
  addWindow(): void {
    if (this.windows.length >= PK_MAX_WINDOWS) {
      this.toast('max_windows');
      hilog.info(DOMAIN, TAG, 'degrade reason=limit windows=%{public}d', this.windows.length);
      return;
    }
    this.openPicker(-1);
  }

  openPicker(index: number): void {
    this.pickerTarget = index;
    this.pickerOpen = true;
    this.candidatesLoading = true;
    this.repo.candidates().then((list: PkCandidate[]): void => {
      this.candidates = list;
      this.candidatesLoading = false;
    }).catch((): void => {
      this.candidates = [];
      this.candidatesLoading = false;
    });
  }

  closePicker(): void {
    this.pickerOpen = false;
    this.pickerTarget = -1;
  }

  /** 换股/新增：目标 code 已被他窗占用时两窗交换（DEC-08-03），不产生重复标的。 */
  pick(code: string): void {
    const target: number = this.pickerTarget;
    this.closePicker();
    if (target < 0) {
      const existing: number = this.indexOfCode(code);
      if (existing >= 0) {
        this.focusWindow(existing);
        this.toast('already_open');
        return;
      }
      if (this.windows.length >= PK_MAX_WINDOWS) {
        this.toast('max_windows');
        return;
      }
      const period: string = this.store.periodOf(code);
      this.windows.push(new PkWindowVM(this.nextId++, code, period));
      this.focus = this.windows.length - 1;
      this.updateFocusFlags();
      this.emptyState = false;
      hilog.info(DOMAIN, TAG, 'window_open index=%{public}d code=%{public}s windows=%{public}d',
        this.focus, code, this.windows.length);
      this.checkLayout();
      this.persist();
      return;
    }
    if (target >= this.windows.length) {
      return;
    }
    const current: PkWindowVM = this.windows[target];
    if (current.code === code) {
      return;
    }
    const other: number = this.indexOfCode(code);
    if (other >= 0 && other !== target) {
      // 交换：两窗的 code 互换、周期各自留在本窗（不复制、不改窗序）。
      const targetCode: string = current.code;
      this.windows[target].code = code;
      this.windows[other].code = targetCode;
      this.windows[target].syncSeq++;
      this.windows[other].syncSeq++;
      hilog.info(DOMAIN, TAG, 'code_swap from=%{public}d to=%{public}d windows=%{public}d',
        target, other, this.windows.length);
      this.toast('swapped');
      this.checkLayout();
      this.persist();
      return;
    }
    this.windows[target].code = code;
    this.windows[target].syncSeq++;
    hilog.info(DOMAIN, TAG, 'code_change index=%{public}d code=%{public}s', target, code);
    this.checkLayout();
    this.persist();
  }

  /**
   * 一次性「同步周期」（FR-08.6）：取焦点窗当前周期广播给全部窗；
   * 各窗仍独立保留缩放/滚动/内容 Tab（禁止同步项）。
   */
  syncPeriods(): void {
    if (this.windows.length === 0) {
      return;
    }
    const period: string = this.windows[this.focus].period;
    if (period.length === 0) {
      return;
    }
    for (let i = 0; i < this.windows.length; i++) {
      this.windows[i].period = period;
      this.windows[i].syncSeq++;
    }
    hilog.info(DOMAIN, TAG, 'period_sync period=%{public}s windows=%{public}d',
      period, this.windows.length);
    this.toast('sync_done');
    this.persist();
  }

  /** 内容侧上报生效周期（换股/用户切周期后），用于同步与持久化。 */
  onPeriodReported(id: number, period: string): void {
    for (let i = 0; i < this.windows.length; i++) {
      if (this.windows[i].id === id) {
        if (this.windows[i].period === period) {
          return;
        }
        this.windows[i].period = period;
        this.persist();
        return;
      }
    }
  }

  closeWindow(index: number): void {
    if (index < 0 || index >= this.windows.length) {
      return;
    }
    const closedCode: string = this.windows[index].code;
    this.windows.splice(index, 1);
    if (this.windows.length === 0) {
      hilog.info(DOMAIN, TAG, 'window_close index=%{public}d code=%{public}s windows=0',
        index, closedCode);
      hilog.info(DOMAIN, TAG, 'exit_pk windows=0 %{public}s', detailSubscriptionStats());
      this.persist();
      this.exitRequested = true;
      return;
    }
    if (index < this.focus) {
      this.focus--;
    } else if (index === this.focus) {
      this.focus = Math.min(index, this.windows.length - 1);
    }
    this.updateFocusFlags();
    hilog.info(DOMAIN, TAG, 'window_close index=%{public}d code=%{public}s windows=%{public}d focus=%{public}d',
      index, closedCode, this.windows.length, this.focus);
    this.checkLayout();
    this.persist();
  }

  /** 降级 1：非焦点窗降频（默认已是 5s，这里做一次显式断言与说明）。 */
  degradeThrottle(): void {
    hilog.info(DOMAIN, TAG, 'degrade reason=throttle windows=%{public}d %{public}s',
      this.windows.length, detailSubscriptionStats());
    this.toast('degrade_throttle');
  }

  /** 降级 2/3：关闭非焦点窗（保留焦点窗），即退化为单窗。 */
  degradeToSingle(): void {
    if (this.windows.length <= 1) {
      this.toast('single_window');
      return;
    }
    const keep: PkWindowVM = this.windows[this.focus];
    this.windows = [keep];
    this.focus = 0;
    this.updateFocusFlags();
    hilog.info(DOMAIN, TAG, 'degrade reason=memory windows=1 code=%{public}s %{public}s',
      keep.code, detailSubscriptionStats());
    this.toast('degrade_close');
    this.checkLayout();
    this.persist();
  }

  /** 恢复上一组（FR-08.8 / DEC-08-05）：失败降级为单窗并提示。 */
  restoreLast(): boolean {
    const saved: PkSavedGroup = this.store.load();
    if (!saved.usable()) {
      this.toast('restore_failed');
      hilog.info(DOMAIN, TAG, 'pk_restore_failed');
      return false;
    }
    const startMs: number = Date.now();
    this.attach(saved.codes, saved.focus, 'detail');
    // 恢复周期：attach 已按 code 从持久化取回（saved.periodOf）。
    this.toast('restored');
    hilog.info(DOMAIN, TAG, 'pk_restore windows=%{public}d ms=%{public}d',
      this.windows.length, Date.now() - startMs);
    return true;
  }

  clearSaved(): void {
    this.store.clear();
    this.hasSaved = false;
  }

  restoreFailed(): void {
    this.toast('restore_failed');
  }

  /** 退出 PK（返回键/关闭最后一窗/⧉ 退出）统一埋点。 */
  logExit(): void {
    hilog.info(DOMAIN, TAG, 'exit_pk windows=%{public}d source=%{public}s',
      this.windows.length, this.source);
  }

  stats(): string {
    return detailSubscriptionStats();
  }

  codeAt(index: number): string {
    return index >= 0 && index < this.windows.length ? this.windows[index].code : '';
  }

  private indexOfCode(code: string): number {
    for (let i = 0; i < this.windows.length; i++) {
      if (this.windows[i].code === code) {
        return i;
      }
    }
    return -1;
  }

  private updateFocusFlags(): void {
    for (let i = 0; i < this.windows.length; i++) {
      this.windows[i].focused = i === this.focus;
    }
  }

  private toast(code: PkToastCode): void {
    this.toastCode = code;
    this.toastSeq++;
  }

  private persist(): void {
    // 单窗不是「对比组合」：不落盘，避免进入 PK（1 窗 + 待补标的）时覆盖上一组（DEC-08-05）。
    if (this.windows.length < 2) {
      return;
    }
    const codes: string[] = [];
    const periods: string[] = [];
    for (let i = 0; i < this.windows.length; i++) {
      codes.push(this.windows[i].code);
      periods.push(this.windows[i].period);
    }
    this.store.save(codes, periods, this.focus);
    this.hasSaved = true;
  }

  private logEntry(): void {
    hilog.info(DOMAIN, TAG, 'pk_entry source=%{public}s windows=%{public}d',
      this.source, this.windows.length);
    hilog.info(DOMAIN, TAG, 'group_created size=%{public}d focus=%{public}d',
      this.windows.length, this.focus);
  }

  /** debug：布局不溢出断言（设计 §5.5.2）。 */
  private checkLayout(): void {
    if (this.windows.length === 0) {
      return;
    }
    const issues: string[] = layoutViolations(this.windows.length, this.viewport);
    if (issues.length === 0) {
      if (!this.layoutChecked) {
        this.layoutChecked = true;
        hilog.info(DOMAIN, TAG, 'pk_layout n=%{public}d vp=%{public}d ok',
          this.windows.length, this.viewport);
      }
      return;
    }
    for (let i = 0; i < issues.length; i++) {
      hilog.error(DOMAIN, TAG, 'pk_layout_violation %{public}s', issues[i]);
    }
  }
}

function clampIndex(index: number, length: number): number {
  if (length <= 0) {
    return 0;
  }
  if (index < 0) {
    return 0;
  }
  return index >= length ? length - 1 : index;
}

/** 视图层可用的布局类型出口（R-07：view 只吃 viewmodel 暴露的类型）。 */
export {
  computeLayout,
  layoutViolations,
  PK_COMPACT_WIDTH,
  PK_DECK_OVERLAP,
  PK_GAP,
  PK_MAX_WINDOWS,
  SlotLayout,
  windowRadius
} from '../repository/PkLayout';
