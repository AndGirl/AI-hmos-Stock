import { AppColor } from 'commons_ui';
import { emptyMetrics, TableMetrics } from '../viewmodel/WatchlistVM';
import { DIR_DOWN, DIR_UP, WatchRowVM } from '../viewmodel/WatchRowVM';

const CELL_INDEXES: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

/**
 * 数字区单行：只读 row 的单元格字符串（格式已在 VM 算好）。
 * 变动高亮由 flashSeq 触发一次 320ms 背景渐变；1s 内不重复由 QuoteBus 合窗保证。
 */
@ComponentV2
export struct QuoteRow {
  @Param row: WatchRowVM = new WatchRowVM('', '', []);
  @Param metrics: TableMetrics = emptyMetrics();
  /** 多选比价态：整行浅强调底（与名称列同色，保证跨列视觉一致）。 */
  @Param selectMode: boolean = false;
  @Param selected: boolean = false;
  @Event onTap: (code: string) => void = () => {
  };
  @Event onLongPress: (code: string) => void = () => {
  };
  @Local flashAlpha: number = 0;

  @Monitor('row.quote.flashSeq')
  onFlashChanged(): void {
    this.flashAlpha = 0.16;
    this.getUIContext().animateTo({ duration: 320, curve: Curve.EaseOut }, () => {
      this.flashAlpha = 0;
    });
  }

  private cellColor(index: number): Resource {
    if (index < 3 && this.row.dir !== 0) {
      return this.row.dir === DIR_UP ? AppColor.priceUp : AppColor.priceDown;
    }
    return AppColor.textPrimary;
  }

  private flashColor(): Resource {
    if (this.row.dir === DIR_UP) {
      return AppColor.priceUp;
    }
    if (this.row.dir === DIR_DOWN) {
      return AppColor.priceDown;
    }
    return AppColor.accent;
  }

  build() {
    Stack() {
      Row()
        .width(this.metrics.numericWidth)
        .height(this.metrics.rowHeight)
        .backgroundColor(this.selected ? AppColor.accentSoft : this.flashColor())
        .opacity(this.selected ? 1 : (this.selectMode ? 0.12 : this.flashAlpha))

      Row() {
        ForEach(CELL_INDEXES, (index: number) => {
          Text(this.row.cells[index])
            .width(this.metrics.widths[index + 1])
            .height(this.metrics.rowHeight)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.End)
            .maxLines(1)
            .padding({ right: 4 })
            .fontColor(this.cellColor(index))
        }, (index: number) => `${index}`)
      }
      .width(this.metrics.numericWidth)
      .height(this.metrics.rowHeight)
    }
    .width(this.metrics.numericWidth)
    .height(this.metrics.rowHeight)
    .border({ width: { bottom: 0.5 }, color: AppColor.divider })
    .opacity(this.row.suspended ? 0.55 : 1)
    .accessibilityText(this.row.accessibilityLabel())
    .onClick(() => {
      this.onTap(this.row.code);
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.onLongPress(this.row.code);
        })
    )
  }
}
