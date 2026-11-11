import { DetailFrom, DetailParam, NotFoundParam, PkParam, RouteName } from '../router/AppRoutes';

/**
 * 页面装配点（products 层）：持有全局路由栈，并提供唯一的跳转入口。
 * 约束：只做装配（栈操作），不出现业务判断、不渲染 UI（§3.1.9）。
 * Destination 的统一分派在 AppRoot 的 pageMap（ArkUI 要求 builder 挂在 Navigation 上）。
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

  pushDetail(code: string, from: DetailFrom, rank?: number): void {
    const param: DetailParam = { code: code, from: from };
    if (rank !== undefined) {
      param.rank = rank;
    }
    this.stack.pushPathByName(RouteName.DETAIL, param);
  }

  pushPk(codes: string[], focus?: number): void {
    const param: PkParam = { codes: codes };
    if (focus !== undefined) {
      param.focus = focus;
    }
    this.stack.pushPathByName(RouteName.PK, param);
  }

  pushNotFound(code?: string): void {
    const param: NotFoundParam = {};
    if (code !== undefined) {
      param.code = code;
    }
    this.stack.pushPathByName(RouteName.NOT_FOUND, param);
  }

  pop(): void {
    this.stack.pop();
  }

  /** 回到四 Tab 根（404 的「返回自选」、异常兜底使用）。 */
  backToTabs(): void {
    this.stack.clear();
  }
}
