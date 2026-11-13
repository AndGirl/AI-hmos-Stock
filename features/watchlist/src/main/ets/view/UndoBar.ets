import { AppColor, AppDim } from 'commons_ui';

/**
 * 撤销条（M7-4 / AC-97）：全局单条，位于底栏上方，5s 倒计时结束后不可恢复。
 * 文案与倒计时由 VM 提供，本组件只负责展示与「撤销」事件。
 */
@ComponentV2
export struct UndoBar {
  @Param count: number = 0;
  @Param seconds: number = 0;
  @Event onUndo: () => void = (): void => {
  };

  build() {
    Row() {
      Text($r('app.string.watch_undo_text', `${this.count}`))
        .fontSize(13)
        .fontColor(AppColor.textPrimary)
        .layoutWeight(1)
        .maxLines(1)

      Text(`${this.seconds}s`)
        .fontSize(12)
        .fontColor(AppColor.textSecondary)
        .margin({ right: AppDim.gap12 })

      Text($r('app.string.watch_undo_action'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.accent)
        .height(40)
        .padding({ left: AppDim.gap12, right: AppDim.gap12 })
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.onUndo();
        })
    }
    .width('100%')
    .height(48)
    .padding({ left: AppDim.gap16, right: AppDim.gap8 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppColor.bannerBg)
    .border({ width: { top: 0.5 }, color: AppColor.divider })
  }
}
