import { AppColor, AppDim } from 'commons_ui';

/** 占位 Tab 的统一空态页：标题 + 说明 + 统一灰色图标位，不含第二个按钮。 */
@ComponentV2
export struct PlaceholderPage {
  @Param pageTitle: ResourceStr = '';
  @Param pageDesc: ResourceStr = '';

  build() {
    Column() {
      Image($r('app.media.ic_placeholder'))
        .width(72)
        .height(72)
        .fillColor(AppColor.textSecondary)
        .opacity(0.35)
        .margin({ bottom: AppDim.gap16 })

      Text(this.pageTitle)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textPrimary)

      Text(this.pageDesc)
        .fontSize(13)
        .fontColor(AppColor.textSecondary)
        .margin({ top: AppDim.gap8 })
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(AppColor.bgPage)
  }
}
