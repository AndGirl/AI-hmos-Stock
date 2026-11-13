import { AppColor } from 'commons_ui';
import { SafeAreaHost, SafeAreaService } from 'commons_basic';
import { TabShell } from '../shell/TabShell';
import { AppServices } from '../di/AppServices';
import { RouteName } from '../router/AppRoutes';
import { DeepLinkHandler } from '../router/DeepLinkHandler';
import { DetailPage } from './DetailPage';
import { PkPage } from './PkPage';
import { SearchRoutePage } from './SearchPage';
import { AddWatchlistPage } from './AddWatchlistPage';
import { NotFoundPage } from './NotFoundPage';

/**
 * 应用根页面（AppRoot）：Navigation 持有全局路由栈，navBar 承载四 Tab 壳。
 * 所有 NavDestination 在这里统一分派（ArkUI 要求 builder 挂在 Navigation 上，且只能挂一次）。
 */
@Entry
@ComponentV2
struct Index {
  private navStack: NavPathStack = AppServices.get().pathStack();
  @Local safeArea: SafeAreaService = SafeAreaHost.getService();

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
    } else {
      NotFoundPage()
    }
  }

  build() {
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
    .padding({ top: this.safeArea.topInset })
    .backgroundColor(AppColor.bgPage)
    .width('100%')
    .height('100%')
  }
}
