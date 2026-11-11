/**
 * 页面装配点（products 层）：持有全局路由栈，后续在此注册 detail / pk / notFound 的
 * NavDestination 构建器并注入各 feature 页面工厂。
 * 约束：只做装配（new 与注册），不出现业务判断、不渲染 UI（§3.1.9）。
 */
export class AppServices {
  private static instance: AppServices | null = null;
  private readonly stack: NavPathStack = new NavPathStack();

  private constructor() {
  }

  static get(): AppServices {
    if (AppServices.instance === null) {
      AppServices.instance = new AppServices();
    }
    return AppServices.instance;
  }

  pathStack(): NavPathStack {
    return this.stack;
  }
}
