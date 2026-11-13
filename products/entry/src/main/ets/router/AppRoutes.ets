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
  static readonly NOT_FOUND: string = 'notFound';
}

/** 详情入口来源：列表 / 卡片 / 搜索 / 深链。 */
export type DetailFrom = 'list' | 'card' | 'search' | 'deeplink';

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
