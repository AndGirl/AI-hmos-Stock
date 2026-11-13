import { AppColor, AppDim } from 'commons_ui';
import { emptyMetrics, TableMetrics } from '../viewmodel/WatchlistVM';
import { DIR_DOWN, DIR_UP, WatchRowVM } from '../viewmodel/WatchRowVM';

/** 名称列单行（冻结列）：名称 + 代码 + 停牌/新股标；行为与其他列一致（行高、点击、高亮）。 */
@ComponentV2
export struct NameCell {
  @Param row: WatchRowVM = new WatchRowVM('', '', []);
  @Param metrics: TableMetrics = emptyMetrics();
  /** 多选比价态（FR-08.1）：左侧出现选中圈，整行浅强调底。 */
  @Param selectMode: boolean = false;
  /** 编辑模式（M7-5）：同样出现选中圈，但行为是「勾选/移出」。 */
  @Param editMode: boolean = false;
  @Param selected: boolean = false;
  @Event onTap: (code: string) => void = (code: string): void => {
  };
  @Event onLongPress: (code: string) => void = (code: string): void => {
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

  @Builder
  selectMark() {
    Text(this.selected ? '✓' : '')
      .fontSize(13)
      .fontColor(AppColor.textOnAccent)
      .width(20)
      .height(20)
      .textAlign(TextAlign.Center)
      .borderRadius(10)
      .border({
        width: this.selected ? 0 : 1,
        color: this.selected ? AppColor.accent : AppColor.disabledText
      })
      .backgroundColor(this.selected ? AppColor.accent : AppColor.transparent)
      .margin({ right: AppDim.gap8 })
      .accessibilityText(this.selected ? $r('app.string.watch_select_a11y') :
        $r('app.string.watch_select_a11y_off'))
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width(this.metrics.nameWidth)
        .height(this.metrics.rowHeight)
        .backgroundColor(this.selected ? AppColor.accentSoft : this.flashColor())
        .opacity(this.selected ? 1 : ((this.selectMode || this.editMode) ? 0.12 : this.flashAlpha))

      Row() {
        if (this.selectMode || this.editMode) {
          this.selectMark()
        }

        Column() {
          Text(this.row.name)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.row.suspended ? AppColor.textSecondary : AppColor.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Row() {
            Text(this.row.code)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColor.textSecondary)
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
            // 离线加入的自选（M7-7）：标「待同步」，联网后由同步服务清零。
            if (this.row.pending) {
              Text($r('app.string.watch_pending_tag'))
                .fontSize(10)
                .fontColor(AppColor.textSecondary)
                .borderWidth(0.5)
                .borderColor(AppColor.divider)
                .borderRadius(2)
                .padding({ left: 2, right: 2 })
                .margin({ left: AppDim.gap4 })
            }
          }
          .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width(this.metrics.nameWidth)
      .height(this.metrics.rowHeight)
      .padding({
        left: (this.selectMode || this.editMode) ? AppDim.gap8 : AppDim.gap12,
        right: AppDim.gap4
      })
      .alignItems(VerticalAlign.Center)
    }
    .width(this.metrics.nameWidth)
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
