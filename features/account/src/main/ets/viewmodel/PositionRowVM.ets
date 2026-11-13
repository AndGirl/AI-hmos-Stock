import { isSuspendedStatus, Position } from 'commons_data';

/**
 * 持仓行 VM（M11-2）：只装原始值 + 派生布尔，文案与格式化在 View 层（R-07）。
 * 行情每秒刷新时用 `copy` 原地增量更新，避免重建行对象导致列表跳动。
 */
@ObservedV2
export class PositionRowVM {
  @Trace code: string = '';
  @Trace name: string = '';
  @Trace qty: number = 0;
  @Trace costPrice: number = 0;
  @Trace last: number | null = null;
  @Trace prevClose: number | null = null;
  @Trace marketValue: number | null = null;
  @Trace pnl: number | null = null;
  @Trace pnlRatio: number | null = null;
  @Trace weight: number | null = null;
  @Trace dayPnl: number | null = null;
  @Trace status: string = 'open';
  /** 停牌/退市：估值回落最近有效价，页面标「停」并置灰现价。 */
  @Trace suspended: boolean = false;
  /** 已在自选（AC-120：「已添加」不可再点）。 */
  @Trace added: boolean = false;

  static of(item: Position): PositionRowVM {
    const row: PositionRowVM = new PositionRowVM();
    row.copy(item);
    return row;
  }

  /** 全量/增量同步（字段级 @Trace，只有变化的文本会重绘）。 */
  copy(item: Position): void {
    this.code = item.code;
    this.name = item.name;
    this.qty = item.qty;
    this.costPrice = item.costPrice;
    this.last = item.last;
    this.prevClose = item.prevClose;
    this.marketValue = item.marketValue;
    this.pnl = item.pnl;
    this.pnlRatio = item.pnlRatio;
    this.weight = item.weight;
    this.dayPnl = item.dayPnl;
    this.status = item.status;
    this.suspended = isSuspendedStatus(item.status);
  }

  setAdded(added: boolean): void {
    this.added = added;
  }
}
