/**
 * 路由名与参数契约（设计 §3.5）。
 * 约束：跨模块跳转只经 AppServices 的 push 方法，禁止页面直接拼 name/param。
 */
export class RouteName {
  static readonly DETAIL: string = 'detail';
  static readonly PK: string = 'pk';
  static readonly SEARCH: string = 'search';
  /** 添加自选（M7-7）：四入口统一走这一页。 */
  static readonly ADD_WATCHLIST: string = 'addWatchlist';
  /** 当日委托（M10-4）：自选页标题「委托」进入。 */
  static readonly ORDERS: string = 'orders';
  /** 持仓与收益（M11-2）：委托页「持仓」互跳进入。 */
  static readonly POSITIONS: string = 'positions';
  /** 隐私政策（M13-1）：首页底部入口进入；撤回同意后回到首启同意页。 */
  static readonly PRIVACY: string = 'privacy';
  static readonly NOT_FOUND: string = 'notFound';
}

/** 详情入口来源：列表 / 卡片 / 搜索 / 深链 / 持仓。 */
export type DetailFrom = 'list' | 'card' | 'search' | 'deeplink' | 'positions';

export interface DetailParam {
  code: string;
  from: DetailFrom;
  rank?: number;
}

/** 搜索入口来源：行情 Tab / 自选空态 / 深链 / 其它（埋点与返回态用）。 */
export type SearchFrom = 'tab' | 'watchlist' | 'deeplink' | 'detail';

export interface SearchParam {
  /** 深链带入的关键词（已截断 20 字）；缺省回落初始态。 */
  q?: string;
  from?: SearchFrom;
}

/** 添加自选入口来源（AC-94 四入口：底部胶囊 / 空态按钮 / 卡片虚线卡 / 详情「自选设置」）。 */
export type AddWatchlistFrom = 'watchlist' | 'detail' | 'search' | 'pane' | 'card';

export interface AddWatchlistParam {
  /** 详情 / 右栏 / 搜索页带入的预置标的（"已在自选"直接展示）。 */
  code?: string;
  /** 目标分组默认值（当前 Tab）；缺省由板块派生。 */
  group?: string;
  from?: AddWatchlistFrom;
}

export interface PkParam {
  codes: string[];
  focus?: number;
  /** 入口来源（FR-08.1 三入口）：detail 动作栏 / icon 详情 ⧉ / watchlist 自选多选。 */
  from?: string;
}

export interface NotFoundParam {
  code?: string;
}

/** 当日委托参数（M10-4）：当前无入参，保留结构便于后续「按标的过滤」只加不改。 */
export interface OrdersParam {
  code?: string;
}

/** 持仓参数（M11-2）：当前无入参，保留结构便于后续「按账户/分组」只加不改。 */
export interface PositionsParam {
  accountId?: string;
}

/** 隐私政策参数（M13-1）：当前无入参；保留类结构便于后续「来源/深链」只加不改。 */
export class PrivacyParam {
}
