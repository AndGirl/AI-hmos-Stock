import { SortKey } from './SortRules';

/**
 * 表格几何（设计 §5.2.4 唯一实现，常量与附录 A 一致）。
 * 11 列固定，不按宽度减列；富余全部给名称列，不足全部转横滑。
 */
export interface TableMetrics {
  widths: number[];
  nameWidth: number;
  numericWidth: number;
  totalWidth: number;
  overflow: number;
  rowHeight: number;
  headerHeight: number;
}

export const NAME_BASE: number = 112;
export const ROW_HEIGHT_BASE: number = 56;
export const HEADER_HEIGHT_BASE: number = 40;
export const NUMERIC_BASE: number[] = [76, 70, 78, 82, 68, 78, 66, 66, 70, 68];

/** 数字列（顺序即渲染顺序）：最新价/涨跌/涨跌幅/总量/现量/成交额/振幅/换手/市盈率/市净率。 */
export const NUMERIC_COLUMN_IDS: string[] =
  ['last', 'chg', 'pct', 'volume', 'lastVolume', 'amount', 'amplitude', 'turnover', 'pe', 'pb'];

/** 每列对应的排序键；现量不参与排序（null）。 */
export const NUMERIC_SORT_KEYS: (SortKey | null)[] =
  ['price', 'chg', 'pct', 'vol', null, 'amt', 'amp', 'turn', 'pe', 'pb'];

export function numericSum(): number {
  let sum: number = 0;
  for (let i = 0; i < NUMERIC_BASE.length; i++) {
    sum += NUMERIC_BASE[i];
  }
  return sum;
}

export function computeTableMetrics(viewport: number, fontScale: number): TableMetrics {
  const numeric: number[] = [];
  let sum: number = 0;
  for (let i = 0; i < NUMERIC_BASE.length; i++) {
    const width: number = Math.round(NUMERIC_BASE[i] * fontScale);
    numeric.push(width);
    sum += width;
  }
  const nameBase: number = Math.round(NAME_BASE * fontScale);
  const nameWidth: number = Math.max(nameBase, viewport - sum);
  const widths: number[] = [nameWidth].concat(numeric);
  const totalWidth: number = nameWidth + sum;
  return {
    widths: widths,
    nameWidth: nameWidth,
    numericWidth: sum,
    totalWidth: totalWidth,
    overflow: Math.max(0, totalWidth - viewport),
    rowHeight: Math.max(ROW_HEIGHT_BASE, Math.round(ROW_HEIGHT_BASE * fontScale)),
    headerHeight: Math.max(HEADER_HEIGHT_BASE, Math.round(HEADER_HEIGHT_BASE * fontScale))
  };
}
