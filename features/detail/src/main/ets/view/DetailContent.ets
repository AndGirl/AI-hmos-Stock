import { AppColor, AppDim, StateMode, StateView } from 'commons_ui';
import { BreakpointHost, BreakpointService, ConfigHost, ConfigService, PerfMeter } from 'commons_basic';
import { DEBUG } from '../../../../BuildProfile';
import { DetailAction, DetailMode, DetailVM } from '../viewmodel/DetailVM';
import { QuoteHeader } from './QuoteHeader';
import { MetricPanel } from './MetricPanel';
import { ChartArea } from './ChartArea';
import { OrderBookPanel } from './OrderBookPanel';
import { NewsBar } from './NewsBar';
import { ContentTabs } from './ContentTabs';
import { ActionBar } from './ActionBar';

/**
 * 详情内容组件（FR-06.1）：壳/内容分离的唯一内容实现。
 * INV-D1：不调用路由栈、不建全局 banner、不起重连定时器。
 * 三形态（§5.3.2）：page 全量；pane（xl 右栏）与 window（多窗实例）走紧凑版——
 * 无资讯条、内容 Tab、动作栏，四项动作收进「⋯」。
 */
@ComponentV2
export struct DetailContent {
  @Param code: string = '';
  @Param mode: DetailMode = 'page';
  @Param contentWidth: number = 360;
  @Param bottomInset: number = 0;
  @Event onAction: (action: DetailAction) => void = (action: DetailAction): void => {
  };
  @Event onLoaded: (code: string) => void = (code: string): void => {
  };
  @Local vm: DetailVM = new DetailVM('');
  @Local breakpoint: BreakpointService = BreakpointHost.getService();
  @Local config: ConfigService = ConfigHost.getService();
  @Local perfRunning: boolean = false;

  aboutToAppear(): void {
    this.vm.attach(this.code);
    this.vm.load();
    this.onLoaded(this.code);
  }

  aboutToDisappear(): void {
    if (this.perfRunning) {
      this.perfRunning = false;
      PerfMeter.stop();
    }
    this.vm.dispose();
  }

  /** debug 构建：长按股票名开始/停止帧率采样（命令见进度文档 §6）。 */
  private togglePerf(): void {
    if (!DEBUG) {
      return;
    }
    if (this.perfRunning) {
      this.perfRunning = false;
      PerfMeter.stop();
      return;
    }
    this.perfRunning = true;
    PerfMeter.start(this.getUIContext(),
      'detail-' + this.code + '-' + this.contentWidth.toFixed(0) + 'vp-' + this.mode);
  }

  @Monitor('code')
  onCodeChanged(): void {
    if (this.code.length === 0) {
      return;
    }
    this.vm.dispose();
    this.vm.attach(this.code);
    this.vm.load();
    this.onLoaded(this.code);
  }

  /** pane / window 为紧凑版；page 为全量（INV-D3：window 每实例独立 VM）。 */
  private isCompact(): boolean {
    return this.mode !== 'page';
  }

  private narrowBook(): boolean {
    return this.isCompact() && this.contentWidth < 360;
  }

  private bookWidth(): number {
    const ratio: number = this.isCompact() ? 0.32 : 0.3;
    const max: number = this.isCompact() ? 132 : 170;
    return Math.min(max, Math.max(102, this.contentWidth * ratio));
  }

  private tradeEnabled(): boolean {
    return this.vm.status !== 'suspended' && this.vm.status !== 'delisted';
  }

  @Builder
  skeletonBlock() {
    Column() {
      Row()
        .width('60%')
        .height(22)
        .borderRadius(4)
        .backgroundColor(AppColor.disabledBg)
      Row()
        .width('40%')
        .height(34)
        .borderRadius(4)
        .backgroundColor(AppColor.disabledBg)
        .margin({ top: AppDim.gap12 })
      Row()
        .width('100%')
        .height(96)
        .borderRadius(8)
        .backgroundColor(AppColor.disabledBg)
        .margin({ top: AppDim.gap16 })
      Row()
        .width('100%')
        .height(190)
        .borderRadius(8)
        .backgroundColor(AppColor.disabledBg)
        .margin({ top: AppDim.gap12 })
    }
    .width('100%')
    .padding({ left: AppDim.gap16, right: AppDim.gap16, top: AppDim.gap16 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  chartRow() {
    ChartArea({
      series: this.vm.chartSeries,
      period: this.vm.period,
      chartState: this.vm.chartState,
      compact: this.isCompact(),
      viewportWidth: this.contentWidth,
      vm: this.vm,
      onSelectPeriod: (period): void => {
        this.vm.selectPeriod(period);
      },
      onRetry: (): void => {
        this.vm.retryChart();
      }
    })
  }

  @Builder
  mainContent() {
    Column() {
      QuoteHeader({
        vm: this.vm,
        compact: this.isCompact(),
        onMore: (): void => {
          this.onAction('more');
        },
        onLongPressName: (): void => {
          this.togglePerf();
        }
      })

      MetricPanel({
        metrics: this.vm.metrics,
        expanded: this.vm.metricsExpanded,
        viewportWidth: this.contentWidth,
        fontScale: this.config.fontScale,
        compact: this.isCompact(),
        onToggle: (): void => {
          this.vm.toggleMetrics();
        }
      })

      // 资讯条在 page / pane / window 三种形态都展示（2026-11-12 产品口径，覆盖 FR-06 §2.6「紧凑版不显示」）。
      NewsBar({
        title: this.vm.newsTitle,
        visible: this.vm.newsVisible,
        onClose: (): void => {
          this.vm.dismissNews();
        }
      })

      if (this.narrowBook()) {
        this.chartRow()
        Row() {
          OrderBookPanel({ book: this.vm.orderBook, ticks: this.vm.ticks, narrow: true })
        }
        .width('100%')
        .padding({ left: AppDim.gap16, right: AppDim.gap16, top: AppDim.gap8 })
      } else {
        Row() {
          Column() {
            this.chartRow()
          }
          .layoutWeight(1)

          Column() {
            OrderBookPanel({ book: this.vm.orderBook, ticks: this.vm.ticks, narrow: false })
          }
          .width(this.bookWidth())
          .margin({ right: AppDim.gap12 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }

      if (!this.isCompact()) {
        ContentTabs({ wide: this.contentWidth >= 840 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      if (this.vm.uiState === 'loading') {
        this.skeletonBlock()
      } else if (this.vm.uiState === 'firstLoadError') {
        StateView({
          mode: StateMode.ERROR,
          stateDesc: $r('app.string.detail_load_failed'),
          showAction: true,
          actionLabel: $r('app.string.retry'),
          onAction: (): void => {
            this.vm.retry();
          }
        })
          .width('100%')
          .layoutWeight(1)
      } else if (this.vm.uiState === 'notFound') {
        StateView({
          mode: StateMode.ERROR,
          stateDesc: $r('app.string.detail_not_found_desc'),
          showAction: false
        })
          .width('100%')
          .layoutWeight(1)
      } else {
        if (this.isCompact()) {
          Scroll() {
            this.mainContent()
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .clip(true)
          .align(Alignment.Top)
        } else {
          Column() {
            Scroll() {
              this.mainContent()
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .clip(true)
            .align(Alignment.Top)

            ActionBar({
              tradeEnabled: this.tradeEnabled(),
              onAction: (action: DetailAction): void => {
                this.onAction(action);
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ bottom: this.bottomInset })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bgPage)
  }
}
