import { AppColor } from 'commons_ui';
import { TabShell } from '../shell/TabShell';
import { AppServices } from '../di/AppServices';

/**
 * 应用根页面（AppRoot）：Navigation 持有全局路由栈，navBar 承载四 Tab 壳。
 * 详情 / 比价 / 404 的 NavDestination 由 AppServices 在路由步骤注册。
 */
@Entry
@ComponentV2
struct Index {
  private navStack: NavPathStack = AppServices.get().pathStack();

  build() {
    Navigation(this.navStack) {
      TabShell()
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .backgroundColor(AppColor.bgPage)
    .width('100%')
    .height('100%')
  }
}
