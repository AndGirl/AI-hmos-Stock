import { TradeStatus } from '../model/QuoteModels';
import { CostBasis, Position, PositionSummary } from '../model/PositionModels';
import { round2 } from './MatchingRules';

/**
 * 持仓与收益口径（M11-1 / AC-121）：全部纯函数，无状态、无定时器、不含中文。
 *
 * 公式（文档：`docs/phase2-position-metrics.md`）：
 * - 估值价 P = 最新价 > 0 ? 最新价 : 最近一次有效价（停牌/退市回落）
 * - 市值 = P × 数量；成本额 = 成本价 × 数量
 * - 累计盈亏 = 市值 − 成本额；累计盈亏率 = 累计盈亏 ÷ 成本额 × 100
 * - 当日盈亏 = (P − 昨收) × 数量；昨收缺失（停牌/退市）或停牌时计 0
 * - 仓位 = 个股市值 ÷ 持仓总市值 × 100
 * - 成本口径 `withoutFee`：本地撮合按委托价成交，不计佣金/印花税
 */

/** 可排序字段（AC-119：市值 / 盈亏额 / 盈亏比）。 */
export type PositionSortKey = 'marketValue' | 'pnl' | 'pnlRatio';

/** 排序方向：与列表列头一致（降 → 升 → 取消）。 */
export type PositionSortDir = 'desc' | 'asc' | 'none';

export const POSITION_SORT_KEYS: PositionSortKey[] = ['marketValue', 'pnl', 'pnlRatio'];

/**
 * 计算单只持仓的输入（Provider 组装；纯函数不吃 Store/Provider）。
 * `lastKnown` 是持仓记录上的「最近一次有效价」，用于停牌估值。
 */
export class PositionBasis {
  code: string;
  name: string;
  qty: number;
  available: number;
  costPrice: number;
  last: number | null;
  lastKnown: number | null;
  prevClose: number | null;
  status: TradeStatus;
  accountId: string;
  costBasis: CostBasis;

  constructor(code: string, name: string, qty: number, available: number, costPrice: number,
    last: number | null, lastKnown: number | null, prevClose: number | null, status: TradeStatus,
    accountId: string, costBasis: CostBasis) {
    this.code = code;
    this.name = name;
    this.qty = qty;
    this.available = available;
    this.costPrice = costPrice;
    this.last = last;
    this.lastKnown = lastKnown;
    this.prevClose = prevClose;
    this.status = status;
    this.accountId = accountId;
    this.costBasis = costBasis;
  }
}

/** 停牌/退市：估值回落「最近一次有效价」，页面标「停」。 */
export function isSuspendedStatus(status: TradeStatus): boolean {
  return status === 'suspended' || status === 'delisted';
}

/** 估值价：有效最新价优先，其次最近一次有效价；都不可用返回 null。 */
export function valuationPriceOf(last: number | null, lastKnown: number | null): number | null {
  if (last !== null && Number.isFinite(last) && last > 0) {
    return last;
  }
  if (lastKnown !== null && Number.isFinite(lastKnown) && lastKnown > 0) {
    return lastKnown;
  }
  return null;
}

/** 单只持仓计算（不写 weight；weight 依赖组合合计，见 `applyWeights`）。 */
export function computePosition(basis: PositionBasis): Position {
  const qty: number = Math.max(0, Math.round(basis.qty));
  const available: number = Math.max(0, Math.round(basis.available));
  const costTotal: number = round2(basis.costPrice * qty);
  const price: number | null = valuationPriceOf(basis.last, basis.lastKnown);
  const marketValue: number | null = price !== null && qty > 0 ? round2(price * qty) : null;
  const pnl: number | null = marketValue !== null ? round2(marketValue - costTotal) : null;
  // 成本额 ≤0（0 成本/负成本脏数据）：盈亏率无意义，返回 null 由页面显示 `--`。
  const pnlRatio: number | null = pnl !== null && costTotal > 0 ? round2(pnl / costTotal * 100) : null;
  let dayPnl: number | null = null;
  if (price !== null && qty > 0) {
    if (basis.prevClose !== null && Number.isFinite(basis.prevClose) && basis.prevClose > 0) {
      dayPnl = round2((price - basis.prevClose) * qty);
    } else {
      // 停牌/退市快照 last 与 prevClose 都是 null：当日盈亏计 0，不做凭空估值。
      dayPnl = 0;
    }
  }
  return new Position(basis.code, basis.name, qty, available, basis.costPrice, price, basis.prevClose,
    marketValue, pnl, pnlRatio, null, dayPnl, basis.costBasis, basis.status, basis.accountId);
}

/** 按组合总市值回填仓位占比（只计有估值的行）。 */
export function applyWeights(rows: Position[]): void {
  let total: number = 0;
  for (let i = 0; i < rows.length; i++) {
    const value: number | null = rows[i].marketValue;
    if (value !== null) {
      total += value;
    }
  }
  for (let i = 0; i < rows.length; i++) {
    const row: Position = rows[i];
    row.weight = row.marketValue !== null && total > 0 ? round2(row.marketValue / total * 100) : null;
  }
}

/** 汇总：市值/当日/累计按「有估值」的行累加；成本额含未估值行；未估值只数单独给。 */
export function summarizePositions(rows: Position[]): PositionSummary {
  let marketValue: number = 0;
  let dayPnl: number = 0;
  let totalPnl: number = 0;
  let costTotal: number = 0;
  let unvalued: number = 0;
  for (let i = 0; i < rows.length; i++) {
    const row: Position = rows[i];
    costTotal += round2(row.costPrice * row.qty);
    if (row.marketValue === null || row.pnl === null) {
      unvalued++;
      continue;
    }
    marketValue += row.marketValue;
    totalPnl += row.pnl;
    dayPnl += row.dayPnl !== null ? row.dayPnl : 0;
  }
  return new PositionSummary(round2(marketValue), round2(dayPnl), round2(totalPnl), round2(costTotal),
    rows.length, unvalued);
}

/** 排序方向循环：none → desc → asc → none（与自选列头同规则）。 */
export function nextPositionSortDir(current: PositionSortDir): PositionSortDir {
  if (current === 'none') {
    return 'desc';
  }
  if (current === 'desc') {
    return 'asc';
  }
  return 'none';
}

export function valueOfPosition(row: Position, key: PositionSortKey): number | null {
  if (key === 'marketValue') {
    return row.marketValue;
  }
  if (key === 'pnl') {
    return row.pnl;
  }
  return row.pnlRatio;
}

/**
 * 空值恒末尾：不随方向翻转（与 CC-4.4 一致）。
 * 返回 a 相对 b 的顺序：负数 a 在前。
 */
export function compareNullable(a: number | null, b: number | null, dir: PositionSortDir): number {
  if (a === null && b === null) {
    return 0;
  }
  if (a === null) {
    return 1;
  }
  if (b === null) {
    return -1;
  }
  if (a === b) {
    return 0;
  }
  const base: number = a < b ? -1 : 1;
  return dir === 'asc' ? base : -base;
}

/** 排序（不改入参数组）：主键 → 市值降序 → code 升序，保证同值时顺序稳定可复现。 */
export function sortPositions(rows: Position[], key: PositionSortKey, dir: PositionSortDir): Position[] {
  const copy: Position[] = rows.slice();
  if (dir === 'none') {
    return copy;
  }
  copy.sort((a: Position, b: Position): number => {
    const primary: number = compareNullable(valueOfPosition(a, key), valueOfPosition(b, key), dir);
    if (primary !== 0) {
      return primary;
    }
    const byValue: number = compareNullable(a.marketValue, b.marketValue, 'desc');
    if (byValue !== 0) {
      return byValue;
    }
    if (a.code === b.code) {
      return 0;
    }
    return a.code < b.code ? -1 : 1;
  });
  return copy;
}
