import { AppColor, AppDim, showComingSoon, StateMode, StateView } from 'commons_ui';
import { ComingSoonText, LayoutConst } from 'commons_basic';

/**
 * 自选 Tab 的 M0 占位：只交付壳与空态，11 列冻结表在 M1 替换本页内容。
 * 空态带唯一「添加自选」入口，点击走统一占位 toast（DEC-10-02）。
 */
@ComponentV2
export struct WatchlistPage {
  build() {
    Column() {
      Row() {
        Text($r('app.string.watchlist_title'))
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.textPrimary)
      }
      .width('100%')
      .padding({ left: AppDim.gap16, right: AppDim.gap16, top: AppDim.gap16, bottom: AppDim.gap8 })

      StateView({
        mode: StateMode.EMPTY,
        stateDesc: $r('app.string.empty_watchlist_desc'),
        showAction: true,
        actionLabel: $r('app.string.action_add_watchlist'),
        onAction: () => {
          showComingSoon(this.getUIContext(), ComingSoonText.ADD_WATCHLIST);
        }
      })
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: LayoutConst.TAB_BAR_RESERVED })
    .backgroundColor(AppColor.bgPage)
  }
}
