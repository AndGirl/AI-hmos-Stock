import { AppColor, AppDim, StateMode, StateView } from 'commons_ui';

/**
 * 搜索的异常 / 空态（M6-4 / G-1 + G2-1）：
 * - 无结果：图标位 + 「没有找到相关股票」+ 3 个热搜建议词（点击即搜），不放第二个按钮；
 * - 失败：单一「重试」；
 * - 429：文案 + 3s 倒计时，倒计时结束才可重试。
 */
@ComponentV2
export struct SearchStatesView {
  @Param state: string = 'empty';
  @Param suggestions: string[] = [];
  @Param cooldownLeft: number = 0;
  @Event onRetry: () => void = (): void => {
  };
  @Event onPick: (text: string) => void = (text: string): void => {
  };

  @Builder
  iconPlaceholder() {
    Image($r('app.media.ic_placeholder'))
      .width(64)
      .height(64)
      .fillColor(AppColor.textSecondary)
      .opacity(0.35)
      .margin({ bottom: AppDim.gap12 })
  }

  build() {
    Column() {
      if (this.state === 'empty') {
        this.iconPlaceholder()
        Text($r('app.string.search_empty_title'))
          .fontSize(13)
          .fontColor(AppColor.textSecondary)
        if (this.suggestions.length > 0) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            ForEach(this.suggestions, (word: string) => {
              Text(word)
                .fontSize(13)
                .fontColor(AppColor.accent)
                .height(30)
                .padding({ left: AppDim.gap12, right: AppDim.gap12 })
                .backgroundColor(AppColor.fieldBg)
                .borderRadius(15)
                .margin({ left: AppDim.gap4, right: AppDim.gap4, top: AppDim.gap12 })
                .onClick(() => {
                  this.onPick(word);
                })
            }, (word: string) => word)
          }
          .width('100%')
          .padding({ left: AppDim.gap24, right: AppDim.gap24 })
        }
      } else if (this.state === 'error') {
        StateView({
          mode: StateMode.ERROR,
          stateDesc: $r('app.string.search_failed_title'),
          showAction: true,
          actionLabel: $r('app.string.retry'),
          onAction: (): void => {
            this.onRetry();
          }
        })
          .width('100%')
          .height('100%')
      } else if (this.state === 'rateLimited') {
        this.iconPlaceholder()
        Text($r('app.string.search_rate_limited'))
          .fontSize(13)
          .fontColor(AppColor.textSecondary)
        if (this.cooldownLeft > 0) {
          Text($r('app.string.search_rate_countdown', this.cooldownLeft.toString()))
            .fontSize(13)
            .fontColor(AppColor.textSecondary)
            .margin({ top: AppDim.gap12 })
        } else {
          Button($r('app.string.retry'))
            .height(AppDim.touchMin)
            .padding({ left: AppDim.gap24, right: AppDim.gap24 })
            .backgroundColor(AppColor.accent)
            .fontColor(AppColor.textOnAccent)
            .fontSize(14)
            .margin({ top: AppDim.gap12 })
            .onClick(() => {
              this.onRetry();
            })
        }
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
