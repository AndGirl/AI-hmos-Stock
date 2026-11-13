import { AppColor } from 'commons_ui';
import { TradeVM } from '../viewmodel/TradeVM';

/**
 * 登录层（DEC-07-07）：未登录入口放行 → 登录 → 回到原标的自动续开。
 * 与编辑/确认共用同一个容器，任一时刻只渲染一层（INV-T2）。
 */
@ComponentV2
export struct TradeLoginView {
  @Param vm: TradeVM = new TradeVM();
  @Param bottomInset: number = 0;

  @Builder
  closeButton() {
    Stack() {
      Text('\u2715')
        .fontSize(15)
        .fontColor(AppColor.textSecondary)
    }
    .width(32)
    .height(32)
    .borderRadius(16)
    .backgroundColor(AppColor.bgSurface)
    .accessibilityGroup(true)
    .accessibilityText($r('app.string.trade_close'))
    .onClick(() => {
      this.vm.tryClose();
    })
  }

  build() {
    Column() {
      Row() {
        Blank()
        this.closeButton()
      }
      .width('100%')

      Text($r('app.string.trade_login_title'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColor.textPrimary)
        .margin({ top: 8 })
      Text($r('app.string.trade_login_desc'))
        .fontSize(13)
        .fontColor(AppColor.textSecondary)
        .margin({ top: 6 })

      Row() {
        if (this.vm.loggingIn) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(AppColor.textOnAccent)
          Text($r('app.string.trade_login_loading'))
            .fontSize(16)
            .fontColor(AppColor.textOnAccent)
            .margin({ left: 8 })
        } else {
          Text($r('app.string.trade_login_action'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.textOnAccent)
        }
      }
      .width('100%')
      .height(48)
      .borderRadius(24)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(AppColor.accentFill)
      .margin({ top: 20 })
      .enabled(!this.vm.loggingIn)
      .onClick(() => {
        this.vm.login();
      })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: this.bottomInset + 16 })
    .alignItems(HorizontalAlign.Start)
  }
}
