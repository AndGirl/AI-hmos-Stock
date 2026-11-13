import {
  AxisBase,
  BarChartModel,
  BarData,
  BarDataSet,
  BarEntry,
  CandleData,
  CandleDataSet,
  CandleEntry,
  CandleStickChartModel,
  Description,
  EntryOhos,
  Highlight,
  IAxisValueFormatter,
  IBarDataSet,
  JArrayList,
  Legend,
  LimitLine,
  LineChartModel,
  LineData,
  LineDataSet,
  Mode,
  OnChartValueSelectedListener,
  Style,
  XAxis,
  XAxisPosition,
  YAxis
} from '@ohos/mpchart';
import { ChartPeriod, ChartPoint, ChartSeries, isKlinePeriod } from '../model/DetailModels';

/**
 * 图表配色：由 View 层从主题 token 解析成 ARGB 数值后注入，
 * commons/data 内不出现颜色字面量（设计 §6.2）。
 */
export class ChartStyle {
  up: number;
  down: number;
  flat: number;
  line: number;
  avg: number;
  grid: number;
  text: number;
  fill: number;

  constructor(up: number, down: number, flat: number, line: number, avg: number, grid: number,
    text: number, fill: number) {
    this.up = up;
    this.down = down;
    this.flat = flat;
    this.line = line;
    this.avg = avg;
    this.grid = grid;
    this.text = text;
    this.fill = fill;
  }
}

/** 长按十字光标的读数回调（时间/价/均价/量由 View 侧按 index 取点）。 */
export interface ChartSelectionListener {
  onSelect(index: number): void;

  onClear(): void;
}

/** ChartEngine 对外契约（设计 §5.3.4）：上层只认 ChartSeries，换实现零改动。 */
export interface ChartEngine {
  setStyle(style: ChartStyle): void;

  setSeries(series: ChartSeries): void;

  setCrosshairEnabled(enabled: boolean): void;

  setZoomEnabled(enabled: boolean): void;

  resetZoomFor(period: ChartPeriod): void;

  dispose(): void;
}

function pad2(value: number): string {
  return value < 10 ? '0' + value : '' + value;
}

/** X 轴刻度：分时 HH:mm、五日 MM-DD、K 线 YY-MM。 */
class PeriodAxisFormatter implements IAxisValueFormatter {
  private stamps: number[] = [];
  private period: ChartPeriod = 'timeline';

  setData(period: ChartPeriod, points: ChartPoint[]): void {
    this.period = period;
    const stamps: number[] = [];
    for (let i = 0; i < points.length; i++) {
      stamps.push(points[i].ts);
    }
    this.stamps = stamps;
  }

  getFormattedValue(value: number, axis: AxisBase): string {
    const index: number = Math.round(value);
    if (index < 0 || index >= this.stamps.length) {
      return '';
    }
    const date: Date = new Date(this.stamps[index]);
    if (this.period === 'timeline') {
      return pad2(date.getHours()) + ':' + pad2(date.getMinutes());
    }
    if (this.period === 'five') {
      return (date.getMonth() + 1) + '-' + pad2(date.getDate());
    }
    const year: string = '' + date.getFullYear();
    return year.substring(2) + '-' + pad2(date.getMonth() + 1);
  }
}

/** Y 轴价格：两位小数。 */
class PriceAxisFormatter implements IAxisValueFormatter {
  getFormattedValue(value: number, axis: AxisBase): string {
    return value.toFixed(2);
  }
}

class ValueListener implements OnChartValueSelectedListener {
  onValueSelected: (e: EntryOhos, h: Highlight) => void = (): void => {
  };
  onNothingSelected: () => void = (): void => {
  };
}

/**
 * mpchart 适配实现：把三方库的类型 / 生命周期 / 配置关在本文件内（ADR-04）。
 * 一个实例持有「价格图 + 量能图 + K 线图」三个 model，切周期只换 series 不换容器。
 */
export class MpChartEngine implements ChartEngine {
  private style: ChartStyle;
  private lineModel: LineChartModel = new LineChartModel();
  private candleModel: CandleStickChartModel = new CandleStickChartModel();
  private volumeModel: BarChartModel = new BarChartModel();
  private xFormatter: PeriodAxisFormatter = new PeriodAxisFormatter();
  private priceFormatter: PriceAxisFormatter = new PriceAxisFormatter();
  private valueListener: ValueListener = new ValueListener();
  private selection: ChartSelectionListener | undefined = undefined;
  private candleMode: boolean = false;
  private zoomEnabled: boolean = false;
  private crosshairEnabled: boolean = true;
  private pointCount: number = 0;
  private priceSet: LineDataSet | undefined = undefined;
  private avgSet: LineDataSet | undefined = undefined;
  private candleSet: CandleDataSet | undefined = undefined;
  /** 最近一次 series：M12-4 深色切换只换配色时据此重建 DataSet（不重建图表容器/不重置缩放）。 */
  private lastSeries: ChartSeries | undefined = undefined;

  constructor(style: ChartStyle) {
    this.style = style;
    this.configureLineChart();
    this.configureCandleChart();
    this.configureVolumeChart();
    this.valueListener.onValueSelected = (e: EntryOhos, h: Highlight): void => {
      if (this.selection !== undefined) {
        this.selection.onSelect(Math.round(h.getX()));
      }
    };
    this.valueListener.onNothingSelected = (): void => {
      if (this.selection !== undefined) {
        this.selection.onClear();
      }
    };
    this.lineModel.setOnChartValueSelectedListener(this.valueListener);
    this.candleModel.setOnChartValueSelectedListener(this.valueListener);
  }

  priceModel(): LineChartModel {
    return this.lineModel;
  }

  candlePriceModel(): CandleStickChartModel {
    return this.candleModel;
  }

  volumeBarModel(): BarChartModel {
    return this.volumeModel;
  }

  isCandleMode(): boolean {
    return this.candleMode;
  }

  setSelectionListener(listener: ChartSelectionListener): void {
    this.selection = listener;
  }

  setStyle(style: ChartStyle): void {
    this.style = style;
    this.configureLineChart();
    this.configureCandleChart();
    this.configureVolumeChart();
    // 重着色：用同一份 series 重建 DataSet（颜色写在 DataSet 上），
    // 图表容器/视口矩阵不变，因此缩放位置保留（M12-4「切换深色不重建图表」）。
    if (this.lastSeries !== undefined) {
      this.setSeries(this.lastSeries);
    }
  }

  setSeries(series: ChartSeries): void {
    this.lastSeries = series;
    this.candleMode = isKlinePeriod(series.period);
    this.pointCount = series.points.length;
    this.xFormatter.setData(series.period, series.points);
    const volumeEntries: JArrayList<BarEntry> = new JArrayList<BarEntry>();
    const volumeColors: number[] = [];
    for (let i = 0; i < series.points.length; i++) {
      const point: ChartPoint = series.points[i];
      volumeEntries.add(new BarEntry(i, point.volume));
      const up: boolean = series.prevClose > 0 ? point.close >= series.prevClose : point.close >= point.open;
      volumeColors.push(up ? this.withAlpha(this.style.up, 0.35) : this.withAlpha(this.style.down, 0.35));
    }
    if (this.candleMode) {
      this.applyCandles(series);
      this.candleModel.notifyDataSetChanged();
      this.candleModel.invalidate();
    } else {
      this.applyLines(series);
      this.lineModel.notifyDataSetChanged();
      this.lineModel.invalidate();
    }
    this.fillVolume(volumeEntries, volumeColors);
    this.volumeModel.notifyDataSetChanged();
    this.volumeModel.invalidate();
  }

  setCrosshairEnabled(enabled: boolean): void {
    this.crosshairEnabled = enabled;
    if (this.candleMode) {
      this.candleModel.setHighlightPerLongPressEnabled(enabled);
      this.candleModel.setHighlightPerTapEnabled(false);
      this.candleModel.setDrawMarkers(false);
      this.applyCrosshairStyles();
      this.candleModel.invalidate();
      return;
    }
    this.lineModel.setHighlightPerLongPressEnabled(enabled);
    this.lineModel.setHighlightPerTapEnabled(false);
    this.lineModel.setDrawMarkers(false);
    this.applyCrosshairStyles();
    this.lineModel.invalidate();
  }

  private applyCrosshairStyles(): void {
    if (this.priceSet !== undefined) {
      this.priceSet.setDrawVerticalHighlightIndicator(this.crosshairEnabled);
      this.priceSet.setDrawHorizontalHighlightIndicator(this.crosshairEnabled);
      this.priceSet.setHighlightLineWidth(0.8);
      this.priceSet.setHighLightColor(this.style.text);
    }
    if (this.candleSet !== undefined) {
      this.candleSet.setDrawVerticalHighlightIndicator(this.crosshairEnabled);
      this.candleSet.setDrawHorizontalHighlightIndicator(this.crosshairEnabled);
      this.candleSet.setHighlightLineWidth(0.8);
      this.candleSet.setHighLightColor(this.style.text);
    }
  }

  setZoomEnabled(enabled: boolean): void {
    this.zoomEnabled = enabled;
    if (this.candleMode) {
      this.candleModel.setScaleEnabled(enabled);
      this.candleModel.setPinchZoom(enabled);
      this.candleModel.setDragEnabled(enabled);
      this.candleModel.invalidate();
      return;
    }
    this.lineModel.setScaleEnabled(enabled);
    this.lineModel.setPinchZoom(enabled);
    this.lineModel.setDragEnabled(enabled);
    this.lineModel.invalidate();
  }

  resetZoomFor(period: ChartPeriod): void {
    const visible: number = this.pointCount > 60 ? 60 : this.pointCount;
    if (this.candleMode) {
      this.candleModel.setVisibleXRangeMaximum(visible);
      this.candleModel.moveViewToX(this.pointCount > 60 ? this.pointCount - 60 : 0);
      this.candleModel.invalidate();
      return;
    }
    this.lineModel.setVisibleXRangeMaximum(visible);
    this.lineModel.moveViewToX(0);
    this.lineModel.invalidate();
  }

  dispose(): void {
    this.selection = undefined;
    this.lineModel.setData(null);
    this.candleModel.setData(null);
    this.volumeModel.setData(null);
    this.lineModel.clearJobs();
    this.candleModel.clearJobs();
    this.volumeModel.clearJobs();
  }

  private applyLines(series: ChartSeries): void {
    const priceEntries: JArrayList<EntryOhos> = new JArrayList<EntryOhos>();
    const avgEntries: JArrayList<EntryOhos> = new JArrayList<EntryOhos>();
    for (let i = 0; i < series.points.length; i++) {
      const point: ChartPoint = series.points[i];
      priceEntries.add(new EntryOhos(i, point.close));
      avgEntries.add(new EntryOhos(i, point.avg));
    }
    const priceSet: LineDataSet = new LineDataSet(priceEntries, 'price');
    priceSet.setMode(Mode.LINEAR);
    priceSet.setDrawCircles(false);
    priceSet.setDrawCircleHole(false);
    priceSet.setDrawValues(false);
    priceSet.setLineWidth(1.2);
    priceSet.setColorsByArr([this.style.line]);
    priceSet.setDrawFilled(true);
    priceSet.setFillColor(this.style.fill);
    priceSet.setFillAlpha(60);
    priceSet.setHighlightEnabled(true);
    priceSet.setDrawVerticalHighlightIndicator(this.crosshairEnabled);
    priceSet.setDrawHorizontalHighlightIndicator(this.crosshairEnabled);
    priceSet.setHighlightLineWidth(0.8);
    priceSet.setHighLightColor(this.style.text);
    this.priceSet = priceSet;

    const avgSet: LineDataSet = new LineDataSet(avgEntries, 'avg');
    avgSet.setMode(Mode.LINEAR);
    avgSet.setDrawCircles(false);
    avgSet.setDrawValues(false);
    avgSet.setLineWidth(1);
    avgSet.setColorsByArr([this.style.avg]);
    avgSet.setHighlightEnabled(false);
    this.avgSet = avgSet;

    this.lineModel.setData(new LineData([priceSet, avgSet]));
    this.applyPrevCloseLine(this.lineModel.getAxisRight(), series.prevClose);
  }

  private applyCandles(series: ChartSeries): void {
    const candleEntries: JArrayList<CandleEntry> = new JArrayList<CandleEntry>();
    for (let i = 0; i < series.points.length; i++) {
      const point: ChartPoint = series.points[i];
      candleEntries.add(new CandleEntry(i, point.high, point.low, point.open, point.close));
    }
    const set: CandleDataSet = new CandleDataSet(candleEntries, 'candle');
    set.setShowCandleBar(true);
    set.setIncreasingColor(this.style.up);
    set.setDecreasingColor(this.style.down);
    set.setNeutralColor(this.style.flat);
    set.setIncreasingPaintStyle(Style.FILL);
    set.setDecreasingPaintStyle(Style.FILL);
    set.setShadowColorSameAsCandle(true);
    set.setShadowWidth(0.7);
    set.setBarSpace(0.25);
    set.setDrawValues(false);
    set.setHighlightEnabled(true);
    set.setDrawVerticalHighlightIndicator(this.crosshairEnabled);
    set.setDrawHorizontalHighlightIndicator(this.crosshairEnabled);
    set.setHighlightLineWidth(0.8);
    set.setHighLightColor(this.style.text);
    this.candleSet = set;

    this.candleModel.setData(new CandleData([set]));
    // K 线不画昨收基准线（昨收只对分时/五日有意义，避免误导）。
    const axis: YAxis | null = this.candleModel.getAxisRight();
    if (axis !== null) {
      axis.removeAllLimitLines();
    }
  }

  private fillVolume(entries: JArrayList<BarEntry>, colors: number[]): void {
    const set: BarDataSet = new BarDataSet(entries, 'volume');
    set.setColorsByArr(colors);
    set.setDrawValues(false);
    set.setHighlightEnabled(false);
    const list: JArrayList<IBarDataSet> = new JArrayList<IBarDataSet>();
    list.add(set);
    this.volumeModel.setData(new BarData(list));
  }

  private applyPrevCloseLine(axis: YAxis | null, prevClose: number): void {
    if (axis === null) {
      return;
    }
    axis.removeAllLimitLines();
    if (prevClose <= 0) {
      return;
    }
    const line: LimitLine = new LimitLine(prevClose, '');
    line.setLineColor(this.style.text);
    line.setLineWidth(0.6);
    line.enableDashedLine(4, 4, 0);
    line.setLabel('');
    axis.addLimitLine(line);
  }

  private configureLineChart(): void {
    const model: LineChartModel = this.lineModel;
    const desc: Description | null = model.getDescription();
    if (desc !== null) {
      desc.setEnabled(false);
    }
    const legend: Legend | null = model.getLegend();
    if (legend !== null) {
      legend.setEnabled(false);
    }
    model.setDrawGridBackground(false);
    model.setDrawBorders(false);
    model.setAutoScaleMinMaxEnabled(false);
    model.setTouchEnabled(true);
    model.setDragEnabled(this.zoomEnabled);
    model.setScaleEnabled(this.zoomEnabled);
    model.setPinchZoom(this.zoomEnabled);
    model.setHighlightPerTapEnabled(false);
    model.setHighlightPerLongPressEnabled(true);
    model.setDrawMarkers(false);
    model.setNoDataText('');
    this.configureXAxis(model.getXAxis(), false);
    this.configureYAxis(model.getAxisLeft(), model.getAxisRight());
  }

  private configureCandleChart(): void {
    const model: CandleStickChartModel = this.candleModel;
    const desc: Description | null = model.getDescription();
    if (desc !== null) {
      desc.setEnabled(false);
    }
    const legend: Legend | null = model.getLegend();
    if (legend !== null) {
      legend.setEnabled(false);
    }
    model.setDrawGridBackground(false);
    model.setDrawBorders(false);
    model.setAutoScaleMinMaxEnabled(false);
    model.setTouchEnabled(true);
    model.setDragEnabled(this.zoomEnabled);
    model.setScaleEnabled(this.zoomEnabled);
    model.setPinchZoom(this.zoomEnabled);
    model.setHighlightPerTapEnabled(false);
    model.setHighlightPerLongPressEnabled(true);
    model.setDrawMarkers(false);
    model.setNoDataText('');
    this.configureXAxis(model.getXAxis(), false);
    this.configureYAxis(model.getAxisLeft(), model.getAxisRight());
  }

  private configureVolumeChart(): void {
    const model: BarChartModel = this.volumeModel;
    const desc: Description | null = model.getDescription();
    if (desc !== null) {
      desc.setEnabled(false);
    }
    const legend: Legend | null = model.getLegend();
    if (legend !== null) {
      legend.setEnabled(false);
    }
    model.setDrawGridBackground(false);
    model.setDrawBorders(false);
    model.setTouchEnabled(false);
    model.setScaleEnabled(false);
    model.setPinchZoom(false);
    model.setDragEnabled(false);
    model.setNoDataText('');
    const xAxis: XAxis | null = model.getXAxis();
    if (xAxis !== null) {
      xAxis.setDrawGridLines(false);
      xAxis.setDrawAxisLine(false);
      xAxis.setTextColor(this.style.text);
      xAxis.setTextSize(9);
      xAxis.setLabelCount(4, false);
      xAxis.setGranularity(1);
      xAxis.setGranularityEnabled(true);
      xAxis.setValueFormatter(this.xFormatter);
      xAxis.setDrawLabels(true);
    }
    const left: YAxis | null = model.getAxisLeft();
    if (left !== null) {
      left.setEnabled(false);
    }
    const right: YAxis | null = model.getAxisRight();
    if (right !== null) {
      right.setEnabled(false);
    }
  }

  private configureXAxis(xAxis: XAxis | null, drawLabels: boolean): void {
    if (xAxis === null) {
      return;
    }
    xAxis.setPosition(XAxisPosition.BOTTOM);
    xAxis.setDrawGridLines(false);
    xAxis.setDrawAxisLine(false);
    xAxis.setDrawLabels(drawLabels);
    xAxis.setTextColor(this.style.text);
    xAxis.setTextSize(9);
    xAxis.setLabelCount(4, false);
    xAxis.setGranularity(1);
    xAxis.setGranularityEnabled(true);
    xAxis.setAvoidFirstLastClipping(true);
    xAxis.setValueFormatter(this.xFormatter);
  }

  private configureYAxis(left: YAxis | null, right: YAxis | null): void {
    if (left !== null) {
      left.setEnabled(false);
    }
    if (right !== null) {
      right.setEnabled(true);
      right.setDrawGridLines(true);
      right.setGridColor(this.style.grid);
      right.setGridLineWidth(0.5);
      right.setDrawAxisLine(false);
      right.setTextColor(this.style.text);
      right.setTextSize(9);
      right.setLabelCount(4);
      right.setValueFormatter(this.priceFormatter);
      right.setDrawZeroLine(false);
    }
  }

  private withAlpha(color: number, alpha: number): number {
    const a: number = Math.round(alpha * 255);
    return (a << 24) | (color & 0x00FFFFFF);
  }
}

export function createChartEngine(style: ChartStyle): MpChartEngine {
  return new MpChartEngine(style);
}
