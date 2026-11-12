import { AppColor, AppDim } from 'commons_ui';
import { CHART_PERIODS, ChartPeriod } from '../viewmodel/DetailExports';
import { periodLabel } from './DetailLabels';

/** 周期 Tab 的最小点击宽度与行高（2 字标签 + 留白，点击区 ≥44vp 方便手指点选）。 */
const TAB_MIN_WIDTH: number = 56;
const TAB_HEIGHT: number = 44;

/**
 * 8 周期 Tab（FR-06.6）：List + ForEach 横向滑动、不折叠下拉；
 * 每个 Tab 至少 56vp 宽、44vp 高，手指点选更稳；行宽跟随内容区（page 全宽、pane 右栏宽）。
 */
@ComponentV2
export struct PeriodTabs {
  @Param period: ChartPeriod = 'timeline';
  @Param viewportWidth: number = 360;
  @Event onSelect: (period: ChartPeriod) => void = (period: ChartPeriod): void => {
  };
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.scrollSelectedIntoView(false);
  }

  @Monitor('period')
  onPeriodChanged(): void {
    this.scrollSelectedIntoView(true);
  }

  /** 选中周期滚动到可见区域（恢复上次周期时避免停在最右被裁切）。 */
  private scrollSelectedIntoView(smooth: boolean): void {
    const index: number = CHART_PERIODS.indexOf(this.period);
    if (index >= 0) {
      this.scroller.scrollToIndex(index, smooth, ScrollAlign.CENTER);
    }
  }

  /** 间距：sm 12 / md 14 / lg 16 / xl 20（FR-06.6）；空间富余时均匀铺开（对齐设计稿的等距排布）。 */
  private tabGap(): number {
    const base: number = this.baseGap();
    const available: number = Math.max(0, this.viewportWidth - 32);
    const content: number = CHART_PERIODS.length * TAB_MIN_WIDTH;
    const extra: number = available - content;
    if (extra <= 0) {
      return base;
    }
    return Math.max(base, extra / (CHART_PERIODS.length - 1));
  }

  private baseGap(): number {
    if (this.viewportWidth >= 1180) {
      return 20;
    }
    if (this.viewportWidth >= 840) {
      return 16;
    }
    if (this.viewportWidth >= 600) {
      return 14;
    }
    return 12;
  }

  build() {
    List({ space: this.tabGap(), scroller: this.scroller }) {
      ForEach(CHART_PERIODS, (value: ChartPeriod) => {
        ListItem() {
          Row() {
            Text(periodLabel(value))
              .fontSize(13)
              .fontColor(value === this.period ? AppColor.accent : AppColor.textSecondary)
              .fontWeight(value === this.period ? FontWeight.Medium : FontWeight.Normal)
              .maxLines(1)
          }
          .constraintSize({ minWidth: TAB_MIN_WIDTH })
          .height(TAB_HEIGHT)
          .padding({ left: AppDim.gap4, right: AppDim.gap4 })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        }
        .onClick(() => {
          this.onSelect(value);
        })
      }, (value: ChartPeriod) => value)
    }
    .listDirection(Axis.Horizontal)
    .height(TAB_HEIGHT)
    .width('100%')
    .scrollBar(BarState.Off)
    .padding({ left: AppDim.gap16, right: AppDim.gap16 })
  }
}
