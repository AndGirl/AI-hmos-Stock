import { BarChart, CandleStickChart, LineChart } from '@ohos/mpchart';
import { FrameCallback } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppColor, AppDim } from 'commons_ui';
import {
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
import { DETAIL_BLOCK_HEIGHT } from './DetailLayout';


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

/** 图表首帧探针（AC-65：chart_frame 日志）。 */
class FirstFrameCallback extends FrameCallback {
  private handler: (ns: number) => void;

  constructor(handler: (ns: number) => void) {
    super();
    this.handler = handler;
  }

  onFrame(frameTimeInNano: number): void {
    this.handler(frameTimeInNano);
  }
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
  private reflowToken: number = 0;

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
    // 让待执行的宽度重排落到空处（图表已 dispose）。
    this.reflowToken++;
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

  /**
   * 容器宽度变化（M4 多窗：2↔3 窗重排、折叠/展开）后图表需要重新套用可视范围。
   * mpchart 的缩放/位移是在旧视口尺寸下算的，不重算会出现 K 线聚在右侧、左侧留白。
   * 放在下一帧后执行，确保图表已按新宽度完成布局。
   */
  @Monitor('viewportWidth')
  onViewportChanged(): void {
    this.reflowToken++;
    const token: number = this.reflowToken;
    setTimeout((): void => {
      if (token !== this.reflowToken) {
        return;
      }
      this.reflow();
    }, 80);
  }

  private reflow(): void {
    const series: ChartSeries | null = this.series;
    if (series === null || series.points.length === 0) {
      return;
    }
    this.engine.setSeries(series);
    this.applyZoom();
  }

  private applySeries(): void {
    if (this.series === null) {
      return;
    }
    this.engine.setSeries(this.series);
    this.engine.setCrosshairEnabled(true);
    this.applyZoom();
    this.measureFirstFrame();
  }

  /** 从「数据已就绪」到下一帧回调的耗时（含容器布局与绘制提交）。 */
  private measureFirstFrame(): void {
    const started: number = Date.now();
    const period: ChartPeriod = this.period;
    this.getUIContext().postFrameCallback(new FirstFrameCallback((): void => {
      hilog.info(0x0001, 'DetailPerf', 'chart_frame period=%{public}s ms=%{public}d',
        period, Date.now() - started);
    }));
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

  /** 价格图高度 = 统一列高 − 量能图高度，保证图表区与右侧盘口列等高。 */
  private priceHeight(): number {
    return DETAIL_BLOCK_HEIGHT - this.volumeHeight();
  }

  private volumeHeight(): number {
    return this.compact ? 40 : 52;
  }

  private chartA11y(): string {
    // FR-06.13：图表提供替代文本摘要（不逐点朗读 K 线）。
    return this.textOf($r('app.string.detail_chart_desc')) + ' ' + this.vm.name + ' ' +
      this.textOf(periodLabel(this.period)) + ' ' + this.vm.priceText + ' ' + this.vm.pctText;
  }

  private textOf(res: Resource): string {
    const context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    return context.resourceManager.getStringSync(res);
  }

  @Builder
  chartSkeleton() {
    Column() {
      Row()
        .width('100%')
        .height(DETAIL_BLOCK_HEIGHT)
        .borderRadius(8)
        .backgroundColor(AppColor.disabledBg)
    }
    .width('100%')
    .padding({ left: AppDim.gap16, right: AppDim.gap16 })
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
    .height(DETAIL_BLOCK_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppColor.bgSurface)
    .borderRadius(8)
    .margin({ left: AppDim.gap16, right: AppDim.gap16 })
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
    .backgroundColor(AppColor.bgPage)
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Column() {
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
        .height(DETAIL_BLOCK_HEIGHT)
        .justifyContent(FlexAlign.Center)
      } else {
        // 读数条叠在图表上沿（不上抬整体高度），保证图表区与盘口列始终等高。
        Stack({ alignContent: Alignment.TopStart }) {
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
          .height(DETAIL_BLOCK_HEIGHT)
          .accessibilityText(this.chartA11y())
          .padding({ left: AppDim.gap8, right: AppDim.gap8 })

          if (this.readout !== null) {
            this.readoutBar()
          }
        }
        .width('100%')
        .height(DETAIL_BLOCK_HEIGHT)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: AppDim.gap8 })
  }
}



