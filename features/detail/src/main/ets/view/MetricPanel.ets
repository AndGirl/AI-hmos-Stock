import { AppColor, AppDim } from 'commons_ui';
import { MetricVM, visibleMetricCount } from '../viewmodel/DetailVM';
import { metricLabel, toneColor } from './DetailLabels';

/**
 * 指标面板（FR-06.4）：12 项固定池，按断点展示 6/9/12，展开后全 12。
 * 字号每升一档列数减 1（下限 1 列），只降列不截断（CC-6.5）。
 */
@ComponentV2
export struct MetricPanel {
  @Param metrics: MetricVM[] = [];
  @Param expanded: boolean = false;
  @Param viewportWidth: number = 360;
  @Param fontScale: number = 1;
  @Param compact: boolean = false;
  @Event onToggle: () => void = () => {
  };

  private columns(): number {
    const base: number = this.compact ? 2 :
      (this.viewportWidth >= 1180 ? 4 : (this.viewportWidth >= 600 ? 3 : 2));
    const reduce: number = this.fontScale >= 1.45 ? 2 : (this.fontScale >= 1.3 ? 1 : 0);
    return Math.max(1, base - reduce);
  }

  private visibleMetrics(): MetricVM[] {
    const count: number = this.compact ? (this.expanded ? 12 : 6) :
      visibleMetricCount(this.viewportWidth, this.expanded);
    return this.metrics.slice(0, count);
  }

  private itemWidth(): string {
    return (100 / this.columns()).toFixed(4) + '%';
  }

  private showToggle(): boolean {
    if (this.compact) {
      return true;
    }
    if (this.viewportWidth >= 1180 && this.expanded) {
      return false;
    }
    return this.metrics.length > this.visibleMetrics().length || this.expanded;
  }

  build() {
    Column() {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.visibleMetrics(), (metric: MetricVM) => {
          Column() {
            Text(metricLabel(metric.key))
              .fontSize(11)
              .fontColor(AppColor.textSecondary)
              .maxLines(1)
            if (metric.isLoss) {
              Text($r('app.string.detail_pe_loss'))
                .fontSize(13)
                .fontColor(AppColor.textPrimary)
                .margin({ top: 2 })
            } else {
              Text(metric.text)
                .fontSize(13)
                .fontColor(toneColor(metric.tone))
                .margin({ top: 2 })
                .maxLines(1)
            }
          }
          .width(this.itemWidth())
          .alignItems(HorizontalAlign.Start)
          .padding({ top: AppDim.gap4, bottom: AppDim.gap4 })
        }, (metric: MetricVM) => metric.key)
      }
      .width('100%')

      if (this.showToggle()) {
        Row() {
          Text(this.expanded ? $r('app.string.detail_metric_collapse') :
            $r('app.string.detail_metric_expand'))
            .fontSize(11)
            .fontColor(AppColor.textSecondary)
          Text(this.expanded ? '∧' : '∨')
            .fontSize(11)
            .fontColor(AppColor.textSecondary)
            .margin({ left: AppDim.gap2 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .height(24)
        .onClick(() => {
          this.onToggle();
        })
      }
    }
    .width('100%')
    .padding({ left: AppDim.gap16, right: AppDim.gap16, bottom: AppDim.gap4 })
  }
}
