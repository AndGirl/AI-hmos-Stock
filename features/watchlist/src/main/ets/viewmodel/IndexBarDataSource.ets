import { WatchRowVM } from './WatchRowVM';

/**
 * 指数条数据源（LazyForEach 用）：与列表行一一对应（逐股票级），顺序跟随当前分组与排序。
 * 行对象本身是 @ObservedV2，行情推送时条目内部按 @Trace 字段局部刷新，不需要整表重载。
 */
export class IndexBarDataSource implements IDataSource {
  private items: WatchRowVM[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): WatchRowVM {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /** 分组/排序变化时整体替换并通知 LazyForEach。 */
  setItems(items: WatchRowVM[]): void {
    this.items = items;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}
