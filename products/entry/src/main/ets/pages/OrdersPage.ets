import { AppColor } from 'commons_ui';
import { OrdersView } from 'trade';
import { AppServices } from '../di/AppServices';

/**
 * 委托列表路由壳（M10-4）：只做 NavDestination 容器与返回栈，
 * 列表/筛选/撤单/开户引导全在 features/trade 的 `OrdersView`。
 *
 * 入口：自选页标题行「委托」（见 `WatchlistPage.onOpenOrders`）。
 */
@ComponentV2
export struct OrdersPage {
  build() {
    NavDestination() {
      Column() {
        OrdersView()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColor.bgPage)
    }
    .title('当日委托')
    .backgroundColor(AppColor.bgPage)
    .onBackPressed((): boolean => {
      AppServices.get().pop();
      return true;
    })
  }
}
