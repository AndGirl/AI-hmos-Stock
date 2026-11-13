import {
  CardMetrics,
  computeCardColumns,
  computeCardMetrics,
  metricColumnsOf,
  metricCountOf
} from '../repository/CardMetrics';

/**
 * 卡片视图状态（M8-1/M8-2）：只放几何与呈现口径，行数据与列表共享 `WatchlistVM.rows`。
 * 单独成类是为了让「列表度量」（`TableMetrics`）与「卡片度量」互不干扰，
 * 且切换视图时不重建 VM（AC-103）。
 */
@ObservedV2
export class CardVM {
  /** 最终列数（已按字号降列）。 */
  @Trace columns: number = 2;
  @Trace gap: number = 12;
  @Trace padding: number = 16;
  @Trace cardW: number = 172;
  @Trace minCardH: number = 132;
  /** 指标条数：sm 4 / md 及以上 6。 */
  @Trace metricCount: number = 4;
  /** 指标区列数：卡宽 ≥200 用 2 列，否则单列。 */
  @Trace metricColumns: number = 1;

  /** 断点/字号/容器宽变化时重算（幂等，值不变则不产生无效渲染）。 */
  update(viewport: number, bp: string, fontScale: number): void {
    if (viewport <= 0) {
      return;
    }
    const columns: number = computeCardColumns(bp, viewport, fontScale);
    const metrics: CardMetrics = computeCardMetrics(viewport, columns, fontScale);
    if (metrics.columns !== this.columns) {
      this.columns = metrics.columns;
    }
    if (metrics.gap !== this.gap) {
      this.gap = metrics.gap;
    }
    if (metrics.padding !== this.padding) {
      this.padding = metrics.padding;
    }
    if (metrics.cardW !== this.cardW) {
      this.cardW = metrics.cardW;
    }
    if (metrics.minCardH !== this.minCardH) {
      this.minCardH = metrics.minCardH;
    }
    const count: number = metricCountOf(bp);
    if (count !== this.metricCount) {
      this.metricCount = count;
    }
    const metricColumns: number = metricColumnsOf(metrics.cardW);
    if (metricColumns !== this.metricColumns) {
      this.metricColumns = metricColumns;
    }
  }

  /** Grid 的 `columnsTemplate`（1fr 均分，与 `cardW` 同源同值）。 */
  columnTemplate(): string {
    let template: string = '1fr';
    for (let i = 1; i < this.columns; i++) {
      template += ' 1fr';
    }
    return template;
  }

  /** 空白/空态判定的兜底值（供组件默认参数使用）。 */
  static fallback(): CardVM {
    return new CardVM();
  }
}
