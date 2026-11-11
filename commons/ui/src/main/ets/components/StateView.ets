import { AppColor, AppDim } from '../theme/TokenRegistry';

/** 页面级状态视图的三种形态（M0 只落地空态与加载态，失败态在 M1/M2 复用）。 */
export enum StateMode {
  LOADING = 0,
  EMPTY = 1,
  ERROR = 2
}

/**
 * 通用状态视图：图标位 + 说明 + 可选单一操作。
 * 规则：空态除说明外最多一个操作入口，不放置第二个按钮（基线 §4.1 规则 6）。
 */
@ComponentV2
export struct StateView {
  @Param mode: StateMode = StateMode.EMPTY;
  @Param stateDesc: ResourceStr = '';
  @Param showAction: boolean = false;
  @Param actionLabel: ResourceStr = '';
  @Event onAction: () => void = () => {
  };

  build() {
    Column() {
      if (this.mode === StateMode.LOADING) {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(AppColor.accent)
      } else {
        Image($r('app.media.ic_placeholder'))
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
          Button(this.actionLabel)
            .height(AppDim.touchMin)
            .padding({ left: AppDim.gap24, right: AppDim.gap24 })
            .fontSize(14)
            .fontColor(AppColor.textSecondary)
            .backgroundColor(AppColor.transparent)
            .borderWidth(1)
            .borderColor(AppColor.divider)
            .borderRadius(AppDim.pillRadius)
            .margin({ top: AppDim.gap24 })
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
