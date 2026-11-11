/**
 * 路由名与参数契约（设计 §3.5）。
 * 约束：跨模块跳转只经 AppServices 的 push 方法，禁止页面直接拼 name/param。
 */
export class RouteName {
  static readonly DETAIL: string = 'detail';
  static readonly PK: string = 'pk';
  static readonly NOT_FOUND: string = 'notFound';
}

/** 详情入口来源：列表 / 卡片 / 搜索 / 深链。 */
export type DetailFrom = 'list' | 'card' | 'search' | 'deeplink';

export interface DetailParam {
  code: string;
  from: DetailFrom;
  rank?: number;
}

export interface PkParam {
  codes: string[];
  focus?: number;
}

export interface NotFoundParam {
  code?: string;
}
