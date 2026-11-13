/** 分组类型：全部（虚拟组）/ 系统组 / 用户组（CC-2）。 */
export type GroupType = 'all' | 'system' | 'user';

/**
 * 自选分组。系统组的展示名由 View 走 i18n（按 id 映射），
 * name 只对用户组有意义（CC-2.9：不得用 tags 判断分组）。
 */
export class WatchGroup {
  id: string;
  type: GroupType;
  order: number;
  name: string;

  constructor(id: string, type: GroupType, order: number, name: string) {
    this.id = id;
    this.type = type;
    this.order = order;
    this.name = name;
  }
}

/**
 * 自选条目：分组归属独立于 tags 存储（设计 §4.3）。
 * `pending`（M7-1）：离线加入、尚未与账号同步的标记；联网后由 `WatchlistSyncService` 清零。
 */
export class WatchItem {
  code: string;
  groups: string[];
  addedAt: number;
  pending: boolean;

  constructor(code: string, groups: string[], addedAt: number, pending: boolean = false) {
    this.code = code;
    this.groups = groups;
    this.addedAt = addedAt;
    this.pending = pending;
  }
}
