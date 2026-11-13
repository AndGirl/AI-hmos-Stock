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

/**
 * 逐标的行级行情（设计 §5.2.6）：每行一个实例，字段全 @Trace，
 * 推送只改目标行，避免整表刷新（CC-1.2）。
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
      this.cells = ['--', '--', '--', '--', '--', '--', '--', '--', '--', '--'];
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
}
