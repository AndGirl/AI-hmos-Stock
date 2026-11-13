import { promptAction } from '@kit.ArkUI';
import { AppColor, AppDim, showComingSoon, StateMode, StateView } from 'commons_ui';
import {
  BreakpointHost,
  BreakpointService,
  ComingSoonText,
  ConfigHost,
  ConfigService,
  ConnectionHost,
  ConnectionHub,
  PerfMeter
} from 'commons_basic';
import { DetailAction, DetailContent, showDetailActionMenu } from 'detail';
import { DEBUG } from '../../../../BuildProfile';
import { WatchlistVM } from '../viewmodel/WatchlistVM';
import { SortKey } from '../viewmodel/WatchlistVM';
import { IndexStrip } from './IndexStrip';
import { GroupTabs } from './GroupTabs';
import { FrozenTable } from './FrozenTable';

const SKELETON_ROWS: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
const SKELETON_CELLS: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

/** 调试面板按钮色（非产品 UI，不走主题 token；面板本身 release 不展示）。 */
const DEBUG_BTN_COLOR: string = '#E84026';

/**
 * 窄窗验证开关：>0 时把 xl 右栏宽度压到该 vp，用于复现 FR-06 §2.6 的 pane <360vp 布局。
 * 真实窄窗由 M4 的多窗宿主创建，本期验证后保持 0。
 */
const NARROW_PANE_TEST_VP: number = 0;

/**
 * 自选列表页（FR-02）：指数条 + 分组 Tab + 11 列冻结表。
 * 状态：骨架（加载）→ 内容 / 空态 / 失败可重试；单行刷新由 VM 的 @Trace 行对象驱动。
 */
@ComponentV2
export struct WatchlistPage {
  @Param onOpenDetail: (code: string) => void = () => {
  };
  @Param onOpenPk: (codes: string[]) => void = () => {
  };
  @Local vm: WatchlistVM = new WatchlistVM();
  @Local breakpoint: BreakpointService = BreakpointHost.getService();
  @Local config: ConfigService = ConfigHost.getService();
  @Local hub: ConnectionHub = ConnectionHost.getService();
  @Local perfRunning: boolean = false;
  /** xl 分栏右栏当前标的（M2：详情 pane 形态，点行只换 code 不路由）。 */
  @Local paneCode: string = '';

  aboutToAppear(): void {
    this.syncLayout();
    this.vm.load();
  }

  aboutToDisappear(): void {
    if (this.perfRunning) {
      this.perfRunning = false;
      PerfMeter.stop();
    }
    this.vm.dispose();
  }

  /**
   * 调试面板（仅 debug 构建；长按标题触发）：
   * 字号档位、空态/失败态注入、帧率采样。release 由 BuildProfile.DEBUG=false 关闭。
   */
  private openDebugMenu(): void {
    if (!DEBUG) {
      return;
    }
    const b0: promptAction.Button = {
      text: this.perfRunning ? '停止帧率采样' : '开始帧率采样（自动滚动）',
      color: DEBUG_BTN_COLOR
    };
    const b1: promptAction.Button = { text: '字号…', color: DEBUG_BTN_COLOR };
    const b2: promptAction.Button = { text: '网络…', color: DEBUG_BTN_COLOR };
    const b3: promptAction.Button = { text: '清空自选（空态）', color: DEBUG_BTN_COLOR };
    const b4: promptAction.Button = { text: '模拟加载失败', color: DEBUG_BTN_COLOR };
    const b5: promptAction.Button = { text: '重置（字号 + 网络 + 数据）', color: DEBUG_BTN_COLOR };
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
      this.togglePerf();
    } else if (index === 1) {
      this.openFontMenu();
    } else if (index === 2) {
      this.openNetMenu();
    } else if (index === 3) {
      this.vm.applyMockFault(true, false);
    } else if (index === 4) {
      this.vm.applyMockFault(false, true);
    } else if (index === 5) {
      ConfigHost.getService().apply(1.0);
      this.vm.applyNetFault('none');
      this.vm.applyMockFault(false, false);
    }
  }

  /** 二级：字号档位（M5-3 端到端用）。 */
  private openFontMenu(): void {
    const b0: promptAction.Button = { text: '1.0×', color: DEBUG_BTN_COLOR };
    const b1: promptAction.Button = { text: '1.3×', color: DEBUG_BTN_COLOR };
    const b2: promptAction.Button = { text: '1.45×', color: DEBUG_BTN_COLOR };
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
    const b0: promptAction.Button = { text: '正常', color: DEBUG_BTN_COLOR };
    const b1: promptAction.Button = { text: '弱网（weak）', color: DEBUG_BTN_COLOR };
    const b2: promptAction.Button = { text: '断线（offline）', color: DEBUG_BTN_COLOR };
    const b3: promptAction.Button = { text: '延迟（delayed）', color: DEBUG_BTN_COLOR };
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

  private togglePerf(): void {
    if (this.perfRunning) {
      this.perfRunning = false;
      PerfMeter.stop();
      return;
    }
    this.perfRunning = true;
    const label: string = `watchlist-${this.breakpoint.widthBp}-${this.vm.rowCount}rows-${this.config.fontScale}x`;
    PerfMeter.start(this.getUIContext(), label);
  }

  @Monitor('breakpoint.viewportWidth')
  onViewportChanged(): void {
    this.syncLayout();
  }

  @Monitor('config.fontScale')
  onFontScaleChanged(): void {
    this.syncLayout();
  }

  /** 列表可用宽：sm/md/lg 单列全宽（屏宽 − 32 内边距）；xl 取左栏 523vp（设计 §5.2.9）。 */
  private syncLayout(): void {
    const screenWidth: number = this.breakpoint.viewportWidth > 0 ? this.breakpoint.viewportWidth : 360;
    const width: number = this.breakpoint.isSplit ? 523 : Math.max(200, screenWidth - 32);
    this.vm.updateLayout(width, this.config.fontScale);
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
    if (this.breakpoint.isSplit) {
      this.paneCode = code;
      return;
    }
    this.onOpenDetail(code);
  }

  /** 多选态下点行 = 切换选中（FR-08.1 第三入口）；达 3 只上限提示不加入。 */
  private handleRowTap(code: string): void {
    if (!this.vm.selectMode) {
      this.openRow(code);
      return;
    }
    if (!this.vm.toggleSelect(code)) {
      this.toast($r('app.string.watch_select_max'));
    }
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

  private handlePaneAction(code: string, action: DetailAction): void {
    if (action === 'watchlist') {
      showComingSoon(this.getUIContext(), ComingSoonText.ADD_WATCHLIST);
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
    // pane（xl 右栏）不提供交易入口（FR-07.11 / AC-75）：不再有 trade 分支。
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

  @Builder
  hDivider() {
    Divider()
      .strokeWidth(1)
      .color(AppColor.dividerStrong)
      .width('100%')
  }

  build() {
    Column() {
      Row() {
        if (this.vm.selectMode) {
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
        }
      }
      .width('100%')
      .padding({ left: AppDim.gap16, right: AppDim.gap16, top: AppDim.gap16, bottom: AppDim.gap4 })
      .gesture(
        LongPressGesture({ repeat: false })
          .onAction(() => {
            this.openDebugMenu();
          })
      )

      Row() {
        Column() {
          IndexStrip({
            source: this.vm.indexBarSource(),
            version: this.vm.stripVersion
          })

          this.hDivider()

      GroupTabs({
        groups: this.vm.groups,
        onSelect: (id: string): void => {
          this.vm.selectGroup(id);
        }
      })

      this.hDivider()

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
      } else if (this.vm.state === 'empty') {
        StateView({
          mode: StateMode.EMPTY,
          stateDesc: $r('app.string.empty_watchlist_desc'),
          showAction: true,
          actionLabel: $r('app.string.action_add_watchlist'),
          onAction: (): void => {
            showComingSoon(this.getUIContext(), ComingSoonText.ADD_WATCHLIST);
          }
        })
          .width('100%')
          .layoutWeight(1)
      } else {
        FrozenTable({
          rows: this.vm.rows,
          metrics: this.vm.metrics,
          sortKey: this.vm.sortKey,
          sortDir: this.vm.sortDir,
          initialVOffset: this.vm.vOffset,
          initialHOffset: this.vm.hOffset,
          autoScroll: this.perfRunning,
          selectMode: this.vm.selectMode,
          selectedCodes: this.vm.selectedCodes,
          offline: this.hub.state === 'offline',
          delayed: this.hub.state === 'delayed',
          onSort: (key: SortKey): void => {
            this.vm.cycleSort(key);
          },
          onRowTap: (code: string): void => {
            this.handleRowTap(code);
          },
          onRowLongPress: (code: string): void => {
            this.enterSelect(code);
          },
          onScrollY: (offset: number): void => {
            this.vm.onVerticalOffset(offset);
          },
          onScrollX: (offset: number): void => {
            this.vm.onHorizontalOffset(offset);
          }
        })
        }

          if (this.vm.selectMode) {
            this.selectBar()
          }
        }
        .width(this.breakpoint.isSplit ? 523 : '100%')
        .height('100%')

        if (this.breakpoint.isSplit) {
          // xl 右栏：详情 pane 形态（与 page 共用 DetailContent，compact 打开）。
          Column() {
            if (this.effectivePaneCode().length > 0) {
              DetailContent({
                code: this.effectivePaneCode(),
                mode: 'pane',
                contentWidth: this.paneWidth(),
                bottomInset: 0,
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
  }
}
