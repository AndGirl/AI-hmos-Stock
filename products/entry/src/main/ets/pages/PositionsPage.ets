import { AppColor, AppDim } from 'commons_ui';
import { PositionsView } from 'account';
import { AppServices } from '../di/AppServices';

/**
 * 持仓路由壳（M11-2）：只做 NavDestination 容器、返回栈与「委托」互跳，
 * 列表/汇总/排序/加自选全在 features/account 的 `PositionsView`。
 *
 * 入口：委托页标题栏「持仓」（见 `OrdersPage`）。M11 起不再占用自选页标题行，
 * 避免 1.45× 字号下标题行拥挤（当日委托/管理/编辑已 3 个文字按钮）。
 */
@ComponentV2
export struct PositionsPage {
  @Builder
  ordersMenu() {
    Row() {
      Text($r('app.string.trade_orders_title'))
        .fontSize(13)
        .fontColor(AppColor.textPrimary)
        .height(44)
        .padding({ left: AppDim.gap8, right: AppDim.gap8 })
    }
    .height(44)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      AppServices.get().pushOrders();
    })
  }

  build() {
    NavDestination() {
      Column() {
        PositionsView({
          onOpenDetail: (code: string): void => {
            AppServices.get().pushDetail(code, 'positions');
          }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColor.bgPage)
    }
    .title($r('app.string.position_title'))
    .menus(this.ordersMenu())
    .backgroundColor(AppColor.bgPage)
    .onBackPressed((): boolean => {
      AppServices.get().pop();
      return true;
    })
  }
}
