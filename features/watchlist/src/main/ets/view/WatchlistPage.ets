import { AppColor, AppDim, showComingSoon, StateMode, StateView } from 'commons_ui';
import {
  BreakpointHost,
  BreakpointService,
  ComingSoonText,
  ConfigHost,
  ConfigService,
  LayoutConst
} from 'commons_basic';
import { WatchlistVM } from '../viewmodel/WatchlistVM';
import { SortKey } from '../viewmodel/WatchlistVM';
import { IndexStrip } from './IndexStrip';
import { GroupTabs } from './GroupTabs';
import { FrozenTable } from './FrozenTable';

const SKELETON_ROWS: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
const SKELETON_CELLS: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

/**
 * 自选列表页（FR-02）：指数条 + 分组 Tab + 11 列冻结表。
 * 状态：骨架（加载）→ 内容 / 空态 / 失败可重试；单行刷新由 VM 的 @Trace 行对象驱动。
 */
@ComponentV2
export struct WatchlistPage {
  @Param onOpenDetail: (code: string) => void = () => {
  };
  @Local vm: WatchlistVM = new WatchlistVM();
  @Local breakpoint: BreakpointService = BreakpointHost.getService();
  @Local config: ConfigService = ConfigHost.getService();

  aboutToAppear(): void {
    this.syncLayout();
    this.vm.load();
  }

  aboutToDisappear(): void {
    this.vm.dispose();
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
    this.vm.updateLayout(width, this.config.fontScale, this.breakpoint.indexCount);
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

  build() {
    Column() {
      Row() {
        Text($r('app.string.watchlist_title'))
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.textPrimary)
      }
      .width('100%')
      .padding({ left: AppDim.gap16, right: AppDim.gap16, top: AppDim.gap16, bottom: AppDim.gap4 })

      IndexStrip({ items: this.vm.indexItems })

      GroupTabs({
        groups: this.vm.groups,
        onSelect: (id: string): void => {
          this.vm.selectGroup(id);
        }
      })

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
          onSort: (key: SortKey): void => {
            this.vm.cycleSort(key);
          },
          onRowTap: (code: string): void => {
            this.onOpenDetail(code);
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
    .height('100%')
    .padding({ bottom: LayoutConst.TAB_BAR_RESERVED })
    .backgroundColor(AppColor.bgPage)
  }
}
