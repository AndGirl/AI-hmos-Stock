import { BarChart, CandleStickChart, LineChart } from '@ohos/mpchart';
import { common } from '@kit.AbilityKit';
import { AppColor, AppDim } from 'commons_ui';
import {
  CHART_PERIODS,
  ChartPeriod,
  ChartSelectionListener,
  ChartSeries,
  ChartStyle,
  MpChartEngine,
  createChartEngine,
  isKlinePeriod
} from '../viewmodel/DetailExports';
import { ChartReadout, ChartState, DetailVM } from '../viewmodel/DetailVM';
import { periodLabel } from './DetailLabels';

/** 十字光标读数桥（把引擎回调转成组件本地状态）。 */
class ReadoutBridge implements ChartSelectionListener {
  private pick: (index: number) => void;
  private drop: () => void;

  constructor(pick: (index: number) => void, drop: () => void) {
    this.pick = pick;
    this.drop = drop;
  }

  onSelect(index: number): void {
    this.pick(index);
  }

  onClear(): void {
    this.drop();
  }
}

/** 空配色占位：真正配色在 aboutToAppear 由主题 token 解析后注入。 */
function emptyStyle(): ChartStyle {
  return new ChartStyle(0, 0, 0, 0, 0, 0, 0, 0);
}

/**
 * 图表区（FR-06.6 / 06.7）：8 周期 Tab（List + ForEach 横滑，间距随断点）、
 * 点击即刷新、长按十字光标、K 线缩放拖动（分时禁用）、局部失败重试。
 * 容器固定高度，切周期只换 series，不重建布局。
 */
@ComponentV2
export struct ChartArea {
  @Param series: ChartSeries | null = null;
  @Param period: ChartPeriod = 'timeline';
  @Param chartState: ChartState = 'idle';
  @Param compact: boolean = false;
  @Param viewportWidth: number = 360;
  @Param vm: DetailVM = new DetailVM('');
  @Event onSelectPeriod: (period: ChartPeriod) => void = (period: ChartPeriod): void => {
  };
  @Event onRetry: () => void = (): void => {
  };
  @Local readout: ChartReadout | null = null;
  private engine: MpChartEngine = createChartEngine(emptyStyle());
  private tabScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.engine.setStyle(this.resolveStyle());
    this.engine.setSelectionListener(new ReadoutBridge((index: number): void => {
      this.readout = this.vm.readoutAt(index);
    }, (): void => {
      this.readout = null;
    }));
    this.applySeries();
  }

  aboutToDisappear(): void {
    this.engine.dispose();
  }

  @Monitor('series')
  onSeriesChanged(): void {
    this.applySeries();
  }

  @Monitor('period')
  onPeriodChanged(): void {
    this.applyZoom();
  }

  private applySeries(): void {
    if (this.series === null) {
      return;
    }
    this.engine.setSeries(this.series);
    this.engine.setCrosshairEnabled(true);
    this.applyZoom();
  }

  private applyZoom(): void {
    this.engine.setZoomEnabled(this.isKline());
    this.engine.resetZoomFor(this.period);
  }

  private isKline(): boolean {
    return isKlinePeriod(this.period);
  }

  private resolveStyle(): ChartStyle {
    const context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return emptyStyle();
    }
    const rm = context.resourceManager;
    return new ChartStyle(
      rm.getColorSync(AppColor.priceUp),
      rm.getColorSync(AppColor.priceDown),
      rm.getColorSync(AppColor.priceFlat),
      rm.getColorSync(AppColor.priceUp),
      rm.getColorSync(AppColor.chartAvg),
      rm.getColorSync(AppColor.divider),
      rm.getColorSync(AppColor.textSecondary),
      rm.getColorSync(AppColor.priceUp)
    );
  }

  /** 周期 Tab 间距：sm 12 / md 14 / lg 16 / xl 20（FR-06.6）。 */
  private tabGap(): number {
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

  private priceHeight(): number {
    if (this.compact) {
      return 150;
    }
    return this.viewportWidth >= 840 ? 220 : 190;
  }

  private volumeHeight(): number {
    return this.compact ? 40 : 52;
  }

  private chartA11y(): string {
    return 'chart ' + this.vm.name + ' ' + this.period + ' ' + this.vm.priceText + ' ' + this.vm.pctText;
  }

  @Builder
  periodTabs() {
    List({ space: this.tabGap(), scroller: this.tabScroller }) {
      ForEach(CHART_PERIODS, (period: ChartPeriod) => {
        ListItem() {
          Text(periodLabel(period))
            .fontSize(13)
            .fontColor(period === this.period ? AppColor.accent : AppColor.textSecondary)
            .fontWeight(period === this.period ? FontWeight.Medium : FontWeight.Normal)
            .padding({ top: 6, bottom: 6 })
        }
        .onClick(() => {
          this.onSelectPeriod(period);
        })
      }, (period: ChartPeriod) => period)
    }
    .listDirection(Axis.Horizontal)
    .height(34)
    .width('100%')

    .scrollBar(BarState.Off)
    .padding({ left: AppDim.gap16, right: AppDim.gap16 })
  }

  @Builder
  chartSkeleton() {
    Column() {
      Row()
        .width('100%')
        .height(this.priceHeight())
        .borderRadius(8)
        .backgroundColor(AppColor.disabledBg)
    }
    .width('100%')
    .padding({ left: AppDim.gap16, right: AppDim.gap16, top: AppDim.gap8 })
  }

  @Builder
  chartError() {
    Row() {
      Text($r('app.string.detail_chart_failed'))
        .fontSize(13)
        .fontColor(AppColor.textSecondary)
      Text($r('app.string.retry'))
        .fontSize(13)
        .fontColor(AppColor.accent)
        .margin({ left: AppDim.gap12 })
        .onClick(() => {
          this.onRetry();
        })
    }
    .width('100%')
    .height(this.priceHeight())
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppColor.bgSurface)
    .borderRadius(8)
    .margin({ left: AppDim.gap16, right: AppDim.gap16, top: AppDim.gap8 })
  }

  @Builder
  readoutBar() {
    Row() {
      Text(this.readout !== null ? this.readout.timeText : '')
        .fontSize(11)
        .fontColor(AppColor.textPrimary)
      Text(this.readout !== null ? this.readout.priceText : '')
        .fontSize(11)
        .fontColor(AppColor.textPrimary)
        .margin({ left: AppDim.gap8 })
      if (this.readout !== null && this.readout.avgText.length > 0) {
        Text($r('app.string.detail_readout_avg'))
          .fontSize(10)
          .fontColor(AppColor.textSecondary)
          .margin({ left: AppDim.gap8 })
        Text(this.readout.avgText)
          .fontSize(11)
          .fontColor(AppColor.chartAvg)
          .margin({ left: 2 })
      }
      Text($r('app.string.detail_readout_volume'))
        .fontSize(10)
        .fontColor(AppColor.textSecondary)
        .margin({ left: AppDim.gap8 })
      Text(this.readout !== null ? this.readout.volumeText : '')
        .fontSize(11)
        .fontColor(AppColor.textPrimary)
        .margin({ left: 2 })
      Text(this.readout !== null ? this.readout.pctText : '')
        .fontSize(11)
        .fontColor(AppColor.textPrimary)
        .margin({ left: AppDim.gap8 })
    }
    .width('100%')
    .height(22)
    .padding({ left: AppDim.gap16, right: AppDim.gap16 })
  }

  build() {
    Column() {
      this.periodTabs()

      if (this.chartState === 'loading' || this.chartState === 'idle') {
        this.chartSkeleton()
      } else if (this.chartState === 'error') {
        this.chartError()
      } else if (this.series === null || this.series.points.length === 0) {
        Row() {
          Text($r('app.string.detail_chart_empty'))
            .fontSize(13)
            .fontColor(AppColor.textSecondary)
        }
        .width('100%')
        .height(this.priceHeight())
        .justifyContent(FlexAlign.Center)
      } else {
        if (this.readout !== null) {
          this.readoutBar()
        }
        Column() {
          if (this.isKline()) {
            CandleStickChart({ model: this.engine.candlePriceModel() })
              .width('100%')
              .height(this.priceHeight())
          } else {
            LineChart({ model: this.engine.priceModel() })
              .width('100%')
              .height(this.priceHeight())
          }
          BarChart({ model: this.engine.volumeBarModel() })
            .width('100%')
            .height(this.volumeHeight())
        }
        .width('100%')
        .height(this.priceHeight() + this.volumeHeight())
        .accessibilityText(this.chartA11y())
        .padding({ left: AppDim.gap8, right: AppDim.gap8 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: AppDim.gap8 })
  }
}
