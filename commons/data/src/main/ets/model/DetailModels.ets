import { Market, QuoteSnapshot, TradeStatus } from './QuoteModels';

/**
 * 图表周期（FR-06.6：固定 8 个，顺序即 Tab 顺序）。
 * timeline=分时，five=五日，d/w/m/q/hy/y=日/周/月/季/半年/年 K。
 */
export type ChartPeriod = 'timeline' | 'five' | 'd' | 'w' | 'm' | 'q' | 'hy' | 'y';

export const CHART_PERIODS: ChartPeriod[] = ['timeline', 'five', 'd', 'w', 'm', 'q', 'hy', 'y'];

/** 分时 241 点；K 线单次 120 根，上限 500 根（FR-06.14）。 */
export const TIMELINE_POINT_COUNT: number = 241;
export const KLINE_PAGE_SIZE: number = 120;
export const KLINE_MAX_COUNT: number = 500;

export function isKlinePeriod(period: ChartPeriod): boolean {
  return period !== 'timeline' && period !== 'five';
}

/** 图表点位：分时为 1 分钟一点（avg 为均价），K 线为一根蜡烛（avg 不用）。 */
export class ChartPoint {
  ts: number;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
  avg: number;

  constructor(ts: number, open: number, high: number, low: number, close: number, volume: number,
    avg: number) {
    this.ts = ts;
    this.open = open;
    this.high = high;
    this.low = low;
    this.close = close;
    this.volume = volume;
    this.avg = avg;
  }
}

/** 一个周期的完整绘图数据（ChartEngine 只认这个结构，ADR-04）。 */
export interface ChartSeries {
  period: ChartPeriod;
  points: ChartPoint[];
  prevClose: number;
  limitUp: number;
  limitDown: number;
}

/** 五档单档：价格空值用 null（停牌时整块 `--`）。 */
export class OrderLevel {
  price: number | null;
  volume: number | null;

  constructor(price: number | null, volume: number | null) {
    this.price = price;
    this.volume = volume;
  }
}

/** 盘口：asks[0]=卖1 … asks[4]=卖5；bids[0]=买1 … bids[4]=买5。 */
export class OrderBook {
  asks: OrderLevel[] = [];
  bids: OrderLevel[] = [];
  /** 委买 / 委卖总量（手），用于红绿比例条（FR-06.8）。 */
  bidVolume: number = 0;
  askVolume: number = 0;
}

export type TickDirection = 'buy' | 'sell' | 'neutral';

export class Tick {
  time: number;
  price: number;
  volume: number;
  direction: TickDirection;

  constructor(time: number, price: number, volume: number, direction: TickDirection) {
    this.time = time;
    this.price = price;
    this.volume = volume;
    this.direction = direction;
  }
}

/** 板块/状态标签（只含 tags，不含分组，CC-2.9）；文案由 View 走 i18n。 */
export type StockTag = 'hsgt' | 'rzrq' | 'large' | 'new' | 'suspended';

export class DetailNews {
  id: string;
  title: string;
  ts: number;

  constructor(id: string, title: string, ts: number) {
    this.id = id;
    this.title = title;
    this.ts = ts;
  }
}

/** 详情首屏快照（FR-06 §3：与真实同形，字段空值一律 null）。 */
export class DetailSnapshot {
  code: string = '';
  name: string = '';
  market: Market = 'SH';
  tags: StockTag[] = [];
  status: TradeStatus = 'open';
  snapshotTime: number = 0;
  quote: QuoteSnapshot | null = null;
  orderBook: OrderBook = new OrderBook();
  ticks: Tick[] = [];
  news: DetailNews | null = null;
}

/** 1s 合并后的详情增量（整块快照，避免 patch 字段合并的歧义）。 */
export class DetailPatch {
  quote: QuoteSnapshot;
  orderBook: OrderBook;
  ticks: Tick[];

  constructor(quote: QuoteSnapshot, orderBook: OrderBook, ticks: Tick[]) {
    this.quote = quote;
    this.orderBook = orderBook;
    this.ticks = ticks;
  }
}

export interface DetailListener {
  onPatch(patch: DetailPatch): void;
}

export interface DetailSubscription {
  unsubscribe(): void;
}

export type DetailErrorReason = 'not_found' | 'timeout' | 'internal' | 'offline';

/** 首屏失败原因：not_found → 404 态，其余 → 可重试错误态（FR-06.2 / §2.5）。 */
export class DetailError extends Error {
  reason: DetailErrorReason;

  constructor(reason: DetailErrorReason, message: string) {
    super(message);
    this.reason = reason;
  }
}

/**
 * 详情数据源：首屏快照 + 图表序列 + 1s 盘口/明细推送。
 * 页面退出 / 切 code 必须 unsubscribe（FR-06.14）。
 */
export interface DetailProvider {
  loadDetail(code: string): Promise<DetailSnapshot>;

  loadChart(code: string, period: ChartPeriod, count?: number): Promise<ChartSeries>;

  subscribe(code: string, listener: DetailListener): DetailSubscription;

  /** 离线有缓存场景取最后一份快照（CC-7.6）。 */
  cachedDetail(code: string): DetailSnapshot | undefined;

  /**
   * M9-1 可选分页（只加不改）：以 `beforeTs` 为游标向更早取 `count` 根 K 线，
   * 单次上限 `KLINE_MAX_COUNT`（500 根）。缺失时调用方回退 `loadChart`。
   */
  chartPage?(code: string, period: ChartPeriod, beforeTs: number, count: number): Promise<ChartSeries>;
}
