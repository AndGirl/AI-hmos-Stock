import { AppColor, StateMode, StateView } from 'commons_ui';
import { AppServices } from '../di/AppServices';

/**
 * 404 / 未知标的兜底页（设计 §3.5、§6.4 L4）：整页错误态 + 唯一「返回自选」。
 * 深链缺参、标的下架/退市统一落到这里，并由调用方上报 deeplink_invalid（M0-2）。
 */
@ComponentV2
export struct NotFoundPage {
  build() {
    NavDestination() {
      StateView({
        mode: StateMode.ERROR,
        stateDesc: $r('app.string.route_not_found_desc'),
        showAction: true,
        actionLabel: $r('app.string.route_back_watchlist'),
        onAction: () => {
          AppServices.get().backToTabs();
        }
      })
        .width('100%')
        .height('100%')
    }
    .title($r('app.string.route_not_found_title'))
    .backgroundColor(AppColor.bgPage)
  }
}
