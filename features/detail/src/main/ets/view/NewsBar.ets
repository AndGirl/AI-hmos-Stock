import { AppColor, AppDim } from 'commons_ui';

const NEWS_HEIGHT: number = 44;

/**
 * 资讯条（FR-06.5）：单条、可关闭；会话内按 code 记忆（VM 负责）。
 * 样式：白色胶囊（左右留边、圆角 = pill_radius、0.5vp 描边），与页面同底色靠描边区分。
 * 本期只展示 + 关闭，点击不跳转（无资讯模块，避免新增占位口径）。
 */
@ComponentV2
export struct NewsBar {
  @Param title: string = '';
  @Param visible: boolean = false;
  @Event onClose: () => void = () => {
  };

  build() {
    if (this.visible) {
      Column() {
        Row() {
          Text($r('app.string.detail_news_tag'))
            .fontSize(10)
            .fontColor(AppColor.accent)
            .border({ width: 0.5, color: AppColor.accent })
            .borderRadius(3)
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
          Text(this.title)
            .fontSize(12)
            .fontColor(AppColor.textPrimary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: AppDim.gap8 })
          Text('×')
            .fontSize(16)
            .fontColor(AppColor.textSecondary)
            .width(32)
            .height(32)
            .textAlign(TextAlign.Center)
            .accessibilityText($r('app.string.detail_news_close'))
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .height(NEWS_HEIGHT)
        .padding({ left: AppDim.gap12, right: AppDim.gap4 })
        .backgroundColor(AppColor.bgPage)
        .borderRadius(AppDim.pillRadius)
        .border({ width: 0.5, color: AppColor.divider })
        .shadow({ radius: 8, color: AppColor.barShadow, offsetY: 2 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: AppDim.gap16, right: AppDim.gap16, top: AppDim.gap8, bottom: AppDim.gap8 })
      .backgroundColor(AppColor.newsBandBg)
    }
  }
}
