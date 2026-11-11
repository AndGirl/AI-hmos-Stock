import { AppColor } from 'commons_ui';
import { TabShell } from '../shell/TabShell';
import { AppServices } from '../di/AppServices';
import { RouteName } from '../router/AppRoutes';
import { DetailPage } from './DetailPage';
import { PkPage } from './PkPage';
import { NotFoundPage } from './NotFoundPage';

/**
 * 应用根页面（AppRoot）：Navigation 持有全局路由栈，navBar 承载四 Tab 壳。
 * 所有 NavDestination 在这里统一分派（ArkUI 要求 builder 挂在 Navigation 上，且只能挂一次）。
 */
@Entry
@ComponentV2
struct Index {
  private navStack: NavPathStack = AppServices.get().pathStack();

  @Builder
  pageMap(name: string) {
    if (name === RouteName.DETAIL) {
      DetailPage()
    } else if (name === RouteName.PK) {
      PkPage()
    } else {
      NotFoundPage()
    }
  }

  build() {
    Navigation(this.navStack) {
      TabShell()
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .backgroundColor(AppColor.bgPage)
    .width('100%')
    .height('100%')
  }
}
