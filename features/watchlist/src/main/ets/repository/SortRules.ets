import { TradeStatus } from 'commons_data';

/** 可排序列（CC-4；现量不参与排序）。 */
export type SortKey = 'price' | 'chg' | 'pct' | 'vol' | 'amt' | 'amp' | 'turn' | 'pe' | 'pb';

/** 列头循环：降序 → 升序 → 取消（CC-4.2）。 */
export type SortDir = 'desc' | 'asc' | 'none';

/** 比较器只依赖这些字段，VM 的 SymbolQuote 结构上满足即可（L2 不反向依赖 L3）。 */
export interface SortableRow {
  last: number | null;
  chg: number | null;
  pct: number | null;
  volume: number | null;
  amount: number | null;
  amplitude: number | null;
  turnover: number | null;
  pe: number | null;
  pb: number | null;
  status: TradeStatus;
  isNew: boolean;
}

export function nextSortDir(current: SortDir): SortDir {
  if (current === 'none') {
    return 'desc';
  }
  if (current === 'desc') {
    return 'asc';
  }
  return 'none';
}

export function valueOf(row: SortableRow, key: SortKey): number | null {
  if (key === 'price') {
    return row.last;
  }
  if (key === 'chg') {
    return row.chg;
  }
  if (key === 'pct') {
    return row.pct;
  }
  if (key === 'vol') {
    return row.volume;
  }
  if (key === 'amt') {
    return row.amount;
  }
  if (key === 'amp') {
    return row.amplitude;
  }
  if (key === 'turn') {
    return row.turnover;
  }
  if (key === 'pe') {
    return row.pe;
  }
  return row.pb;
}

/**
 * 空值恒末尾：不随方向翻转（CC-4.4）。
 * 返回 a 相对 b 的顺序：负数 a 在前。
 */
export function compareNullable(a: number | null, b: number | null, dir: SortDir): number {
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

/** 主键相同（或都为空）时用最新价做次键，保证稳定（§5.2.7 第 3 条）。 */
export function compareRows(a: SortableRow, b: SortableRow, key: SortKey, dir: SortDir): number {
  const primary: number = compareNullable(valueOf(a, key), valueOf(b, key), dir);
  if (primary !== 0) {
    return primary;
  }
  const aNull: boolean = valueOf(a, key) === null;
  const bNull: boolean = valueOf(b, key) === null;
  if (aNull && bNull) {
    return 0;
  }
  return compareNullable(a.last, b.last, dir);
}
