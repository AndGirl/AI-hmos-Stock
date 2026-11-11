import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ChartPeriod,
  ChartPoint,
  ChartSeries,
  DetailError,
  DetailListener,
  DetailPatch,
  DetailSnapshot,
  DetailSubscription,
  Market,
  OrderBook,
  OrderLevel,
  QuoteSnapshot,
  StockTag,
  Tick,
  TradeStatus,
  isKlinePeriod
} from 'commons_data';
import {
  DASH,
  formatAmount,
  formatClock,
  formatDate,
  formatMonthDay,
  formatPercent,
  formatPrice,
  formatSigned,
  formatSnapshotTime,
  formatVolume,
  toneOf,
  toneOfDirection,
  ValueTone
} from '../repository/DetailFormat';
import { DetailRepository } from '../repository/DetailRepository';

/** 详情页动作（FR-06.10）：page 在动作栏，compact 收进「⋯」。 */
export type DetailAction = 'watchlist' | 'pk' | 'more' | 'trade';

/** 承载形态（FR-06.1 / §5.3.2）：page 全量、pane 右栏紧凑、window 多窗实例紧凑。 */
export type DetailMode = 'page' | 'pane' | 'window';

export type DetailUiState = 'loading' | 'ready' | 'firstLoadError' | 'notFound';

export type ChartState = 'idle' | 'loading' | 'ready' | 'error';

/** 指标池顺序即 FR-06 §2.2 的优先级序（sm 取前 6、md/lg 取前 9、xl 全 12）。 */
export type MetricKey = 'open' | 'prevClose' | 'turnover' | 'high' | 'low' | 'pe' | 'volume' |
  'amount' | 'marketCap' | 'amplitude' | 'volumeRatio' | 'floatCap';

export const METRIC_ORDER: MetricKey[] = ['open', 'prevClose', 'turnover', 'high', 'low', 'pe',
  'volume', 'amount', 'marketCap', 'amplitude', 'volumeRatio', 'floatCap'];

const CHART_TTL_MS: number = 5 * 60 * 1000;

@ObservedV2
export class MetricVM {
  key: MetricKey;
  @Trace text: string = DASH;
  @Trace tone: ValueTone = 'none';
  @Trace isLoss: boolean = false;

  constructor(key: MetricKey) {
    this.key = key;
  }
}

@ObservedV2
export class OrderLevelVM {
  @Trace priceText: string = DASH;
  @Trace volumeText: string = DASH;
  @Trace tone: ValueTone = 'none';
  @Trace flashSeq: number = 0;
}

@ObservedV2
export class OrderBookVM {
  @Trace asks: OrderLevelVM[] = [];
  @Trace bids: OrderLevelVM[] = [];
  /** 红段（委买占比）宽度百分比，5~95 钳制。 */
  @Trace bidPercent: number = 50;
  @Trace frozen: boolean = false;

  constructor() {
    for (let i = 0; i < 5; i++) {
      this.asks.push(new OrderLevelVM());
      this.bids.push(new OrderLevelVM());
    }
  }
}

@ObservedV2
export class TickVM {
  key: string = '';
  @Trace timeText: string = DASH;
  @Trace priceText: string = DASH;
  @Trace volumeText: string = DASH;
  @Trace tone: ValueTone = 'none';
}

/** 十字光标读数（已格式化，视图直接展示）。 */
export class ChartReadout {
  timeText: string;
  priceText: string;
  avgText: string;
  volumeText: string;
  pctText: string;

  constructor(timeText: string, priceText: string, avgText: string, volumeText: string,
    pctText: string) {
    this.timeText = timeText;
    this.priceText = priceText;
    this.avgText = avgText;
    this.volumeText = volumeText;
    this.pctText = pctText;
  }
}

class ChartCacheEntry {
  series: ChartSeries;
  at: number;

  constructor(series: ChartSeries, at: number) {
    this.series = series;
    this.at = at;
  }
}

class DetailPrefs {
  period: ChartPeriod = 'timeline';
  expanded: boolean = false;
}

/** 跨实例缓存：page ↔ pane 切换不重建周期/展开态（INV-D2）。 */
const PREFS: Map<string, DetailPrefs> = new Map<string, DetailPrefs>();
const SERIES_CACHE: Map<string, ChartCacheEntry> = new Map<string, ChartCacheEntry>();
const NEWS_DISMISSED: Set<string> = new Set<string>();

function seriesKey(code: string, period: ChartPeriod): string {
  return code + ':' + period;
}

/** 状态 → 指标颜色。 */
function priceTone(quote: QuoteSnapshot): ValueTone {
  if (quote.status === 'suspended' || quote.status === 'delisted' || quote.chg === null) {
    return 'none';
  }
  if (quote.chg > 0) {
    return 'up';
  }
  if (quote.chg < 0) {
    return 'down';
  }
  return 'flat';
}

class DetailSink implements DetailListener {
  private handler: (patch: DetailPatch) => void;

  constructor(handler: (patch: DetailPatch) => void) {
    this.handler = handler;
  }

  onPatch(patch: DetailPatch): void {
    this.handler(patch);
  }
}

/**
 * 详情 VM（L3）：首屏状态机、指标/盘口/明细格式化、8 周期图表缓存与 seq 取消。
 * 推送只改 @Trace 字段，整块数组仅在周期切换 / 明细刷新时替换。
 */
@ObservedV2
export class DetailVM {
  @Trace uiState: DetailUiState = 'loading';
  code: string = '';
  @Trace name: string = '';
  @Trace market: Market = 'SH';
  @Trace status: TradeStatus = 'open';
  @Trace tags: StockTag[] = [];
  @Trace priceText: string = DASH;
  @Trace chgText: string = DASH;
  @Trace pctText: string = DASH;
  @Trace priceTone: ValueTone = 'none';
  @Trace timeText: string = DASH;
  @Trace flashSeq: number = 0;
  @Trace metrics: MetricVM[] = [];
  @Trace metricsExpanded: boolean = false;
  @Trace orderBook: OrderBookVM = new OrderBookVM();
  @Trace ticks: TickVM[] = [];
  @Trace newsTitle: string = '';
  @Trace newsVisible: boolean = false;
  @Trace period: ChartPeriod = 'timeline';
  @Trace chartSeries: ChartSeries | null = null;
  @Trace chartState: ChartState = 'idle';

  private repo: DetailRepository = new DetailRepository();
  private loadToken: number = 0;
  private chartToken: number = 0;
  private sub: DetailSubscription | undefined = undefined;
  private lastQuote: QuoteSnapshot | null = null;
  private frozen: boolean = false;
  /** 性能采样起点（AC-65：快照/图表数据耗时，日志 grep DetailPerf）。 */
  private loadStartMs: number = 0;
  private chartStartMs: number = 0;

  constructor(code: string) {
    this.code = code;
    for (let i = 0; i < METRIC_ORDER.length; i++) {
      this.metrics.push(new MetricVM(METRIC_ORDER[i]));
    }
    const prefs: DetailPrefs | undefined = PREFS.get(code);
    if (prefs !== undefined) {
      this.period = prefs.period;
      this.metricsExpanded = prefs.expanded;
    }
    this.newsVisible = false;
  }

  /** 绑定 code（内容组件复用同一 VM 实例，避免 @Local 重新赋值导致视图仍观察旧对象）。 */
  attach(code: string): void {
    this.code = code;
    this.uiState = 'loading';
    const prefs: DetailPrefs | undefined = PREFS.get(code);
    if (prefs !== undefined) {
      this.period = prefs.period;
      this.metricsExpanded = prefs.expanded;
    } else {
      this.period = 'timeline';
      this.metricsExpanded = false;
    }
    this.newsVisible = false;
  }

  load(): void {
    this.dispose();
    this.loadToken++;
    const token: number = this.loadToken;
    this.uiState = 'loading';
    this.loadStartMs = Date.now();
    this.repo.load(this.code).then((snapshot: DetailSnapshot): void => {
      if (token !== this.loadToken) {
        return;
      }
      this.applySnapshot(snapshot);
      this.uiState = 'ready';
      hilog.info(0x0001, 'DetailPerf', 'snapshot code=%{public}s ms=%{public}d',
        this.code, Date.now() - this.loadStartMs);
      this.loadChart(false);
      this.subscribe();
    }).catch((err: Error): void => {
      if (token !== this.loadToken) {
        return;
      }
      hilog.info(0x0001, 'DetailPerf', 'snapshot_fail code=%{public}s ms=%{public}d',
        this.code, Date.now() - this.loadStartMs);
      this.uiState = isNotFound(err) ? 'notFound' : 'firstLoadError';
    });
  }

  retry(): void {
    this.load();
  }

  /** 周期切换：点击即刷新（禁止沿用上一周期画面），5min 内切回走缓存。 */
  selectPeriod(period: ChartPeriod): void {
    if (period === this.period && this.chartState === 'ready') {
      return;
    }
    this.period = period;
    this.persistPrefs();
    this.loadChart(false);
  }

  retryChart(): void {
    this.loadChart(true);
  }

  toggleMetrics(): void {
    this.metricsExpanded = !this.metricsExpanded;
    this.persistPrefs();
  }

  dismissNews(): void {
    this.newsVisible = false;
    NEWS_DISMISSED.add(this.code);
  }

  dispose(): void {
    this.loadToken++;
    this.chartToken++;
    if (this.sub !== undefined) {
      this.sub.unsubscribe();
      this.sub = undefined;
    }
  }

  /** 长按十字光标读数（时间 / 价 / 均价 / 量 / 涨跌幅）。 */
  readoutAt(index: number): ChartReadout | null {
    const series: ChartSeries | null = this.chartSeries;
    if (series === null || index < 0 || index >= series.points.length) {
      return null;
    }
    const point: ChartPoint = series.points[index];
    const kline: boolean = isKlinePeriod(series.period);
    let time: string = formatSnapshotTime(point.ts);
    if (series.period === 'timeline') {
      time = formatClock(point.ts);
    } else if (series.period === 'five') {
      time = formatMonthDay(point.ts);
    } else if (kline) {
      time = formatDate(point.ts);
    }
    let base: number = series.prevClose;
    if (kline && index > 0) {
      base = series.points[index - 1].close;
    }
    const pct: number = base > 0 ? (point.close - base) / base * 100 : 0;
    return new ChartReadout(time, formatPrice(point.close),
      series.period === 'timeline' ? formatPrice(point.avg) : '', formatVolume(point.volume),
      formatSigned(pct, '%'));
  }

  private persistPrefs(): void {
    PREFS.set(this.code, new DetailPrefs());
    const prefs: DetailPrefs | undefined = PREFS.get(this.code);
    if (prefs !== undefined) {
      prefs.period = this.period;
      prefs.expanded = this.metricsExpanded;
    }
  }

  private applySnapshot(snapshot: DetailSnapshot): void {
    this.name = snapshot.name;
    this.market = snapshot.market;
    this.status = snapshot.status;
    this.tags = snapshot.tags;
    const quote: QuoteSnapshot | null = snapshot.quote;
    if (quote !== null) {
      this.lastQuote = quote;
      this.updateQuote(quote);
      this.applyOrderBook(snapshot.orderBook, quote);
    }
    this.applyTicks(snapshot.ticks);
    if (snapshot.news !== null && !NEWS_DISMISSED.has(snapshot.code)) {
      this.newsTitle = snapshot.news.title;
      this.newsVisible = true;
    }
  }

  private subscribe(): void {
    this.sub = this.repo.subscribe(this.code, new DetailSink((patch: DetailPatch): void => {
      this.applyPatch(patch);
    }));
  }

  private applyPatch(patch: DetailPatch): void {
    if (this.frozen) {
      return;
    }
    this.lastQuote = patch.quote;
    this.updateQuote(patch.quote);
    this.applyOrderBook(patch.orderBook, patch.quote);
    this.applyTicks(patch.ticks);
    this.flashSeq++;
  }

  private updateQuote(quote: QuoteSnapshot): void {
    const suspended: boolean = quote.status === 'suspended' || quote.status === 'delisted';
    this.status = quote.status;
    this.priceText = formatPrice(quote.last);
    this.chgText = formatSigned(quote.chg, '');
    this.pctText = formatSigned(quote.pct, '%');
    this.priceTone = suspended ? 'none' : priceTone(quote);
    this.timeText = formatSnapshotTime(quote.snapshotTime);
    this.updateMetrics(quote);
  }

  private updateMetrics(quote: QuoteSnapshot): void {
    const prevClose: number | null = quote.prevClose;
    for (let i = 0; i < this.metrics.length; i++) {
      const metric: MetricVM = this.metrics[i];
      metric.isLoss = false;
      switch (metric.key) {
        case 'open':
          metric.text = formatPrice(quote.open);
          metric.tone = toneOf(quote.open, prevClose);
          break;
        case 'prevClose':
          metric.text = formatPrice(quote.prevClose);
          metric.tone = 'none';
          break;
        case 'turnover':
          metric.text = formatPercent(quote.turnover);
          metric.tone = 'none';
          break;
        case 'high':
          metric.text = formatPrice(quote.high);
          metric.tone = toneOf(quote.high, prevClose);
          break;
        case 'low':
          metric.text = formatPrice(quote.low);
          metric.tone = toneOf(quote.low, prevClose);
          break;
        case 'pe':
          if (quote.pe === null) {
            metric.text = DASH;
          } else if (quote.pe <= 0) {
            metric.text = '';
            metric.isLoss = true;
          } else {
            metric.text = quote.pe.toFixed(2);
          }
          metric.tone = 'none';
          break;
        case 'volume':
          metric.text = formatVolume(quote.volume);
          metric.tone = 'none';
          break;
        case 'amount':
          metric.text = formatAmount(quote.amount);
          metric.tone = 'none';
          break;
        case 'marketCap':
          metric.text = formatAmount(quote.marketCap);
          metric.tone = 'none';
          break;
        case 'amplitude':
          metric.text = formatPercent(quote.amplitude);
          metric.tone = 'none';
          break;
        case 'volumeRatio':
          metric.text = quote.volumeRatio === null || quote.volumeRatio === undefined ?
            DASH : quote.volumeRatio.toFixed(2);
          metric.tone = 'none';
          break;
        case 'floatCap':
          metric.text = formatAmount(quote.floatCap);
          metric.tone = 'none';
          break;
        default:
          metric.text = DASH;
          metric.tone = 'none';
          break;
      }
    }
  }

  private applyOrderBook(book: OrderBook, quote: QuoteSnapshot): void {
    const vm: OrderBookVM = this.orderBook;
    const base: number | null = quote.prevClose;
    vm.frozen = quote.status !== 'open';
    this.applyLevels(vm.asks, book.asks, base, vm.frozen);
    this.applyLevels(vm.bids, book.bids, base, vm.frozen);
    const total: number = book.askVolume + book.bidVolume;
    if (total <= 0 || quote.status === 'suspended' || quote.status === 'delisted') {
      vm.bidPercent = 50;
    } else {
      const pct: number = book.bidVolume / total * 100;
      vm.bidPercent = Math.max(5, Math.min(95, pct));
    }
  }

  private applyLevels(target: OrderLevelVM[], source: OrderLevel[], base: number | null,
    frozen: boolean): void {
    for (let i = 0; i < target.length && i < 5; i++) {
      const level = i < source.length ? source[i] : undefined;
      const vm: OrderLevelVM = target[i];
      const priceText: string = level !== undefined ? formatPrice(level.price) : DASH;
      if (!frozen && vm.priceText !== priceText && vm.priceText !== DASH) {
        vm.flashSeq++;
      }
      vm.priceText = priceText;
      vm.volumeText = level !== undefined && level.volume !== null ? Math.round(level.volume).toString() :
        DASH;
      vm.tone = level !== undefined ? toneOf(level.price, base) : 'none';
    }
  }

  private applyTicks(ticks: Tick[]): void {
    const out: TickVM[] = [];
    for (let i = 0; i < ticks.length; i++) {
      const tick: Tick = ticks[i];
      const vm: TickVM = new TickVM();
      vm.key = tick.time + '-' + i + '-' + tick.price;
      vm.timeText = formatClock(tick.time);
      vm.priceText = formatPrice(tick.price);
      vm.volumeText = Math.round(tick.volume).toString();
      vm.tone = toneOfDirection(tick.direction);
      out.push(vm);
    }
    this.ticks = out;
  }

  private loadChart(force: boolean): void {
    if (this.uiState !== 'ready') {
      return;
    }
    const key: string = seriesKey(this.code, this.period);
    const cached: ChartCacheEntry | undefined = SERIES_CACHE.get(key);
    if (!force && cached !== undefined && Date.now() - cached.at < CHART_TTL_MS) {
      this.chartSeries = cached.series;
      this.chartState = 'ready';
      hilog.info(0x0001, 'DetailPerf', 'chart_cached period=%{public}s', this.period);
      return;
    }
    this.chartToken++;
    const token: number = this.chartToken;
    this.chartState = 'loading';
    this.chartStartMs = Date.now();
    this.repo.loadChart(this.code, this.period).then((series: ChartSeries): void => {
      if (token !== this.chartToken) {
        return;
      }
      SERIES_CACHE.set(key, new ChartCacheEntry(series, Date.now()));
      this.chartSeries = series;
      this.chartState = 'ready';
      hilog.info(0x0001, 'DetailPerf', 'chart period=%{public}s ms=%{public}d points=%{public}d',
        this.period, Date.now() - this.chartStartMs, series.points.length);
    }).catch((): void => {
      if (token !== this.chartToken) {
        return;
      }
      this.chartState = 'error';
      hilog.info(0x0001, 'DetailPerf', 'chart_fail period=%{public}s ms=%{public}d',
        this.period, Date.now() - this.chartStartMs);
    });
  }
}

function isNotFound(err: Error): boolean {
  if (err instanceof DetailError) {
    return (err as DetailError).reason === 'not_found';
  }
  return false;
}

/** 视图层用：指标数量（sm 6 / md/lg 9 / xl 12，展开后 12）。 */
export function visibleMetricCount(viewportWidth: number, expanded: boolean): number {
  if (expanded || viewportWidth >= 1180) {
    return 12;
  }
  if (viewportWidth < 600) {
    return 6;
  }
  return 9;
}

