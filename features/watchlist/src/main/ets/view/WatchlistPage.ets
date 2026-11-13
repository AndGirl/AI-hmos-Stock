import { promptAction } from '@kit.ArkUI';
import { BottomTabBar, AppColor, AppDim, StateMode, StateView } from 'commons_ui';
import {
  BackDispatcher,
  BackHandler,
  BreakpointHost,
  BreakpointService,
  ConfigHost,
  ConfigService,
  ConnectionHost,
  ConnectionHub,
  PerfMeter,
  SafeAreaHost,
  SafeAreaService
} from 'commons_basic';
import { DetailAction, DetailContent, showDetailActionMenu } from 'detail';
import { DEBUG } from '../../../../BuildProfile';
import { GroupEditReason, WATCHLIST_GROUP_NAME_MAX, WatchlistVM } from '../viewmodel/WatchlistVM';
import { SortKey } from '../viewmodel/WatchlistVM';
import { IndexStrip } from './IndexStrip';
import { GroupTabs } from './GroupTabs';
import { FrozenTable } from './FrozenTable';
import { CardGrid } from './CardGrid';
import { ViewSwitch } from './ViewSwitch';
import { CardSortChip } from './CardSortChip';
import { EditBar } from './EditBar';
import { UndoBar } from './UndoBar';
import { GroupManageSheet } from './GroupManageSheet';

const SKELETON_ROWS: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
const SKELETON_CELLS: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
/** 切换视图的淡入时长（AC-103：150ms，无白屏）。 */
const VIEW_FADE_MS: number = 150;

/**
 * 窄窗验证开关：>0 时把 xl 右栏宽度压到该 vp，用于复现 FR-06 §2.6 的 pane <360vp 布局。
 * 真实窄窗由 M4 的多窗宿主创建，本期验证后保持 0。
 */
const NARROW_PANE_TEST_VP: number = 0;

/**
 * 自选列表页（FR-02 / M7）：指数条 + 分组 Tab + 11 列冻结表。
 * 状态：骨架（加载）→ 内容 / 空态 / 失败可重试；单行刷新由 VM 的 @Trace 行对象驱动。
 * M7 新增：底部「添加自选」胶囊、编辑模式（行前勾选 + 移出 + 二次确认）、5s 撤销条、分组管理。
 */
@ComponentV2
export struct WatchlistPage {
  @Param onOpenDetail: (code: string) => void = (code: string): void => {
  };
  @Param onOpenPk: (codes: string[]) => void = (codes: string[]): void => {
  };
  /** 平板 xl 右栏动作栏的「去交易」（§10-83）：弹窗归属窗口，由壳层挂载（INV-T4）。 */
  @Param onOpenTrade: (code: string) => void = (code: string): void => {
  };
  /** 空态「搜索添加」（M6-6）：进全屏搜索页，由壳层装配路由。 */
  @Param onOpenSearch: () => void = (): void => {
  };
  /** 添加自选（M7-7）：`groupId` 为当前分组（作为目标分组默认值），空串表示由板块派生。 */
  @Param onOpenAdd: (groupId: string) => void = (groupId: string): void => {
  };
  /** 详情/右栏「自选设置」（M7-7）：带 code 打开添加页。 */
  @Param onOpenAddForCode: (code: string) => void = (code: string): void => {
  };
  /** xl 分栏时底栏由本页左列承载（§10-83）：当前选中 Tab 与切换回调由壳层注入。 */
  @Param bottomBarIndex: number = 2;
  @Param onSelectBottomTab: (index: number) => void = (index: number): void => {
  };
  @Local vm: WatchlistVM = new WatchlistVM();
  @Local breakpoint: BreakpointService = BreakpointHost.getService();
  @Local config: ConfigService = ConfigHost.getService();
  @Local hub: ConnectionHub = ConnectionHost.getService();
  @Local safeArea: SafeAreaService = SafeAreaHost.getService();
  @Local perfRunning: boolean = false;
  /** 采样时是否让列表/卡片自动滚动（M8-7：静止与滚动两种场景分开采）。 */
  @Local perfAutoScroll: boolean = false;
  /** xl 分栏右栏当前标的（M2：详情 pane 形态，点行只换 code 不路由）。 */
  @Local paneCode: string = '';
  /** 分组管理浮层（M7-6）：页面内 Stack 承载，避免跨窗弹层（INV-T4）。 */
  @Local groupSheet: boolean = false;
  /** 视图切换的淡入透明度（150ms，AC-103）；切换期间不出现白屏。 */
  @Local contentAlpha: number = 1;
  /** 系统返回键（M8，关闭 M7 遗留）：浮层/编辑/多选态先退一层。 */
  private backHandler: BackHandler = (): boolean => this.handleBack();

  aboutToAppear(): void {
    this.syncLayout();
    this.vm.load();
    BackDispatcher.register(this.backHandler);
  }

  aboutToDisappear(): void {
    this.stopPerf();
    BackDispatcher.unregister(this.backHandler);
    this.vm.dispose();
  }

  /**
   * 返回键优先级（M8）：分组管理浮层 → 编辑模式 → 比价多选 → 交给系统。
   * 只在本页所在 Tab 可见时接管（`bottomBarIndex`），否则会吞掉其它 Tab 的返回。
   */
  private handleBack(): boolean {
    if (this.bottomBarIndex !== 2) {
      return false;
    }
    if (this.groupSheet) {
      this.groupSheet = false;
      return true;
    }
    if (this.vm.editMode) {
      this.vm.exitEdit();
      return true;
    }
    if (this.vm.selectMode) {
      this.vm.cancelSelect();
      return true;
    }
    return false;
  }

  /**
   * 调试面板（仅 debug 构建；长按标题触发）：
   * 字号档位、空态/失败态注入、帧率采样、填满至 50（AC-96）、清除视图记忆（M8-4）。
   * release 由 BuildProfile.DEBUG=false 关闭。
   */
  private openDebugMenu(): void {
    if (!DEBUG) {
      return;
    }
    const b0: promptAction.Button = { text: '帧率采样…（静止/滚动）', color: AppColor.debug };
    const b1: promptAction.Button = { text: '字号…', color: AppColor.debug };
    const b2: promptAction.Button = { text: '网络…', color: AppColor.debug };
    const b3: promptAction.Button = { text: '场景…（空态/失败/填满）', color: AppColor.debug };
    const b4: promptAction.Button = { text: '重置（字号 + 网络 + 数据）', color: AppColor.debug };
    const b5: promptAction.Button = { text: '清除视图记忆（回列表）', color: AppColor.debug };
    const buttons: [promptAction.Button, promptAction.Button, promptAction.Button,
      promptAction.Button, promptAction.Button, promptAction.Button] = [b0, b1, b2, b3, b4, b5];
    this.getUIContext().getPromptAction().showActionMenu({
      title: '调试面板（debug）',
      buttons: buttons
    }).then((res: promptAction.ActionMenuSuccessResponse): void => {
      this.onDebugAction(res.index);
    }).catch((): void => {
    });
  }

  private onDebugAction(index: number): void {
    if (index === 0) {
      this.openPerfMenu();
    } else if (index === 1) {
      this.openFontMenu();
    } else if (index === 2) {
      this.openNetMenu();
    } else if (index === 3) {
      this.openSceneMenu();
    } else if (index === 4) {
      ConfigHost.getService().apply(1.0);
      this.vm.applyNetFault('none');
      // 重置：字号/网络恢复，并把自选恢复为 45 只种子
      this.vm.resetAll();
    } else if (index === 5) {
      // 清除视图记忆（M8-4）：删 view_pref_v1 并回列表，用于验收「冷启不闪烁」的重复试验。
      this.vm.debugClearViewPref();
      this.toast('已清除视图记忆，回到列表视图');
    }
  }

  /** 二级：数据场景（M7 验收：空态、失败态、50 上限；M8 追加 200 卡压测）。 */
  private openSceneMenu(): void {
    const stress: boolean = this.vm.stressActive();
    const b0: promptAction.Button = { text: '清空自选（空态）', color: AppColor.debug };
    const b1: promptAction.Button = { text: '模拟加载失败', color: AppColor.debug };
    const b2: promptAction.Button = { text: '填满至 50（AC-96）', color: AppColor.debug };
    const b3: promptAction.Button = {
      text: stress ? '退出卡片压测（恢复真实数据）' : '卡片压测 200（仅卡片态，不落盘）',
      color: AppColor.debug
    };
    const buttons: [promptAction.Button, promptAction.Button, promptAction.Button,
      promptAction.Button] = [b0, b1, b2, b3];
    this.getUIContext().getPromptAction().showActionMenu({ title: '场景', buttons: buttons })
      .then((res: promptAction.ActionMenuSuccessResponse): void => {
        if (res.index === 0) {
          // 真实清空（Store 落盘），不是展示层置空
          this.vm.clearAll();
        } else if (res.index === 1) {
          this.vm.applyMockFault(true);
        } else if (res.index === 2) {
          this.vm.debugFillToLimit();
        } else if (res.index === 3) {
          if (this.vm.stressActive()) {
            this.vm.debugClearStressRows();
            return;
          }
          if (this.vm.viewMode !== 'card') {
            this.toast('请先切到卡片视图再做压测');
            return;
          }
          const count: number = this.vm.debugBuildStressRows();
          this.toast(`已生成 ${count} 张压测卡（不落盘）`);
        }
      }).catch((): void => {
    });
  }

  /** 二级：字号档位（M5-3 端到端用）。 */
  private openFontMenu(): void {
    const b0: promptAction.Button = { text: '1.0×', color: AppColor.debug };
    const b1: promptAction.Button = { text: '1.3×', color: AppColor.debug };
    const b2: promptAction.Button = { text: '1.45×', color: AppColor.debug };
    const buttons: [promptAction.Button, promptAction.Button, promptAction.Button] = [b0, b1, b2];
    this.getUIContext().getPromptAction().showActionMenu({ title: '字号', buttons: buttons })
      .then((res: promptAction.ActionMenuSuccessResponse): void => {
        if (res.index === 0) {
          ConfigHost.getService().apply(1.0);
        } else if (res.index === 1) {
          ConfigHost.getService().apply(1.3);
        } else if (res.index === 2) {
          ConfigHost.getService().apply(1.45);
        }
      }).catch((): void => {
    });
  }

  /** 二级：网络故障（M5-1：weak / offline / delayed / 恢复）。 */
  private openNetMenu(): void {
    const b0: promptAction.Button = { text: '正常', color: AppColor.debug };
    const b1: promptAction.Button = { text: '弱网（weak）', color: AppColor.debug };
    const b2: promptAction.Button = { text: '断线（offline）', color: AppColor.debug };
    const b3: promptAction.Button = { text: '延迟（delayed）', color: AppColor.debug };
    const buttons: [promptAction.Button, promptAction.Button, promptAction.Button,
      promptAction.Button] = [b0, b1, b2, b3];
    this.getUIContext().getPromptAction().showActionMenu({ title: '网络状态', buttons: buttons })
      .then((res: promptAction.ActionMenuSuccessResponse): void => {
        if (res.index === 0) {
          this.vm.applyNetFault('none');
        } else if (res.index === 1) {
          this.vm.applyNetFault('weak');
        } else if (res.index === 2) {
          this.vm.applyNetFault('offline');
        } else if (res.index === 3) {
          this.vm.applyNetFault('delayed');
        }
      }).catch((): void => {
    });
  }

  /** 二级：帧率采样（M8-7：静止 / 自动滚动 / 停止三段，便于 50 卡三场景对比）。 */
  private openPerfMenu(): void {
    const b0: promptAction.Button = { text: '开始（静止，看空转帧率）', color: AppColor.debug };
    const b1: promptAction.Button = { text: '开始（自动滚动）', color: AppColor.debug };
    const b2: promptAction.Button = { text: '停止并输出（PERF_STOP）', color: AppColor.debug };
    const buttons: [promptAction.Button, promptAction.Button, promptAction.Button] = [b0, b1, b2];
    this.getUIContext().getPromptAction().showActionMenu({ title: '帧率采样', buttons: buttons })
      .then((res: promptAction.ActionMenuSuccessResponse): void => {
        if (res.index === 0) {
          this.startPerf(false);
        } else if (res.index === 1) {
          this.startPerf(true);
        } else if (res.index === 2) {
          this.stopPerf();
        }
      }).catch((): void => {
    });
  }

  private startPerf(autoScroll: boolean): void {
    if (this.perfRunning) {
      this.stopPerf();
    }
    this.perfAutoScroll = autoScroll;
    this.perfRunning = true;
    const view: string = this.vm.stressActive() ? 'card-stress' : this.vm.viewMode;
    const label: string =
      `watchlist-${view}-${this.breakpoint.widthBp}-${this.cardRowCount()}rows-${this.config.fontScale}x-${autoScroll ? 'scroll' : 'static'}`;
    PerfMeter.start(this.getUIContext(), label);
  }

  private stopPerf(): void {
    if (!this.perfRunning) {
      return;
    }
    this.perfRunning = false;
    this.perfAutoScroll = false;
    PerfMeter.stop();
  }

  private cardRowCount(): number {
    return this.vm.viewMode === 'card' ? this.vm.cardRows().length : this.vm.rowCount;
  }

  @Monitor('breakpoint.viewportWidth')
  onViewportChanged(): void {
    this.syncLayout();
  }

  /** Tab 切回自选时补一次 Store 重读（覆盖页面隐藏期间漏掉的变更）。 */
  @Monitor('bottomBarIndex')
  onAppTabChanged(): void {
    if (this.bottomBarIndex === 2) {
      this.vm.resume();
    }
  }

  @Monitor('config.fontScale')
  onFontScaleChanged(): void {
    this.syncLayout();
  }

  /** 联网后待同步清零：提示一次（M7-7 / AC-96），提示后清计数以允许下一次再提示。 */
  @Monitor('vm.syncedCount')
  onPendingSynced(): void {
    if (this.vm.syncedCount > 0) {
      this.toast($r('app.string.watch_synced_toast', `${this.vm.syncedCount}`));
      this.vm.syncedCount = 0;
    }
  }

  /** 列表可用宽：sm/md/lg 单列全宽（屏宽 − 32 内边距）；xl 取左栏 523vp（设计 §5.2.9）。
   * 卡片视图在 xl 走整宽（见 `splitPane`），因此卡片几何按屏宽算、由 `CardMetrics` 自行扣 32 内边距。
   */
  private syncLayout(): void {
    const screenWidth: number = this.breakpoint.viewportWidth > 0 ? this.breakpoint.viewportWidth : 360;
    const width: number = this.breakpoint.isSplit ? 523 : Math.max(200, screenWidth - 32);
    this.vm.updateLayout(width, this.config.fontScale);
    this.vm.updateCardLayout(screenWidth, this.breakpoint.widthBp, this.config.fontScale);
  }

  /**
   * xl 是否保留右侧详情栏（M8 口径）：只有**列表视图**分栏；
   * 卡片视图在 xl 需要 5 列（AC-100），左栏 523vp 放不下 → 卡片视图整宽、右栏让位。
   */
  private splitPane(): boolean {
    return this.breakpoint.isSplit && this.vm.viewMode === 'list';
  }

  private paneWidth(): number {
    if (NARROW_PANE_TEST_VP > 0) {
      return NARROW_PANE_TEST_VP;
    }
    const screenWidth: number = this.breakpoint.viewportWidth > 0 ? this.breakpoint.viewportWidth : 1180;
    return Math.max(320, screenWidth - 523);
  }

  /** 右栏标的：用户点过的优先，否则取列表首行（xl 默认有内容）。 */
  private effectivePaneCode(): string {
    if (this.paneCode.length > 0) {
      return this.paneCode;
    }
    return this.vm.rows.length > 0 ? this.vm.rows[0].code : '';
  }

  private openRow(code: string): void {
    if (this.splitPane()) {
      this.paneCode = code;
      return;
    }
    this.onOpenDetail(code);
  }

  /**
   * 视图切换（M8-3 / AC-103）：VM 侧节流 + 保状态，视图侧 150ms 淡入。
   * 锚点用右栏当前标的（xl），无右栏时 VM 回退到选中项/上次首行。
   */
  private toggleView(): void {
    const ok: boolean = this.vm.toggleViewMode(this.splitPane() ? this.paneCode : '');
    if (!ok) {
      return;
    }
    this.contentAlpha = 0.05;
    this.getUIContext().animateTo({ duration: VIEW_FADE_MS, curve: Curve.EaseOut }, () => {
      this.contentAlpha = 1;
    });
  }

  /**
   * 行点击优先级（M7-5）：编辑态 = 勾选（不跳详情）> 比价多选 = 切换选中 > 常规 = 进详情/右栏。
   * M8：卡片压测期间（合成 code 不在服务端）一律不响应。
   */
  private handleRowTap(code: string): void {
    if (this.vm.stressActive()) {
      return;
    }
    if (this.vm.editMode) {
      this.vm.toggleEditSelect(code);
      return;
    }
    if (!this.vm.selectMode) {
      this.openRow(code);
      return;
    }
    if (!this.vm.toggleSelect(code)) {
      this.toast($r('app.string.watch_select_max'));
    }
  }

  private handleRowLongPress(code: string): void {
    if (this.vm.stressActive()) {
      return;
    }
    // 编辑态里长按与点击等价，避免和「勾选」两套语义打架。
    if (this.vm.editMode) {
      this.vm.toggleEditSelect(code);
      return;
    }
    this.enterSelect(code);
  }

  /** 排序 chip 点本体：复用列头的循环（降序→升序→取消），不新增排序态（CK-2）。 */
  private cycleCardSort(): void {
    const key: SortKey | null = this.vm.sortKey;
    if (key === null) {
      return;
    }
    this.vm.cycleSort(key);
  }

  private enterSelect(code: string): void {
    if (!this.vm.enterSelect(code)) {
      this.toast($r('app.string.watch_select_max'));
    }
  }

  /** 比价：少于 2 只不进 PK（FR-08.1「至少选择 2 只」）。 */
  private confirmSelect(): void {
    const codes: string[] | null = this.vm.confirmSelect();
    if (codes === null) {
      this.toast($r('app.string.watch_select_min'));
      return;
    }
    this.onOpenPk(codes);
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
  }

  /** 添加自选：当前分组作为目标分组默认值（「全部」不预置，交给板块派生）。 */
  private openAdd(): void {
    const groupId: string = this.vm.selectedGroupId === 'all' ? '' : this.vm.selectedGroupId;
    this.onOpenAdd(groupId);
  }

  /** 编辑模式「移出」二次确认（AC-98）。 */
  private confirmRemoveSelected(): void {
    if (this.vm.editSelected.length === 0) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.watch_remove_confirm'),
      message: $r('app.string.watch_remove_confirm_desc'),
      primaryButton: {
        value: $r('app.string.watch_select_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.watch_edit_remove_all'),
        action: (): void => {
          this.vm.removeEditSelected();
        }
      }
    });
  }

  /** 分组展示名（弹窗标题用）：用户组用 name，遗留 `user` 组与系统组走 i18n（View 负责中文）。 */
  private groupNameOf(id: string): string {
    for (let i = 0; i < this.vm.groups.length; i++) {
      const group = this.vm.groups[i];
      if (group.id !== id) {
        continue;
      }
      if (group.name.length > 0) {
        return group.name;
      }
      break;
    }
    return this.stringOf(this.groupLabelRes(id));
  }

  /** 取资源字符串（异步能力不可用/异常时回落空串，不阻塞确认框）。 */
  private stringOf(res: Resource): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      if (ctx === undefined) {
        return '';
      }
      return ctx.resourceManager.getStringSync(res.id);
    } catch (err) {
      return '';
    }
  }

  private groupLabelRes(id: string): Resource {
    if (id === 'user') {
      return $r('app.string.watch_group_user');
    }
    if (id === 'fin') {
      return $r('app.string.watch_group_fin');
    }
    if (id === 'star') {
      return $r('app.string.watch_group_star');
    }
    if (id === 'kcb') {
      return $r('app.string.watch_group_kcb');
    }
    return $r('app.string.watch_group_all');
  }

  /** 删除分组二次确认（AC-99）：提示「只删归属不删股票」。 */
  private confirmDeleteGroup(id: string): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.group_delete_confirm', this.groupNameOf(id)),
      message: $r('app.string.group_delete_desc'),
      primaryButton: {
        value: $r('app.string.group_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.group_delete'),
        action: (): void => {
          this.vm.deleteGroup(id).then((reason: GroupEditReason): void => {
            this.toast(this.groupReasonText(reason, 'deleted'));
          });
        }
      }
    });
  }

  /** 分组编辑结论 → 文案（VM 只回枚举，中文留在 View）。 */
  private groupReasonText(reason: GroupEditReason, ok: string): ResourceStr {
    if (reason === 'limit') {
      return $r('app.string.group_limit');
    }
    if (reason === 'empty') {
      return $r('app.string.group_name_empty');
    }
    if (reason === 'too_long') {
      return $r('app.string.group_name_too_long');
    }
    if (reason === 'emoji') {
      return $r('app.string.group_name_emoji');
    }
    if (reason === 'duplicate') {
      return $r('app.string.group_name_duplicate');
    }
    if (reason === 'system_readonly') {
      return $r('app.string.group_readonly');
    }
    if (ok === 'created') {
      return $r('app.string.group_created', this.groupSheetNewName);
    }
    if (ok === 'renamed') {
      return $r('app.string.group_renamed');
    }
    if (ok === 'deleted') {
      return $r('app.string.group_deleted');
    }
    return $r('app.string.add_failed');
  }

  /** 新建成功提示要带组名：由 sheet 的上抛参数暂存。 */
  private groupSheetNewName: string = '';

  private handleCreateGroup(name: string): void {
    this.groupSheetNewName = name;
    this.vm.createGroup(name).then((reason: GroupEditReason): void => {
      this.toast(this.groupReasonText(reason, 'created'));
    });
  }

  private handleRenameGroup(id: string, name: string): void {
    this.groupSheetNewName = name;
    this.vm.renameGroup(id, name).then((reason: GroupEditReason): void => {
      this.toast(this.groupReasonText(reason, 'renamed'));
    });
  }

  private handlePaneAction(code: string, action: DetailAction): void {
    if (action === 'watchlist') {
      this.onOpenAddForCode(code);
      return;
    }
    if (action === 'pk') {
      this.onOpenPk([code]);
      return;
    }
    if (action === 'more') {
      showDetailActionMenu(this.getUIContext(), true, (picked: DetailAction): void => {
        this.handlePaneAction(code, picked);
      });
      return;
    }
    // 平板 xl 右栏动作栏的「去交易」（§10-83）：交给壳层开窗，弹窗不跨窗（FR-07.11）。
    if (action === 'trade') {
      this.onOpenTrade(code);
      return;
    }
  }

  /**
   * 自选全空引导（2026-11-13 需求变更，M7 调整主按钮）：
   * 主按钮从「去行情加自选」换成「添加自选」（M7 已落地添加页），文字链保留「搜索添加」。
   */
  @Builder
  emptyGuide() {
    Column() {
      Image($r('app.media.ic_tab_watchlist'))
        .width(64)
        .height(64)
        .fillColor(AppColor.textSecondary)
        .opacity(0.35)

      Text($r('app.string.watch_empty_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textPrimary)
        .margin({ top: AppDim.gap16 })

      Text($r('app.string.watch_empty_desc'))
        .fontSize(13)
        .fontColor(AppColor.textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .margin({ top: AppDim.gap8, left: AppDim.gap24, right: AppDim.gap24 })

      Text($r('app.string.watch_add_entry'))
        .fontSize(15)
        .fontColor(AppColor.textOnAccent)
        .height(44)
        .padding({ left: AppDim.gap24, right: AppDim.gap24 })
        .textAlign(TextAlign.Center)
        .backgroundColor(AppColor.accent)
        .borderRadius(AppDim.pillRadius)
        .margin({ top: AppDim.gap24 })
        .accessibilityText($r('app.string.watch_add_entry'))
        .onClick(() => {
          this.openAdd();
        })

      Text($r('app.string.empty_watchlist_action_search'))
        .fontSize(13)
        .fontColor(AppColor.textSecondary)
        .height(44)
        .padding({ left: AppDim.gap12, right: AppDim.gap12 })
        .textAlign(TextAlign.Center)
        .margin({ top: AppDim.gap8 })
        .onClick(() => {
          this.onOpenSearch();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  skeleton() {
    Column() {
      ForEach(SKELETON_ROWS, (rowIndex: number) => {
        Row() {
          Row()
            .width(112)
            .height(14)
            .borderRadius(4)
            .backgroundColor(AppColor.disabledBg)
            .margin({ left: AppDim.gap12 })
          ForEach(SKELETON_CELLS, (cellIndex: number) => {
            Row()
              .width(56)
              .height(12)
              .borderRadius(4)
              .backgroundColor(AppColor.disabledBg)
              .margin({ left: AppDim.gap12 })
          }, (cellIndex: number) => `${rowIndex}-${cellIndex}`)
        }
        .width('100%')
        .height(56)
        .alignItems(VerticalAlign.Center)
      }, (rowIndex: number) => `s${rowIndex}`)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: AppDim.gap16, top: AppDim.gap8 })
  }

  @Builder
  selectBar() {
    Row() {
      Column() {
        Text($r('app.string.watch_select_count', this.vm.selectedCodes.length.toString()))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
        Text($r('app.string.watch_select_hint'))
          .fontSize(11)
          .fontColor(AppColor.textSecondary)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text($r('app.string.watch_select_cancel'))
        .fontSize(14)
        .fontColor(AppColor.textSecondary)
        .height(40)
        .padding({ left: AppDim.gap12, right: AppDim.gap12 })
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.vm.cancelSelect();
        })
      Text($r('app.string.watch_select_pk'))
        .fontSize(15)
        .fontColor(AppColor.textOnAccent)
        .height(40)
        .width(96)
        .textAlign(TextAlign.Center)
        .backgroundColor(AppColor.accent)
        .borderRadius(AppDim.pillRadius)
        .margin({ left: AppDim.gap8 })
        .onClick(() => {
          this.confirmSelect();
        })
    }
    .width('100%')
    .height(60)
    .padding({ left: AppDim.gap16, right: AppDim.gap16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppColor.bgSurface)
    .border({ width: { top: 0.5 }, color: AppColor.divider })
  }

  /** 底部「添加自选」胶囊（M7-7 E1）：列表滚动区之外、底栏之上。 */
  @Builder
  addCapsule() {
    Row() {
      Text($r('app.string.watch_add_entry'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textOnAccent)
        .height(40)
        .padding({ left: AppDim.gap24, right: AppDim.gap24 })
        .textAlign(TextAlign.Center)
        .backgroundColor(AppColor.accent)
        .borderRadius(AppDim.pillRadius)
        .accessibilityText($r('app.string.watch_add_entry'))
        .onClick(() => {
          this.openAdd();
        })
    }
    .width('100%')
    .height(52)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppColor.bgPage)
  }

  @Builder
  hDivider() {
    Divider()
      .strokeWidth(1)
      .color(AppColor.dividerStrong)
      .width('100%')
  }

  /** 分组管理浮层：底部半屏 + 遮罩，点遮罩关闭（M7-6）。 */
  @Builder
  groupManageOverlay() {
    Column() {
      Column()
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(AppColor.scrim)
        .onClick(() => {
          this.groupSheet = false;
        })

      GroupManageSheet({
        groups: this.vm.groups,
        nameMax: WATCHLIST_GROUP_NAME_MAX,
        onCreate: (name: string): void => {
          this.handleCreateGroup(name);
        },
        onRename: (id: string, name: string): void => {
          this.handleRenameGroup(id, name);
        },
        onDelete: (id: string): void => {
          this.confirmDeleteGroup(id);
        },
        onClose: (): void => {
          this.groupSheet = false;
        }
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          if (this.vm.editMode) {
            Text($r('app.string.watch_select_count', this.vm.editSelected.length.toString()))
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColor.textPrimary)
            Blank()
            Text($r('app.string.watch_edit_done'))
              .fontSize(14)
              .fontColor(AppColor.accent)
              .height(32)
              .padding({ left: AppDim.gap8, right: AppDim.gap8 })
              .onClick(() => {
                this.vm.exitEdit();
              })
          } else if (this.vm.selectMode) {
            Text($r('app.string.watch_select_count', this.vm.selectedCodes.length.toString()))
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColor.textPrimary)
            Blank()
            Text($r('app.string.watch_select_cancel'))
              .fontSize(13)
              .fontColor(AppColor.textSecondary)
              .height(32)
              .padding({ left: AppDim.gap8, right: AppDim.gap8 })
              .onClick(() => {
                this.vm.cancelSelect();
              })
          } else {
            Text($r('app.string.watchlist_title'))
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColor.textPrimary)
              .layoutWeight(1)
            // M7-5/M7-6 入口：编辑 / 管理（分组栏右侧留给 M8 的卡片切换与排序）。
            if (this.vm.state !== 'loading' && this.vm.emptyKind !== 'all') {
              Text($r('app.string.watch_manage'))
                .fontSize(13)
                .fontColor(AppColor.textSecondary)
                .height(32)
                .padding({ left: AppDim.gap8, right: AppDim.gap8 })
                .onClick(() => {
                  this.groupSheet = true;
                })
              Text($r('app.string.watch_edit'))
                .fontSize(13)
                .fontColor(AppColor.textSecondary)
                .height(32)
                .padding({ left: AppDim.gap8, right: AppDim.gap8 })
                .onClick(() => {
                  this.vm.toggleEdit();
                })
            }
          }
        }
        .width('100%')
        .padding({ left: AppDim.gap16, right: AppDim.gap16, top: AppDim.gap16, bottom: AppDim.gap4 })
        .alignItems(VerticalAlign.Center)
        .gesture(
          LongPressGesture({ repeat: false })
            .onAction(() => {
              this.openDebugMenu();
            })
        )

        Row() {
          Column() {
            // 自选全空时指数条/分组页签/视图切换/排序全无意义，整段隐藏，只留引导式空态。
            if (this.vm.emptyKind !== 'all') {
              // 分组为空时指数条也没有条目，只留「推荐」卡会显得空荡，一并隐藏。
              if (this.vm.rowCount > 0) {
                IndexStrip({
                  source: this.vm.indexBarSource(),
                  version: this.vm.stripVersion
                })

                this.hDivider()
              }

              // 分组栏 + 视图切换（M8-3）：切换按钮取代原「卡片」文字占位。
              Row() {
                GroupTabs({
                  groups: this.vm.groups,
                  onSelect: (id: string): void => {
                    this.vm.selectGroup(id);
                  },
                  onLongPress: (id: string): void => {
                    // 长按分组 = 进分组管理（M7-6），并停在该分组上下文里。
                    this.groupSheet = true;
                  }
                })
                  .layoutWeight(1)

                ViewSwitch({
                  mode: this.vm.viewMode,
                  onToggle: (): void => {
                    this.toggleView();
                  }
                })
                  .margin({ right: AppDim.gap8 })
              }
              .width('100%')
              .height(40)
              .alignItems(VerticalAlign.Center)

              this.hDivider()

              // 排序 chip（M8-5 / AC-102）：与列表列头共用同一个 SortState，卡片态才展示；无排序时隐藏。
              if (this.vm.viewMode === 'card' && this.vm.sortKey !== null && this.vm.sortDir !== 'none') {
                Row() {
                  CardSortChip({
                    sortKey: this.vm.sortKey,
                    sortDir: this.vm.sortDir,
                    onCycle: (): void => {
                      this.cycleCardSort();
                    },
                    onClear: (): void => {
                      this.vm.clearSort();
                    }
                  })
                }
                .width('100%')
                .height(34)
                .alignItems(VerticalAlign.Center)
              }
            }

            // 内容区：加载/错误/空态与列表共用；内容分支按视图形态切换（M8-3 淡入）。
            Column() {
              if (this.vm.state === 'loading') {
                this.skeleton()
              } else if (this.vm.state === 'error') {
                StateView({
                  mode: StateMode.ERROR,
                  stateDesc: $r('app.string.watch_list_failed'),
                  showAction: true,
                  actionLabel: $r('app.string.retry'),
                  onAction: (): void => {
                    this.vm.retry();
                  }
                })
                  .width('100%')
                  .layoutWeight(1)
              } else if (this.vm.emptyKind === 'all') {
                this.emptyGuide()
              } else if (this.vm.state === 'empty') {
                // 分组为空但自选有票：只提示换分组，不复用「暂无自选」（2026-11-13）。
                StateView({
                  mode: StateMode.EMPTY,
                  stateDesc: $r('app.string.watch_group_empty_desc'),
                  showAction: true,
                  actionLabel: $r('app.string.watch_group_empty_action'),
                  iconRes: $r('app.media.ic_tab_watchlist'),
                  onAction: (): void => {
                    this.vm.selectGroup('all');
                  }
                })
                  .width('100%')
                  .layoutWeight(1)
              } else if (this.vm.viewMode === 'card') {
                CardGrid({
                  rows: this.vm.cardRows(),
                  card: this.vm.card,
                  scrollToIndex: this.vm.scrollIndex,
                  scrollSeq: this.vm.scrollSeq,
                  selectedCodes: this.vm.editMode ? this.vm.editSelected : this.vm.selectedCodes,
                  selectMode: this.vm.selectMode,
                  editMode: this.vm.editMode,
                  offline: this.hub.state === 'offline',
                  autoScroll: this.perfRunning && this.perfAutoScroll,
                  onTap: (code: string): void => {
                    this.handleRowTap(code);
                  },
                  onLongPress: (code: string): void => {
                    this.handleRowLongPress(code);
                  },
                  onVisibleIndex: (first: number): void => {
                    this.vm.onCardIndex(first);
                  }
                })
              } else {
                FrozenTable({
                  rows: this.vm.rows,
                  metrics: this.vm.metrics,
                  sortKey: this.vm.sortKey,
                  sortDir: this.vm.sortDir,
                  initialVOffset: this.vm.vOffset,
                  initialHOffset: this.vm.hOffset,
                  scrollToIndex: this.vm.scrollIndex,
                  scrollSeq: this.vm.scrollSeq,
                  autoScroll: this.perfRunning && this.perfAutoScroll,
                  selectMode: this.vm.selectMode,
                  editMode: this.vm.editMode,
                  selectedCodes: this.vm.editMode ? this.vm.editSelected : this.vm.selectedCodes,
                  offline: this.hub.state === 'offline',
                  delayed: this.hub.state === 'delayed',
                  onSort: (key: SortKey): void => {
                    this.vm.cycleSort(key);
                  },
                  onRowTap: (code: string): void => {
                    this.handleRowTap(code);
                  },
                  onRowLongPress: (code: string): void => {
                    this.handleRowLongPress(code);
                  },
                  onScrollY: (offset: number): void => {
                    this.vm.onVerticalOffset(offset);
                  },
                  onScrollX: (offset: number): void => {
                    this.vm.onHorizontalOffset(offset);
                  }
                })
              }
            }
            .width('100%')
            .layoutWeight(1)
            .opacity(this.contentAlpha)

            // 底部胶囊（M7-7 E1）：常规态才出现（编辑/多选态有各自的底栏）；
            // 分组空态也保留，便于直接补股票。
            if (!this.vm.editMode && !this.vm.selectMode && this.vm.state !== 'loading' &&
              this.vm.state !== 'error' && this.vm.emptyKind !== 'all') {
              this.addCapsule()
            }

            if (this.vm.selectMode) {
              this.selectBar()
            }

            if (this.vm.editMode) {
              EditBar({
                count: this.vm.editSelected.length,
                allSelected: this.vm.isAllSelected(),
                onSelectAll: (): void => {
                  this.vm.selectAllRows();
                },
                onCancel: (): void => {
                  this.vm.exitEdit();
                },
                onRemove: (): void => {
                  this.confirmRemoveSelected();
                }
              })
            }

            // 撤销条（M7-4）：底栏上方，全局单条。
            if (this.vm.undoVisible) {
              UndoBar({
                count: this.vm.undoCount,
                seconds: this.vm.undoLeft,
                onUndo: (): void => {
                  this.vm.undoRemove();
                }
              })
            }

            // xl 分栏：底栏收进左列，右栏（含动作栏）才能贴到窗口底部（§10-83 / 设计稿）。
            if (this.breakpoint.isSplit) {
              BottomTabBar({
                currentIndex: this.bottomBarIndex,
                bottomInset: this.safeArea.bottomInset,
                onSelect: (index: number): void => {
                  this.onSelectBottomTab(index);
                }
              })
            }
          }
          .width(this.splitPane() ? 523 : '100%')
          .height('100%')

          if (this.splitPane()) {
            // xl 右栏：详情 pane 形态（与 page 共用 DetailContent，compact 打开）。
            Column() {
              if (this.effectivePaneCode().length > 0) {
                DetailContent({
                  code: this.effectivePaneCode(),
                  mode: 'pane',
                  contentWidth: this.paneWidth(),
                  bottomInset: this.safeArea.bottomInset,
                  onAction: (action: DetailAction): void => {
                    this.handlePaneAction(this.effectivePaneCode(), action);
                  }
                })
              } else {
                StateView({
                  mode: StateMode.EMPTY,
                  stateDesc: $r('app.string.empty_watchlist_desc')
                })
                  .width('100%')
                  .height('100%')
              }
            }
            .height('100%')
            .width(this.paneWidth())
            .border({ width: { left: 0.5 }, color: AppColor.divider })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Top)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColor.bgPage)

      if (this.groupSheet) {
        this.groupManageOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }
}
