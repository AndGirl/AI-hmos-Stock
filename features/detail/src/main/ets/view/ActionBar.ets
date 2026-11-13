import { AppColor, AppDim } from 'commons_ui';
import { DetailAction } from '../viewmodel/DetailVM';

/**
 * 通栏动作栏（FR-06.10）：左侧三项（自选设置 / 股票PK / 更多），
 * 右侧「去交易」红底胶囊（高 ≥44vp、占宽 ≥40%）；停牌/退市禁用。
 */
@ComponentV2
export struct ActionBar {
  @Param tradeEnabled: boolean = true;
  @Event onAction: (action: DetailAction) => void = (action: DetailAction): void => {
  };

  @Builder
  actionItem(icon: Resource, label: Resource, action: DetailAction, enabled: boolean) {
    Column() {
      Image(icon)
        .width(20)
        .height(20)
        .fillColor(enabled ? AppColor.textPrimary : AppColor.disabledText)
      Text(label)
        .fontSize(10)
        .fontColor(enabled ? AppColor.textPrimary : AppColor.disabledText)
        .margin({ top: 2 })
        .maxLines(1)
    }
    .width(66)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .accessibilityGroup(true)
    .onClick(() => {
      this.onAction(action);
    })
  }

  build() {
    Row() {
      Row() {
        this.actionItem($r('app.media.ic_detail_star'), $r('app.string.detail_action_watchlist'), 'watchlist',
          true)
        this.actionItem($r('app.media.ic_detail_pk'), $r('app.string.detail_action_pk'), 'pk', true)
        this.actionItem($r('app.media.ic_detail_more'), $r('app.string.detail_action_more'), 'more', true)
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.SpaceAround)

      Text($r('app.string.detail_action_trade'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tradeEnabled ? AppColor.textOnAccent : AppColor.disabledText)
        .textAlign(TextAlign.Center)
        .height(44)
        .width('42%')
        .backgroundColor(this.tradeEnabled ? AppColor.accentFill : AppColor.disabledBg)
        .borderRadius(AppDim.pillRadius)
        .margin({ right: AppDim.gap16 })
        .onClick(() => {
          this.onAction('trade');
        })
    }
    .width('100%')
    .height(64)
    .padding({ left: AppDim.gap8 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppColor.bgPage)
    .border({ width: { top: 0.5 }, color: AppColor.divider })
  }
}
