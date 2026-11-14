import { AppColor } from 'commons_ui';
import { ComplianceHost, ComplianceService, SafeAreaHost, SafeAreaService, StartupMeter } from 'commons_basic';
import { DataServices } from 'commons_data';
import { TabShell } from '../shell/TabShell';
import { AppServices } from '../di/AppServices';
import { RouteName } from '../router/AppRoutes';
import { DeepLinkHandler } from '../router/DeepLinkHandler';
import { ConsentView } from '../view/ConsentView';
import { DetailPage } from './DetailPage';
import { PkPage } from './PkPage';
import { SearchRoutePage } from './SearchPage';
import { AddWatchlistPage } from './AddWatchlistPage';
import { OrdersPage } from './OrdersPage';
import { PositionsPage } from './PositionsPage';
import { PrivacyPage } from './PrivacyPage';
import { NotFoundPage } from './NotFoundPage';

/**
 * 应用根页面（AppRoot）：Navigation 持有全局路由栈，navBar 承载四 Tab 壳。
 * 所有 NavDestination 在这里统一分派（ArkUI 要求 builder 挂在 Navigation 上，且只能挂一次）。
 *
 * M13-1 首启门禁：未同意隐私政策时**不渲染 TabShell / Navigation**（避免内容先于同意出现），
 * 只渲染中性骨架或全屏同意页；同意后本页因 `ComplianceService.consented` 变化自动切到 TabShell。
 * 冷启动深链在 `Navigation.onAppear` 才 `markReady()`，因此未同意期间深链会排队到同意之后。
 */
@Entry
@ComponentV2
struct Index {
  private navStack: NavPathStack = AppServices.get().pathStack();
  @Local safeArea: SafeAreaService = SafeAreaHost.getService();
  @Local compliance: ComplianceService = ComplianceHost.getService();

  aboutToAppear(): void {
    // 预热（幂等）：EntryAbility 已发起过同一次读盘，这里只等同一个 Promise。
    DataServices.privacyConsent().load();
  }

  @Builder
  pageMap(name: string) {
    if (name === RouteName.DETAIL) {
      DetailPage()
    } else if (name === RouteName.PK) {
      PkPage()
    } else if (name === RouteName.SEARCH) {
      SearchRoutePage()
    } else if (name === RouteName.ADD_WATCHLIST) {
      AddWatchlistPage()
    } else if (name === RouteName.ORDERS) {
      OrdersPage()
    } else if (name === RouteName.POSITIONS) {
      PositionsPage()
    } else if (name === RouteName.PRIVACY) {
      PrivacyPage()
    } else {
      NotFoundPage()
    }
  }

  build() {
    Column() {
      if (!this.compliance.ready) {
        // 读盘期间只给中性骨架（背景色），不显示任何内容（不闪「先内容后弹窗」）。
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(AppColor.bgPage)
      } else if (!this.compliance.consented) {
        ConsentView()
      } else {
        Navigation(this.navStack) {
          TabShell()
        }
        .navDestination(this.pageMap)
        .onAppear(() => {
          // UI 已挂载，消费冷启动暂存的深链（设计 §3.2）。
          DeepLinkHandler.markReady();
        })
        .mode(NavigationMode.Stack)
        .hideTitleBar(true)
        .padding({
          top: this.safeArea.topInset,
          left: this.safeArea.leftInset,
          right: this.safeArea.rightInset
        })
        .backgroundColor(AppColor.bgPage)
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bgPage)
    .onAppear((): void => {
      // 冷启打点终点（M13-2）：首个内容帧已渲染（同意页/主界面各记一条，便于区分首启）。
      StartupMeter.markFirstFrame(this.compliance.consented ? 'tabs' : 'consent');
    })
  }
}
