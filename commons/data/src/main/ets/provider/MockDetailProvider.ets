import {
  ConnectionState,
  QuoteListener,
  QuotePatch,
  QuoteProvider,
  QuoteSnapshot,
  QuoteSubscription
} from '../model/QuoteModels';
import {
  ChartPeriod,
  ChartSeries,
  DetailError,
  DetailListener,
  DetailPatch,
  DetailProvider,
  DetailSnapshot,
  DetailSubscription,
  KLINE_MAX_COUNT,
  KLINE_PAGE_SIZE,
  OrderBook,
  Tick,
  TickDirection,
  TIMELINE_POINT_COUNT
} from '../model/DetailModels';
import { buildStockSeeds, StockSeed } from '../mock/MarketSeeds';
import { buildChartSeries, buildNews, buildOrderBook, buildTags, buildTicks } from '../mock/DetailSeeds';
import { MockFaults } from '../mock/MockFaults';

const PUSH_INTERVAL_MS: number = 1000;
const DETAIL_LATENCY_MS: number = 180;
const CHART_LATENCY_MS: number = 120;
const TICK_POOL_SIZE: number = 20;

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: (value: void) => void): void => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}

/** 保持 quote provider 心跳的哑监听（详情自己按 1s 读快照）。 */
class KeepAliveListener implements QuoteListener {
  onPatch(patch: QuotePatch): void {
  }

  onStatus(state: ConnectionState): void {
  }
}

/**
 * 停牌快照的价格字段是 null，但历史图表仍应可看（FR-06.6 异常口径）：
 * 用种子基准价补出一份“停牌前”的行情给图表生成器。
 */
function withHistoryPrices(quote: QuoteSnapshot, fallback: number): QuoteSnapshot {
  if (quote.last !== null && quote.prevClose !== null) {
    return quote;
  }
  const history: QuoteSnapshot = {
    code: quote.code,
    market: quote.market,
    name: quote.name,
    status: 'closed',
    snapshotTime: quote.snapshotTime,
    isNew: false,
    last: fallback,
    prevClose: fallback * 0.985,
    chg: 0,
    pct: 0,
    volume: quote.volume,
    lastVolume: null,
    amount: quote.amount,
    amplitude: null,
    turnover: null,
    pe: quote.pe,
    pb: quote.pb
  };
  return history;
}

class DetailSubEntry {
  code: string;
  listener: DetailListener;
  keepAlive: QuoteSubscription;

  constructor(code: string, listener: DetailListener, keepAlive: QuoteSubscription) {
    this.code = code;
    this.listener = listener;
    this.keepAlive = keepAlive;
  }
}

class DetailSubscriptionImpl implements DetailSubscription {
  private provider: MockDetailProvider;
  private entry: DetailSubEntry;
  private active: boolean = true;

  constructor(provider: MockDetailProvider, entry: DetailSubEntry) {
    this.provider = provider;
    this.entry = entry;
  }

  unsubscribe(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.provider.removeEntry(this.entry);
  }
}

/**
 * Mock 详情源：首屏快照 + 8 周期图表 + 1s 盘口/逐笔推送。
 * 快照价格复用 QuoteProvider（与自选列表同源），盘口/逐笔按快照派生。
 */
export class MockDetailProvider implements DetailProvider {
  private quotes: QuoteProvider;
  private seeds: Map<string, StockSeed> = new Map<string, StockSeed>();
  private cache: Map<string, DetailSnapshot> = new Map<string, DetailSnapshot>();
  private ticks: Map<string, Tick[]> = new Map<string, Tick[]>();
  private entries: DetailSubEntry[] = [];
  private timerId: number = -1;
  private keepAliveListener: KeepAliveListener = new KeepAliveListener();

  constructor(quotes: QuoteProvider) {
    this.quotes = quotes;
    const seeds: StockSeed[] = buildStockSeeds();
    for (let i = 0; i < seeds.length; i++) {
      this.seeds.set(seeds[i].code, seeds[i]);
    }
  }

  async loadDetail(code: string): Promise<DetailSnapshot> {
    if (this.seeds.get(code) === undefined) {
      throw new DetailError('not_found', 'unknown code ' + code);
    }
    if (MockFaults.failDetail) {
      throw new DetailError('internal', 'mock detail failure');
    }
    await delay(DETAIL_LATENCY_MS);
    const quote: QuoteSnapshot = await this.quoteOf(code);
    const snapshot: DetailSnapshot = new DetailSnapshot();
    snapshot.code = code;
    snapshot.name = quote.name;
    snapshot.market = quote.market;
    snapshot.status = quote.status;
    snapshot.snapshotTime = quote.snapshotTime;
    snapshot.tags = buildTags(quote);
    snapshot.quote = quote;
    snapshot.orderBook = buildOrderBook(quote);
    snapshot.ticks = buildTicks(quote, TICK_POOL_SIZE);
    snapshot.news = buildNews(code, quote.name, quote.snapshotTime);
    this.ticks.set(code, snapshot.ticks);
    this.cache.set(code, snapshot);
    return snapshot;
  }

  async loadChart(code: string, period: ChartPeriod, count?: number): Promise<ChartSeries> {
    if (MockFaults.failChart) {
      throw new DetailError('internal', 'mock chart failure');
    }
    const cached: DetailSnapshot | undefined = this.cache.get(code);
    let quote: QuoteSnapshot;
    if (cached !== undefined && cached.quote !== null) {
      quote = cached.quote;
    } else {
      if (this.seeds.get(code) === undefined) {
        throw new DetailError('not_found', 'unknown code ' + code);
      }
      quote = await this.quoteOf(code);
    }
    await delay(CHART_LATENCY_MS);
    const seed: StockSeed | undefined = this.seeds.get(code);
    if (seed !== undefined && seed.isNew) {
      // 新股无历史：返回空序列，由视图展示「暂无历史数据」（FR-06.6）。
      const empty: ChartSeries = {
        period: period,
        points: [],
        prevClose: 0,
        limitUp: 0,
        limitDown: 0
      };
      return empty;
    }
    const chartSource: QuoteSnapshot = withHistoryPrices(quote, seed !== undefined ? seed.base : 10);
    let size: number = TIMELINE_POINT_COUNT;
    if (period !== 'timeline' && period !== 'five') {
      size = count !== undefined ? count : KLINE_PAGE_SIZE;
      size = Math.max(KLINE_PAGE_SIZE, Math.min(KLINE_MAX_COUNT, size));
    }
    return buildChartSeries(chartSource, period, size, Date.now());
  }

  subscribe(code: string, listener: DetailListener): DetailSubscription {
    const keepAlive: QuoteSubscription = this.quotes.subscribe([code], this.keepAliveListener);
    const entry: DetailSubEntry = new DetailSubEntry(code, listener, keepAlive);
    this.entries.push(entry);
    this.ensureTimer();
    return new DetailSubscriptionImpl(this, entry);
  }

  cachedDetail(code: string): DetailSnapshot | undefined {
    return this.cache.get(code);
  }

  removeEntry(entry: DetailSubEntry): void {
    const index: number = this.entries.indexOf(entry);
    if (index >= 0) {
      this.entries.splice(index, 1);
    }
    entry.keepAlive.unsubscribe();
    if (this.entries.length === 0) {
      this.stopTimer();
    }
  }

  private async quoteOf(code: string): Promise<QuoteSnapshot> {
    const list: QuoteSnapshot[] = await this.quotes.getSnapshots([code]);
    if (list.length === 0) {
      throw new DetailError('not_found', 'unknown code ' + code);
    }
    return list[0];
  }

  private ensureTimer(): void {
    if (this.timerId !== -1) {
      return;
    }
    this.timerId = setInterval((): void => {
      this.push().catch((): void => {
      });
    }, PUSH_INTERVAL_MS);
  }

  private stopTimer(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private async push(): Promise<void> {
    const codes: Set<string> = new Set<string>();
    for (let i = 0; i < this.entries.length; i++) {
      codes.add(this.entries[i].code);
    }
    const list: string[] = Array.from(codes);
    if (list.length === 0) {
      return;
    }
    const snapshots: QuoteSnapshot[] = await this.quotes.getSnapshots(list);
    const byCode: Map<string, QuoteSnapshot> = new Map<string, QuoteSnapshot>();
    for (let i = 0; i < snapshots.length; i++) {
      byCode.set(snapshots[i].code, snapshots[i]);
    }
    for (let i = 0; i < this.entries.length; i++) {
      const entry: DetailSubEntry = this.entries[i];
      const quote: QuoteSnapshot | undefined = byCode.get(entry.code);
      if (quote === undefined) {
        continue;
      }
      const frozen: boolean = quote.status === 'suspended' || quote.status === 'delisted';
      let ticks: Tick[] | undefined = this.ticks.get(entry.code);
      if (ticks === undefined) {
        ticks = [];
      }
      let nextTicks: Tick[] = ticks;
      if (!frozen && quote.last !== null) {
        let direction: TickDirection = 'neutral';
        if (quote.chg !== null && quote.chg > 0) {
          direction = 'buy';
        } else if (quote.chg !== null && quote.chg < 0) {
          direction = 'sell';
        }
        const next: Tick[] = [];
        next.push(new Tick(quote.snapshotTime, quote.last, 1 + Math.round(Math.random() * 200), direction));
        for (let j = 0; j < ticks.length && j < TICK_POOL_SIZE - 1; j++) {
          next.push(ticks[j]);
        }
        nextTicks = next;
      }
      this.ticks.set(entry.code, nextTicks);
      const orderBook: OrderBook = buildOrderBook(quote);
      const cached: DetailSnapshot | undefined = this.cache.get(entry.code);
      if (cached !== undefined) {
        cached.quote = quote;
        cached.orderBook = orderBook;
        cached.ticks = nextTicks;
        cached.snapshotTime = quote.snapshotTime;
      }
      entry.listener.onPatch(new DetailPatch(quote, orderBook, nextTicks));
    }
  }
}
