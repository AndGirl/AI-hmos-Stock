import {
  AddWatchlistFrom,
  AddWatchlistParam,
  DetailFrom,
  DetailParam,
  NotFoundParam,
  OrdersParam,
  PkParam,
  PositionsParam,
  PrivacyParam,
  RouteName,
  SearchFrom,
  SearchParam
} from '../router/AppRoutes';
import { NavigationGuard } from '../router/NavigationGuard';

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
    // FR-06.2：同一标的 300ms 内只跳一次（列表/卡片/搜索/深链共用）。
    if (!NavigationGuard.tryNavigate('detail:' + code)) {
      return;
    }
    const param: DetailParam = { code: code, from: from };
    if (rank !== undefined) {
      param.rank = rank;
    }
    this.stack.pushPathByName(RouteName.DETAIL, param);
  }

  /** 搜索（M6-6）：深链 / 自选空态 / 其它入口统一走这里。 */
  pushSearch(q?: string, from?: SearchFrom): void {
    if (!NavigationGuard.tryNavigate('search:' + (q !== undefined ? q : ''))) {
      return;
    }
    const param: SearchParam = {};
    if (q !== undefined && q.trim().length > 0) {
      param.q = q.trim();
    }
    if (from !== undefined) {
      param.from = from;
    }
    this.stack.pushPathByName(RouteName.SEARCH, param);
  }

  /**
   * 添加自选（M7-7）：底部胶囊 / 空态按钮 / 卡片虚线卡 / 详情「自选设置」共用。
   * `code` 为预置标的，`group` 为目标分组默认值；只做栈操作，业务在 VM。
   */
  pushAddWatchlist(code?: string, group?: string, from?: AddWatchlistFrom): void {
    const key: string = 'addWatchlist:' + (code !== undefined ? code : '');
    if (!NavigationGuard.tryNavigate(key)) {
      return;
    }
    const param: AddWatchlistParam = {};
    if (code !== undefined && code.trim().length > 0) {
      param.code = code.trim();
    }
    if (group !== undefined && group.trim().length > 0) {
      param.group = group.trim();
    }
    if (from !== undefined) {
      param.from = from;
    }
    this.stack.pushPathByName(RouteName.ADD_WATCHLIST, param);
  }

  pushPk(codes: string[], focus?: number, from?: string): void {
    const param: PkParam = { codes: codes };
    if (focus !== undefined) {
      param.focus = focus;
    }
    if (from !== undefined) {
      param.from = from;
    }
    this.stack.pushPathByName(RouteName.PK, param);
  }

  /** 当日委托（M10-4）：自选页标题「委托」进入。 */
  pushOrders(): void {
    const param: OrdersParam = {};
    this.stack.pushPathByName(RouteName.ORDERS, param);
  }

  /** 持仓与收益（M11-2）：委托页「持仓」互跳进入。 */
  pushPositions(): void {
    const param: PositionsParam = {};
    this.stack.pushPathByName(RouteName.POSITIONS, param);
  }

  /** 隐私政策（M13-1）：首页底部入口进入（同意后常驻可查）。 */
  pushPrivacy(from?: string): void {
    const param: PrivacyParam = {};
    if (from !== undefined && from.length > 0) {
      param.from = from;
    }
    this.stack.pushPathByName(RouteName.PRIVACY, param);
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
