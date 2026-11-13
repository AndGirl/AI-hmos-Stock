import { QuotePatch, QuoteSnapshot, TradeStatus } from 'commons_data';
import { SortableRow } from '../repository/SortRules';

/** 价格方向：1 涨 / -1 跌 / 0 平或空值。 */
export const DIR_UP: number = 1;
export const DIR_DOWN: number = -1;
export const DIR_FLAT: number = 0;

function textOf(value: number | null, digits: number): string {
  return value === null ? '--' : value.toFixed(digits);
}

function signedText(value: number | null, digits: number, suffix: string): string {
  if (value === null) {
    return '--';
  }
  const body: string = value.toFixed(digits);
  const sign: string = value > 0 ? '+' : '';
  return `${sign}${body}${suffix}`;
}

function percentText(value: number | null): string {
  return value === null ? '--' : `${value.toFixed(2)}%`;
}

/** 总量：手 → 万手（≥1 万手时）。 */
function volumeText(value: number | null): string {
  if (value === null) {
    return '--';
  }
  if (value >= 10000) {
    return `${(value / 10000).toFixed(1)}万手`;
  }
  return `${Math.round(value)}手`;
}

/** 成交额：元 → 亿 / 万。 */
function amountText(value: number | null): string {
  if (value === null) {
    return '--';
  }
  if (value >= 100000000) {
    return `${(value / 100000000).toFixed(2)}亿`;
  }
  return `${(value / 10000).toFixed(0)}万`;
}

/** 逐标的行级行情（设计 §5.2.6）：每行一个实例，字段全 @Trace，
 * 推送只改目标行，避免整表刷新（CC-1.2）。
 * M8 起额外承载卡片需要的 4 个「快照字段」（今开/最高/最低/量比）：
 * 契约里的 `QuotePatch` 不含它们，因此只随快照更新，推送期间保持不变（契约 v1.1 再扩）。
 */
@ObservedV2
export class SymbolQuote implements SortableRow {
  @Trace last: number | null = null;
  @Trace chg: number | null = null;
  @Trace pct: number | null = null;
  @Trace volume: number | null = null;
  @Trace lastVolume: number | null = null;
  @Trace amount: number | null = null;
  @Trace amplitude: number | null = null;
  @Trace turnover: number | null = null;
  @Trace pe: number | null = null;
  @Trace pb: number | null = null;
  @Trace open: number | null = null;
  @Trace high: number | null = null;
  @Trace low: number | null = null;
  @Trace volumeRatio: number | null = null;
  @Trace status: TradeStatus = 'closed';
  @Trace isNew: boolean = false;
  @Trace flashSeq: number = 0;

  applySnapshot(snapshot: QuoteSnapshot): void {
    this.last = snapshot.last;
    this.chg = snapshot.chg;
    this.pct = snapshot.pct;
    this.volume = snapshot.volume;
    this.lastVolume = snapshot.lastVolume;
    this.amount = snapshot.amount;
    this.amplitude = snapshot.amplitude;
    this.turnover = snapshot.turnover;
    this.pe = snapshot.pe;
    this.pb = snapshot.pb;
    // 可选字段：契约里缺省即视为未知 → null（渲染为 --），不能用 0 代替。
    this.open = snapshot.open !== undefined ? snapshot.open : null;
    this.high = snapshot.high !== undefined ? snapshot.high : null;
    this.low = snapshot.low !== undefined ? snapshot.low : null;
    this.volumeRatio = snapshot.volumeRatio !== undefined ? snapshot.volumeRatio : null;
    this.status = snapshot.status;
    this.isNew = snapshot.isNew;
  }

  applyPatch(patch: QuotePatch): void {
    if (patch.last !== undefined) {
      this.last = patch.last;
    }
    if (patch.chg !== undefined) {
      this.chg = patch.chg;
    }
    if (patch.pct !== undefined) {
      this.pct = patch.pct;
    }
    if (patch.volume !== undefined) {
      this.volume = patch.volume;
    }
    if (patch.lastVolume !== undefined) {
      this.lastVolume = patch.lastVolume;
    }
    if (patch.amount !== undefined) {
      this.amount = patch.amount;
    }
    if (patch.amplitude !== undefined) {
      this.amplitude = patch.amplitude;
    }
    if (patch.turnover !== undefined) {
      this.turnover = patch.turnover;
    }
    if (patch.pe !== undefined) {
      this.pe = patch.pe;
    }
    if (patch.pb !== undefined) {
      this.pb = patch.pb;
    }
    if (patch.status !== undefined) {
      this.status = patch.status;
    }
  }

  direction(): number {
    if (this.status === 'suspended' || this.status === 'delisted' || this.chg === null) {
      return DIR_FLAT;
    }
    if (this.chg > 0) {
      return DIR_UP;
    }
    if (this.chg < 0) {
      return DIR_DOWN;
    }
    return DIR_FLAT;
  }
}

/** 列表 10 个数字列的停牌占位（共享常量，行内从不修改）。 */
const DASH_CELLS: string[] = ['--', '--', '--', '--', '--', '--', '--', '--', '--', '--'];
/** 卡片 6 项指标的停牌占位（今开/最高/最低/成交额/换手率/量比）。 */
const DASH_CARD_VALUES: string[] = ['--', '--', '--', '--', '--', '--'];
/** 卡片指标中文名（与 cardValues 同序）：仅供无障碍朗读使用，界面标签走 i18n 资源。 */
const CARD_METRIC_NAMES: string[] = ['今开', '最高', '最低', '成交额', '换手率', '量比'];

/**
 * 列表行 VM：字符串在 VM 层算好（设计 §5.2.11：行内不做格式化）。
 * cells 顺序与 NUMERIC_COLUMN_IDS 一致。
 */
@ObservedV2
export class WatchRowVM {
  code: string = '';
  @Trace name: string = '';
  @Trace groups: string[] = [];
  @Trace suspended: boolean = false;
  @Trace isNew: boolean = false;
  /** 待同步（M7-7）：离线加入、尚未与账号同步的条目标「待同步」。 */
  @Trace pending: boolean = false;
  @Trace quote: SymbolQuote = new SymbolQuote();
  @Trace cells: string[] = [];
  /** 卡片指标值（M8-2，固定 6 项：今开/最高/最低/成交额/换手率/量比；sm 卡只展示前 4 项）。 */
  @Trace cardValues: string[] = DASH_CARD_VALUES;
  @Trace dir: number = DIR_FLAT;

  constructor(code: string, name: string, groups: string[]) {
    this.code = code;
    this.name = name;
    this.groups = groups;
  }

  updateFromSnapshot(snapshot: QuoteSnapshot): void {
    this.quote.applySnapshot(snapshot);
    if (snapshot.name !== '') {
      this.name = snapshot.name;
    }
    this.suspended = snapshot.status === 'suspended' || snapshot.status === 'delisted';
    this.isNew = snapshot.isNew;
    this.refresh();
  }

  applyPatch(patch: QuotePatch): void {
    this.quote.applyPatch(patch);
    this.suspended = this.quote.status === 'suspended' || this.quote.status === 'delisted';
    this.refresh();
    this.quote.flashSeq++;
  }

  refresh(): void {
    this.dir = this.quote.direction();
    const q: SymbolQuote = this.quote;
    if (this.suspended) {
      this.cells = DASH_CELLS;
      this.cardValues = DASH_CARD_VALUES;
      return;
    }
    this.cells = [
      textOf(q.last, 2),
      signedText(q.chg, 2, ''),
      signedText(q.pct, 2, '%'),
      volumeText(q.volume),
      volumeText(q.lastVolume),
      amountText(q.amount),
      percentText(q.amplitude),
      percentText(q.turnover),
      textOf(q.pe, 2),
      textOf(q.pb, 2)
    ];
    this.cardValues = [
      textOf(q.open, 2),
      textOf(q.high, 2),
      textOf(q.low, 2),
      amountText(q.amount),
      percentText(q.turnover),
      textOf(q.volumeRatio, 2)
    ];
  }

  /** 调试压测用（M8-7 200 卡）：复制行情与派生串，code 由构造方指定，不影响 Store。 */
  copyQuoteFrom(other: WatchRowVM): void {
    const from: SymbolQuote = other.quote;
    const to: SymbolQuote = this.quote;
    to.last = from.last;
    to.chg = from.chg;
    to.pct = from.pct;
    to.volume = from.volume;
    to.lastVolume = from.lastVolume;
    to.amount = from.amount;
    to.amplitude = from.amplitude;
    to.turnover = from.turnover;
    to.pe = from.pe;
    to.pb = from.pb;
    to.open = from.open;
    to.high = from.high;
    to.low = from.low;
    to.volumeRatio = from.volumeRatio;
    to.status = from.status;
    to.isNew = from.isNew;
    this.name = other.name;
    this.suspended = other.suspended;
    this.isNew = other.isNew;
    this.pending = other.pending;
    this.refresh();
  }

  /** 无障碍朗读文本（FR-02.13）。 */
  accessibilityLabel(): string {
    const q: SymbolQuote = this.quote;
    const parts: string[] = [
      this.name,
      this.code,
      `最新价${textOf(q.last, 2)}`,
      `涨跌${signedText(q.chg, 2, '')}`,
      `涨跌幅${signedText(q.pct, 2, '%')}`
    ];
    if (this.suspended) {
      parts.push('停牌');
    }
    if (this.isNew) {
      parts.push('新股');
    }
    if (this.pending) {
      parts.push('待同步');
    }
    return parts.join('，');
  }

  /**
   * 卡片无障碍朗读文本（AC-105）：只朗读**卡片上真实展示**的字段，
   * 不朗读列表中才有、卡片没展示的列（总量/现量/振幅/市盈率/市净率）。
   * `metricCount` = 该断点卡片实际展示的指标条数（sm 4 / md 及以上 6）。
   */
  cardAccessibilityLabel(metricCount: number): string {
    const q: SymbolQuote = this.quote;
    const parts: string[] = [this.name, this.code];
    if (this.suspended) {
      parts.push('停牌');
    }
    if (this.isNew) {
      parts.push('新股');
    }
    if (this.pending) {
      parts.push('待同步');
    }
    parts.push(`最新价${textOf(q.last, 2)}`);
    parts.push(`涨跌${signedText(q.chg, 2, '')}`);
    parts.push(`涨跌幅${signedText(q.pct, 2, '%')}`);
    const count: number = Math.min(metricCount, CARD_METRIC_NAMES.length);
    for (let i = 0; i < count; i++) {
      parts.push(`${CARD_METRIC_NAMES[i]}${this.cardValues[i]}`);
    }
    return parts.join('，');
  }
}
