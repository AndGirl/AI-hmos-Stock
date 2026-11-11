import { QuoteSnapshot } from '../model/QuoteModels';
import {
  ChartPoint,
  ChartPeriod,
  ChartSeries,
  DetailNews,
  OrderBook,
  OrderLevel,
  StockTag,
  Tick,
  TickDirection,
  TIMELINE_POINT_COUNT
} from '../model/DetailModels';

const DAY_MS: number = 86400000;
const MINUTE_MS: number = 60000;
const LIMIT_RATIO: number = 0.10;
const TIMELINE_MINUTES: number = TIMELINE_POINT_COUNT - 1;

/** 线性同余伪随机：同一 code + period 恒定，保证 Mock 图表可复现。 */
class Lcg {
  private seed: number;

  constructor(seed: number) {
    const normalized: number = Math.abs(Math.floor(seed)) % 2147483647;
    this.seed = normalized === 0 ? 12345 : normalized;
  }

  next(): number {
    this.seed = (this.seed * 16807) % 2147483647;
    return (this.seed - 1) / 2147483646;
  }

  range(min: number, max: number): number {
    return min + this.next() * (max - min);
  }
}

function hashCode(text: string): number {
  let hash: number = 7;
  for (let i = 0; i < text.length; i++) {
    hash = (hash * 31 + text.charCodeAt(i)) % 2147483647;
  }
  return hash;
}

export function seedOf(code: string, period: ChartPeriod): number {
  return hashCode(code) + hashCode(period) * 131;
}

/** 当天 00:00 的本地时间戳（图表 X 轴基准，只用于 Mock 时间刻度）。 */
function dayStart(at: number): number {
  const date: Date = new Date(at);
  date.setHours(0, 0, 0, 0);
  return date.getTime();
}

/** 分时第 i 点的行情时间：前 120 分钟 09:30 起，后 121 分钟 13:00 起（午休不占宽）。 */
function timelineTs(day: number, index: number): number {
  const morningOpen: number = day + 9 * 3600000 + 30 * MINUTE_MS;
  if (index <= 120) {
    return morningOpen + index * MINUTE_MS;
  }
  const afternoonOpen: number = day + 13 * 3600000;
  return afternoonOpen + (index - 120) * MINUTE_MS;
}

export function buildTags(quote: QuoteSnapshot): StockTag[] {
  const tags: StockTag[] = [];
  if (quote.status === 'suspended') {
    tags.push('suspended');
  }
  if (quote.isNew) {
    tags.push('new');
  }
  if (quote.code.startsWith('60') || quote.code.startsWith('000')) {
    tags.push('hsgt');
  }
  if (quote.code.charCodeAt(quote.code.length - 1) % 2 === 0) {
    tags.push('rzrq');
  }
  if (quote.last !== null && quote.last >= 50) {
    tags.push('large');
  }
  return tags;
}

function levelList(last: number, direction: number, rng: Lcg): OrderLevel[] {
  const levels: OrderLevel[] = [];
  for (let i = 1; i <= 5; i++) {
    const price: number = Math.round((last + direction * i * 0.01) * 100) / 100;
    const volume: number = Math.round(rng.range(80, 4800));
    levels.push(new OrderLevel(price, volume));
  }
  return levels;
}

export function buildOrderBook(quote: QuoteSnapshot): OrderBook {
  const rng: Lcg = new Lcg(seedOf(quote.code, 'timeline') + (quote.volume !== null ? quote.volume : 0) +
    Math.round(quote.snapshotTime % 9973));
  const book: OrderBook = new OrderBook();
  if (quote.last === null || quote.status === 'suspended' || quote.status === 'delisted') {
    for (let i = 0; i < 5; i++) {
      book.asks.push(new OrderLevel(null, null));
      book.bids.push(new OrderLevel(null, null));
    }
    return book;
  }
  book.asks = levelList(quote.last, 1, rng);
  book.bids = levelList(quote.last, -1, rng);
  let askTotal: number = 0;
  let bidTotal: number = 0;
  for (let i = 0; i < 5; i++) {
    askTotal += book.asks[i].volume !== null ? book.asks[i].volume as number : 0;
    bidTotal += book.bids[i].volume !== null ? book.bids[i].volume as number : 0;
  }
  book.askVolume = askTotal;
  book.bidVolume = bidTotal;
  return book;
}

function tickDirection(price: number, last: number, rng: Lcg): TickDirection {
  if (price > last) {
    return 'buy';
  }
  if (price < last) {
    return 'sell';
  }
  return rng.next() > 0.5 ? 'buy' : 'sell';
}

export function buildTicks(quote: QuoteSnapshot, count: number): Tick[] {
  const rng: Lcg = new Lcg(seedOf(quote.code, 'five') + (quote.volume !== null ? quote.volume : 0));
  const ticks: Tick[] = [];
  const last: number = quote.last !== null ? quote.last : 0;
  let price: number = last;
  let time: number = quote.snapshotTime > 0 ? quote.snapshotTime : Date.now();
  for (let i = 0; i < count; i++) {
    const volume: number = Math.round(rng.range(1, 260));
    ticks.push(new Tick(time, price, volume, tickDirection(price, last, rng)));
    price = Math.round((price + rng.range(-0.03, 0.03)) * 100) / 100;
    time -= Math.round(rng.range(1000, 9000));
  }
  return ticks;
}

export function buildNews(code: string, name: string, snapshotTime: number): DetailNews | null {
  // 尾号为 7 的标的不下发资讯，用于验证「整条隐藏且不占位」（FR-06.5）。
  if (code.charCodeAt(code.length - 1) === 55) {
    return null;
  }
  return new DetailNews('news-' + code, `${name}发布三季度业绩预告，净利润同比增长 18.6%`, snapshotTime - 3600000);
}

function buildTimelineSeries(quote: QuoteSnapshot, day: number, index: number, dayStartPrice: number,
  dayEndPrice: number): ChartSeries {
  const prevClose: number = quote.prevClose !== null ? quote.prevClose : 0;
  const rng: Lcg = new Lcg(seedOf(quote.code, 'timeline') + index * 719);
  const points: ChartPoint[] = [];
  let amountSum: number = 0;
  let volumeSum: number = 0;
  for (let i = 0; i <= TIMELINE_MINUTES; i++) {
    const target: number = dayStartPrice + (dayEndPrice - dayStartPrice) * i / TIMELINE_MINUTES;
    const noise: number = rng.range(-0.004, 0.004) * dayStartPrice;
    let price: number = target + noise;
    const upper: number = prevClose * (1 + LIMIT_RATIO);
    const lower: number = prevClose * (1 - LIMIT_RATIO);
    if (prevClose > 0 && price > upper) {
      price = upper;
    }
    if (prevClose > 0 && price < lower) {
      price = lower;
    }
    price = Math.round(price * 100) / 100;
    const volume: number = Math.round(rng.range(300, 18000));
    amountSum += price * volume;
    volumeSum += volume;
    const avg: number = volumeSum > 0 ? amountSum / volumeSum : price;
    points.push(new ChartPoint(timelineTs(day, i), price, price, price, price, volume,
      Math.round(avg * 100) / 100));
  }
  return {
    period: 'timeline',
    points: points,
    prevClose: prevClose,
    limitUp: prevClose * (1 + LIMIT_RATIO),
    limitDown: prevClose * (1 - LIMIT_RATIO)
  };
}

/** 五日：5 个交易日 × 241 点，逐日从上一日收盘推进到当日收盘。 */
function buildFiveSeries(quote: QuoteSnapshot, day: number): ChartSeries {
  const points: ChartPoint[] = [];
  const prevClose: number = quote.prevClose !== null ? quote.prevClose : 0;
  const last: number = quote.last !== null ? quote.last : prevClose;
  const start: number = prevClose > 0 ? prevClose : last;
  for (let d = 0; d < 5; d++) {
    const dayTs: number = day - (4 - d) * DAY_MS;
    const dayStartPrice: number = start + (last - start) * d / 5;
    const dayEndPrice: number = start + (last - start) * (d + 1) / 5;
    const series: ChartSeries = buildTimelineSeries(quote, dayTs, d, dayStartPrice, dayEndPrice);
    for (let i = 0; i < series.points.length; i++) {
      points.push(series.points[i]);
    }
  }
  return {
    period: 'five',
    points: points,
    prevClose: prevClose,
    limitUp: prevClose * (1 + LIMIT_RATIO),
    limitDown: prevClose * (1 - LIMIT_RATIO)
  };
}

function klineStepDays(period: ChartPeriod): number {
  if (period === 'w') {
    return 7;
  }
  if (period === 'm') {
    return 30;
  }
  if (period === 'q') {
    return 91;
  }
  if (period === 'hy') {
    return 182;
  }
  if (period === 'y') {
    return 365;
  }
  return 1;
}

function buildKlineSeries(quote: QuoteSnapshot, period: ChartPeriod, count: number, day: number): ChartSeries {
  const rng: Lcg = new Lcg(seedOf(quote.code, period));
  const last: number = quote.last !== null ? quote.last : 0;
  const stepDays: number = klineStepDays(period);
  const points: ChartPoint[] = [];
  const drift: number = period === 'y' || period === 'hy' ? 0.05 : 0.025;
  let close: number = last > 0 ? last * (1 - drift * Math.min(6, count / 20)) : 10;
  const prevCloseOfLast: number = close;
  for (let i = 0; i < count; i++) {
    const open: number = Math.round(close * 100) / 100;
    const change: number = rng.range(-0.035, 0.038);
    const nextClose: number = Math.round(open * (1 + change) * 100) / 100;
    const high: number = Math.round(Math.max(open, nextClose) * (1 + rng.range(0.001, 0.02)) * 100) / 100;
    const low: number = Math.round(Math.min(open, nextClose) * (1 - rng.range(0.001, 0.02)) * 100) / 100;
    const volume: number = Math.round(rng.range(20000, 900000));
    const ts: number = day - (count - 1 - i) * stepDays * DAY_MS;
    points.push(new ChartPoint(ts, open, high, low, nextClose, volume, nextClose));
    close = nextClose;
  }
  // 末根收敛到最新价：避免随机游走让年K/半年K的右端离当前价太远。
  if (last > 0 && points.length > 0) {
    const tail: ChartPoint = points[points.length - 1];
    if (tail.close > 0) {
      const factor: number = last / tail.close;
      for (let i = 0; i < points.length; i++) {
        const point: ChartPoint = points[i];
        point.open = Math.round(point.open * factor * 100) / 100;
        point.high = Math.round(point.high * factor * 100) / 100;
        point.low = Math.round(point.low * factor * 100) / 100;
        point.close = Math.round(point.close * factor * 100) / 100;
        point.avg = point.close;
      }
    }
  }
  return {
    period: period,
    points: points,
    prevClose: prevCloseOfLast,
    limitUp: prevCloseOfLast * (1 + LIMIT_RATIO),
    limitDown: prevCloseOfLast * (1 - LIMIT_RATIO)
  };
}

/** 生成一个周期的图表数据（首屏与切周期共用）。 */
export function buildChartSeries(quote: QuoteSnapshot, period: ChartPeriod, count: number,
  at: number): ChartSeries {
  const day: number = dayStart(at);
  if (period === 'timeline') {
    const prevClose: number = quote.prevClose !== null ? quote.prevClose : 0;
    const last: number = quote.last !== null ? quote.last : prevClose;
    return buildTimelineSeries(quote, day, 9, prevClose, last);
  }
  if (period === 'five') {
    return buildFiveSeries(quote, day);
  }
  return buildKlineSeries(quote, period, count, day);
}
