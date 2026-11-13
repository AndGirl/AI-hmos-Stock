import { HitRange, QuotePatch, rangesForField, SearchHit, SearchKind, TradeStatus } from 'commons_data';

/** 价格方向：1 涨 / -1 跌 / 0 平、停牌或空值。 */
export const SEARCH_DIR_UP: number = 1;
export const SEARCH_DIR_DOWN: number = -1;
export const SEARCH_DIR_FLAT: number = 0;

function priceText(value: number | null): string {
  return value === null ? '--' : value.toFixed(2);
}

function pctText(value: number | null): string {
  if (value === null) {
    return '--';
  }
  const sign: string = value > 0 ? '+' : '';
  return `${sign}${value.toFixed(2)}%`;
}

/**
 * 搜索单行（M6-3/M6-4）：只更新命中行的「已添加」态（§5.6 红线），不重建整段。
 * 行内不放中文，展示字符串在 VM 算好；无障碍文本由 View 组装（避免 L2 出现文案）。
 * P1 起支持 `applyQuote`：与自选页同一路 QuoteBus 推送，单行刷新价格。
 */
@ObservedV2
export class SearchRowVM {
  code: string = '';
  kind: SearchKind = 'stock';
  @Trace name: string = '';
  @Trace priceText: string = '--';
  @Trace pctText: string = '--';
  @Trace dir: number = SEARCH_DIR_FLAT;
  @Trace suspended: boolean = false;
  @Trace isNew: boolean = false;
  @Trace added: boolean = false;
  @Trace pending: boolean = false;
  /** 添加页多选态（M7-2）：本行是否被勾选。 */
  @Trace picked: boolean = false;
  /** 命中位次（详情埋点 from=search&rank=n）。 */
  @Trace rank: number = 0;
  @Trace nameRanges: HitRange[] = [];
  @Trace codeRanges: HitRange[] = [];
  @Trace last: number | null = null;
  @Trace pct: number | null = null;
  @Trace status: TradeStatus = 'closed';

  apply(hit: SearchHit, rank: number): void {
    this.code = hit.code;
    this.kind = hit.kind;
    this.name = hit.name;
    this.last = hit.price;
    this.pct = hit.pct;
    this.status = hit.status;
    this.isNew = hit.isNew;
    this.rank = rank;
    this.nameRanges = rangesForField(hit.ranges, 'name');
    this.codeRanges = rangesForField(hit.ranges, 'code');
    this.refresh();
  }

  /** QuoteBus 单行推送（P1 行情同步）：只改本行，不重建列表。 */
  applyQuote(patch: QuotePatch): void {
    if (patch.last !== undefined) {
      this.last = patch.last;
    }
    if (patch.pct !== undefined) {
      this.pct = patch.pct;
    }
    if (patch.status !== undefined) {
      this.status = patch.status;
    }
    this.refresh();
  }

  markAdded(): void {
    this.added = true;
    this.pending = false;
  }

  /** 添加页勾选切换（M7-2）：只改本行，计数由 VM 维护。 */
  markPicked(on: boolean): void {
    this.picked = on;
  }

  /** 撤出自选（M6 追加）：行回未添加态，恢复可点「＋」。 */
  markRemoved(): void {
    this.added = false;
    this.pending = false;
  }

  /** 可加：仅未添加的股票行；已添加行改为可点移除（AC-91 变更）。 */
  canAdd(): boolean {
    return this.kind === 'stock' && !this.added && !this.pending;
  }

  private refresh(): void {
    this.priceText = priceText(this.last);
    this.pctText = pctText(this.pct);
    this.suspended = this.status === 'suspended' || this.status === 'delisted';
    this.dir = SearchRowVM.directionOf(this.status, this.pct);
  }

  private static directionOf(status: TradeStatus, pct: number | null): number {
    if (status === 'suspended' || status === 'delisted' || pct === null) {
      return SEARCH_DIR_FLAT;
    }
    if (pct > 0) {
      return SEARCH_DIR_UP;
    }
    if (pct < 0) {
      return SEARCH_DIR_DOWN;
    }
    return SEARCH_DIR_FLAT;
  }
}
