import { AppColor, AppDim } from 'commons_ui';
import { emptyMetrics, TableMetrics } from '../viewmodel/WatchlistVM';
import { DIR_DOWN, DIR_UP, WatchRowVM } from '../viewmodel/WatchRowVM';

/** 名称列单行（冻结列）：名称 + 代码 + 停牌/新股标；行为与其他列一致（行高、点击、高亮）。 */
@ComponentV2
export struct NameCell {
  @Param row: WatchRowVM = new WatchRowVM('', '', []);
  @Param metrics: TableMetrics = emptyMetrics();
  @Event onTap: (code: string) => void = () => {
  };
  @Local flashAlpha: number = 0;

  @Monitor('row.quote.flashSeq')
  onFlashChanged(): void {
    this.flashAlpha = 0.16;
    this.getUIContext().animateTo({ duration: 320, curve: Curve.EaseOut }, () => {
      this.flashAlpha = 0;
    });
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
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width(this.metrics.nameWidth)
        .height(this.metrics.rowHeight)
        .backgroundColor(this.flashColor())
        .opacity(this.flashAlpha)

      Column() {
        Text(this.row.name)
          .fontSize(14)
          .fontColor(this.row.suspended ? AppColor.textSecondary : AppColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row() {
          Text(this.row.code)
            .fontSize(11)
            .fontColor(AppColor.textSecondary)
            .maxLines(1)

          if (this.row.suspended) {
            Text($r('app.string.watch_tag_suspended'))
              .fontSize(10)
              .fontColor(AppColor.textSecondary)
              .borderWidth(0.5)
              .borderColor(AppColor.divider)
              .borderRadius(2)
              .padding({ left: 2, right: 2 })
              .margin({ left: AppDim.gap4 })
          }
          if (this.row.isNew) {
            Text($r('app.string.watch_tag_new'))
              .fontSize(10)
              .fontColor(AppColor.priceUp)
              .borderWidth(0.5)
              .borderColor(AppColor.priceUp)
              .borderRadius(2)
              .padding({ left: 2, right: 2 })
              .margin({ left: AppDim.gap4 })
          }
        }
        .margin({ top: 2 })
      }
      .width(this.metrics.nameWidth)
      .height(this.metrics.rowHeight)
      .padding({ left: AppDim.gap12, right: AppDim.gap4 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
    }
    .width(this.metrics.nameWidth)
    .height(this.metrics.rowHeight)
    .border({ width: { bottom: 0.5 }, color: AppColor.divider })
    .opacity(this.row.suspended ? 0.55 : 1)
    .accessibilityText(this.row.accessibilityLabel())
    .onClick(() => {
      this.onTap(this.row.code);
    })
  }
}
