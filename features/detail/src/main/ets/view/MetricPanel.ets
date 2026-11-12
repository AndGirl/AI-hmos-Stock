import { AppColor, AppDim } from 'commons_ui';
import { MetricVM, visibleMetricCount } from '../viewmodel/DetailVM';
import { metricLabel, toneColor } from './DetailLabels';

const ROW_HEIGHT: number = 22;
/** 展开按钮点击区 ≥ 44vp（touch_min），chevron 本身 18vp。 */
const TOGGLE_HEIGHT: number = 44;
const CHEVRON_SIZE: number = 22;

/**
 * 指标面板（FR-06.4）：12 项固定池，按断点展示 6 / 9 / 12 项，超出部分用居中 chevron 展开到 12。
 * 版式对齐设计稿（直板机-详情页）：每格「标签左 / 数值右」，列间 0.5vp 分隔线；
 * 字号每升一档只减列、不缩字不截断（CC-6.5），展开态显示全部 12 项。
 */
@ComponentV2
export struct MetricPanel {
  @Param metrics: MetricVM[] = [];
  @Param expanded: boolean = false;
  @Param viewportWidth: number = 360;
  @Param fontScale: number = 1;
  @Param compact: boolean = false;
  @Event onToggle: () => void = (): void => {
  };

  /** 列数：sm 2 / md·lg 3 / xl 4（紧凑版 2）；字号每升一档减 1，下限 1。 */
  private columns(): number {
    const base: number = this.compact ? 2 :
      (this.viewportWidth >= 1180 ? 4 : (this.viewportWidth >= 600 ? 3 : 2));
    const reduce: number = this.fontScale >= 1.45 ? 2 : (this.fontScale >= 1.3 ? 1 : 0);
    return Math.max(1, base - reduce);
  }

  /** 收起态展示项数：sm 6 / md·lg 9 / xl 12（紧凑版 6）。 */
  private collapsedCount(): number {
    if (this.compact) {
      return 6;
    }
    return visibleMetricCount(this.viewportWidth, false);
  }

  private shownCount(): number {
    return this.expanded ? this.metrics.length : this.collapsedCount();
  }

  private visibleMetrics(): MetricVM[] {
    return this.metrics.slice(0, this.shownCount());
  }

  /**
   * 行优先二维数组，但取值按「先列后行」：设计稿里每一列是一组（今开/昨收/换手率、最高/最低/市盈率…），
   * 因此同一列内自上而下取优先级序，再从左到右换列。
   */
  private metricRows(): MetricVM[][] {
    const cols: number = this.columns();
    const list: MetricVM[] = this.visibleMetrics();
    const rowsPerCol: number = Math.ceil(list.length / cols);
    const rows: MetricVM[][] = [];
    for (let r = 0; r < rowsPerCol; r++) {
      const row: MetricVM[] = [];
      for (let c = 0; c < cols; c++) {
        const index: number = c * rowsPerCol + r;
        if (index < list.length) {
          row.push(list[index]);
        }
      }
      if (row.length > 0) {
        rows.push(row);
      }
    }
    return rows;
  }

  /** 当前断点是否隐藏了指标（sm/md/lg 为 true，xl 展示满 12 项为 false）。 */
  private hasOverflow(): boolean {
    return this.metrics.length > this.collapsedCount();
  }

  /** 新开详情页时：当前断点若已展示全部 12 项（xl），不显示 chevron；有超出项才显示。 */
  private showChevron(): boolean {
    return this.hasOverflow();
  }

  private chevronAngle(): number {
    return this.expanded ? 180 : 0;
  }

  /** 行 key 必须随「行内容」变化：否则 ForEach 复用旧行节点，展开时会残留收起态的单元格。 */
  private rowKey(row: MetricVM[]): string {
    let key: string = 'mrow';
    for (let i = 0; i < row.length; i++) {
      key += '-' + row[i].key;
    }
    return key;
  }

  build() {
    Column() {
      ForEach(this.metricRows(), (row: MetricVM[], rowIndex: number) => {
        Row() {
          ForEach(row, (cell: MetricVM, cellIndex: number) => {
            Row() {
              Text(metricLabel(cell.key))
                .fontSize(11)
                .fontColor(AppColor.textSecondary)
                .maxLines(1)
              Blank()
              if (cell.isLoss) {
                Text($r('app.string.detail_pe_loss'))
                  .fontSize(13)
                  .fontColor(AppColor.textPrimary)
                  .maxLines(1)
              } else {
                Text(cell.text)
                  .fontSize(13)
                  .fontColor(toneColor(cell.tone))
                  .maxLines(1)
              }
            }
            .layoutWeight(1)
            .height(ROW_HEIGHT)
            .padding({ left: AppDim.gap12, right: AppDim.gap12 })
            .border({
              width: { right: cellIndex < row.length - 1 ? 0.5 : 0 },
              color: AppColor.divider
            })
            .accessibilityGroup(true)
          }, (cell: MetricVM) => cell.key)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }, (row: MetricVM[], rowIndex: number) => this.rowKey(row))

      if (this.showChevron()) {
        Row() {
          Image($r('app.media.ic_chevron'))
            .width(CHEVRON_SIZE)
            .height(CHEVRON_SIZE)
            .fillColor(AppColor.textSecondary)
            .rotate({ angle: this.chevronAngle() })
        }
        .width('100%')
        .height(TOGGLE_HEIGHT)
        .justifyContent(FlexAlign.Center)
        .accessibilityText(this.expanded ? $r('app.string.detail_metric_collapse') :
          $r('app.string.detail_metric_expand'))
        .onClick(() => {
          this.onToggle();
        })
      }
    }
    .width('100%')
    .padding({ left: AppDim.gap16, right: AppDim.gap16, top: AppDim.gap4, bottom: AppDim.gap4 })
  }
}
