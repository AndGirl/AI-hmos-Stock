import { AppColor, AppDim } from 'commons_ui';
import { CardVM } from '../viewmodel/CardVM';
import { WatchRowVM } from '../viewmodel/WatchRowVM';
import { CardCell } from './CardCell';

/**
 * 卡片栅格（M8-2/M8-3）：
 * - `Grid` + `columnsTemplate`（1fr 均分）+ `cachedCount` 复用，行数据与列表共享 `WatchRowVM[]`；
 * - 虚线「＋ 添加自选」卡固定在末位（G-4），编辑/多选态由页面关闭；
 * - 锚定：`scrollSeq` 变化时滚到 `scrollToIndex`（与冻结表同一套参数）。
 */
@ComponentV2
export struct CardGrid {
  @Param rows: WatchRowVM[] = [];
  @Param card: CardVM = new CardVM();
  @Param scrollToIndex: number = -1;
  @Param scrollSeq: number = 0;
  @Param selectedCodes: string[] = [];
  @Param selectMode: boolean = false;
  @Param editMode: boolean = false;
  /** 断线置灰（CC-7.6）：整块 55%，不冻结数据语义（冻结由 VM 负责）。 */
  @Param offline: boolean = false;
  /** 调试用：持续等速滚动（帧率采样时提供稳定负载）。 */
  @Param autoScroll: boolean = false;
  @Event onTap: (code: string) => void = (code: string): void => {
  };
  @Event onLongPress: (code: string) => void = (code: string): void => {
  };
  @Event onVisibleIndex: (first: number) => void = (first: number): void => {
  };
  private scroller: Scroller = new Scroller();
  private driveTimer: number = -1;
  private driveDown: boolean = true;

  aboutToAppear(): void {
    this.syncAutoScroll();
  }

  aboutToDisappear(): void {
    this.stopAutoScroll();
  }

  @Monitor('autoScroll')
  onAutoScrollChanged(): void {
    this.syncAutoScroll();
  }

  @Monitor('scrollSeq')
  onScrollRequest(): void {
    if (this.scrollToIndex < 0 || this.scrollToIndex >= this.rows.length) {
      return;
    }
    this.scroller.scrollToIndex(this.scrollToIndex, true, ScrollAlign.START);
  }

  private syncAutoScroll(): void {
    if (this.autoScroll) {
      if (this.driveTimer === -1) {
        this.driveTimer = setInterval((): void => {
          this.driveScrollStep();
        }, 1600);
      }
    } else {
      this.stopAutoScroll();
    }
  }

  private stopAutoScroll(): void {
    if (this.driveTimer !== -1) {
      clearInterval(this.driveTimer);
      this.driveTimer = -1;
    }
  }

  private driveScrollStep(): void {
    if (this.rows.length === 0) {
      return;
    }
    const last: number = this.rows.length - 1;
    if (this.driveDown) {
      this.scroller.scrollToIndex(last, true, ScrollAlign.START);
    } else {
      this.scroller.scrollToIndex(0, true, ScrollAlign.START);
    }
    this.driveDown = !this.driveDown;
  }

  private isSelected(code: string): boolean {
    return this.selectedCodes.indexOf(code) >= 0;
  }

  build() {
    Grid(this.scroller) {
      ForEach(this.rows, (row: WatchRowVM) => {
        GridItem() {
          CardCell({
            row: row,
            minCardH: this.card.minCardH,
            metricCount: this.card.metricCount,
            metricColumns: this.card.metricColumns,
            selectMode: this.selectMode,
            editMode: this.editMode,
            selected: this.isSelected(row.code),
            onTap: (code: string): void => {
              this.onTap(code);
            },
            onLongPress: (code: string): void => {
              this.onLongPress(code);
            }
          })
        }
      }, (row: WatchRowVM) => row.code)
    }
    .id('card_grid')
    .columnsTemplate(this.card.columnTemplate())
    .columnsGap(this.card.gap)
    .rowsGap(this.card.gap)
    .cachedCount(6)
    .padding({
      left: this.card.padding,
      right: this.card.padding,
      top: AppDim.gap8,
      bottom: AppDim.gap8
    })
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
    .opacity(this.offline ? 0.55 : 1)
    .onScrollIndex((first: number, last: number): void => {
      this.onVisibleIndex(first);
    })
    .onAppear(() => {
      // 首帧落位（M8 修 P2）：只认 `scrollToIndex`（切换时由 VM 写好的锚点），
      // 不再额外挂一个会随滚动变化的 `initialIndex` 入参——否则每跨一行都会带上整页重渲染。
      if (this.scrollToIndex > 0 && this.scrollToIndex < this.rows.length) {
        this.scroller.scrollToIndex(this.scrollToIndex, false, ScrollAlign.START);
      }
    })
  }
}
