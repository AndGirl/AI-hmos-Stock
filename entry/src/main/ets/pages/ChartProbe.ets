import {
  LineChart,
  LineChartModel,
  LineData,
  LineDataSet,
  EntryOhos,
  JArrayList,
  CandleStickChart,
  CandleStickChartModel,
  CandleData,
  CandleDataSet,
  CandleEntry,
  XAxis
} from '@ohos/mpchart';

@Entry
@Component
struct ChartProbe {
  private lineModel: LineChartModel = new LineChartModel();
  private candleModel: CandleStickChartModel = new CandleStickChartModel();
  @State costText: string = '绘制中…';

  aboutToAppear(): void {
    const t0: number = Date.now();

    const values: JArrayList<EntryOhos> = new JArrayList<EntryOhos>();
    for (let i = 0; i < 241; i++) {
      values.add(new EntryOhos(i, 20 + Math.sin(i / 18) * 1.2));
    }
    const lineSet: LineDataSet = new LineDataSet(values, '分时');
    lineSet.setColorByColor(0xFFDFA03C);
    lineSet.setCircleRadius(0);
    const lineSets: JArrayList<LineDataSet> = new JArrayList<LineDataSet>();
    lineSets.add(lineSet);
    this.lineModel.setData(new LineData(lineSets));

    const candles: JArrayList<CandleEntry> = new JArrayList<CandleEntry>();
    let base: number = 100;
    for (let i = 0; i < 120; i++) {
      const open: number = base + Math.sin(i / 5) * 2;
      const close: number = base + Math.sin((i + 1) / 5) * 2;
      const high: number = Math.max(open, close) + 1.2;
      const low: number = Math.min(open, close) - 1.2;
      candles.add(new CandleEntry(i, high, low, open, close));
      base = close;
    }
    const candleSet: CandleDataSet = new CandleDataSet(candles, '日K');
    const candleSets: JArrayList<CandleDataSet> = new JArrayList<CandleDataSet>();
    candleSets.add(candleSet);
    this.candleModel.setData(new CandleData(candleSets));

    this.costText = `数据构建耗时 ${Date.now() - t0}ms · 分时 241 点 / K 线 120 根`;
  }

  build() {
    Column() {
      Text('V0.3 图表库验证')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 4 })

      Text(this.costText)
        .fontSize(10)
        .fontColor('#8D95A3')
        .width('100%')
        .padding({ left: 16, bottom: 12 })

      Text('LineChart · 分时 241 点').fontSize(11).fontColor('#5B6270').padding({ left: 16 })
      LineChart({ model: this.lineModel })
        .width('100%')
        .height(280)

      Text('CandleStickChart · 日K 120 根').fontSize(11).fontColor('#5B6270').padding({ left: 16, top: 12 })
      CandleStickChart({ model: this.candleModel })
        .width('100%')
        .height(280)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
