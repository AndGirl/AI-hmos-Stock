import { AppColor, AppDim } from '../theme/TokenRegistry';

/** 页面级状态视图的三种形态：加载 / 空 / 失败（骨架 Skeleton 在 M1 单独实现）。 */
export enum StateMode {
  LOADING = 0,
  EMPTY = 1,
  ERROR = 2
}

/**
 * 通用状态视图：加载指示 / 图标位 + 说明 + 可选单一操作。
 * 规则：
 * - 空态除说明外最多一个操作入口，不放置第二个按钮（基线 §4.1 规则 6）；
 * - 失败态操作即「重试」，retrying 为 true 时按钮内显示 loading 并禁用。
 */
@ComponentV2
export struct StateView {
  @Param mode: StateMode = StateMode.EMPTY;
  @Param stateDesc: ResourceStr = '';
  @Param showAction: boolean = false;
  @Param actionLabel: ResourceStr = '';
  @Param retrying: boolean = false;
  /** 图标位可替换：默认统一灰占位图；自选空态等页面可传自己的语义图标（2026-11-13）。 */
  @Param iconRes: Resource = $r('app.media.ic_placeholder');
  @Event onAction: () => void = () => {
  };

  build() {
    Column() {
      if (this.mode === StateMode.LOADING) {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(AppColor.accent)

        Text($r('app.string.loading'))
          .fontSize(13)
          .fontColor(AppColor.textSecondary)
          .margin({ top: AppDim.gap8 })
      } else {
        Image(this.iconRes)
          .width(64)
          .height(64)
          .fillColor(AppColor.textSecondary)
          .opacity(0.35)
          .margin({ bottom: AppDim.gap12 })

        Text(this.stateDesc)
          .fontSize(13)
          .fontColor(AppColor.textSecondary)
          .textAlign(TextAlign.Center)
          .margin({ left: AppDim.gap24, right: AppDim.gap24 })

        if (this.showAction) {
          Button() {
            Row() {
              if (this.retrying) {
                LoadingProgress()
                  .width(16)
                  .height(16)
                  .color(AppColor.textSecondary)
                  .margin({ right: AppDim.gap8 })
              }

              Text(this.actionLabel)
                .fontSize(14)
                .fontColor(AppColor.textSecondary)
            }
            .justifyContent(FlexAlign.Center)
          }
          .height(AppDim.touchMin)
          .padding({ left: AppDim.gap24, right: AppDim.gap24 })
          .backgroundColor(AppColor.transparent)
          .borderWidth(1)
          .borderColor(AppColor.divider)
          .borderRadius(AppDim.pillRadius)
          .margin({ top: AppDim.gap24 })
          .enabled(!this.retrying)
          .onClick(() => {
            this.onAction();
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
