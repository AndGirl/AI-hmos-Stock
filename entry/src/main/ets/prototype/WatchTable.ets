import { WatchRow, MOCK_ROWS } from './WatchData';

/**
 * V0.2 原型：11 列冻结横滑
 * 结构：左侧固定名称列 + 右侧单一横向 Scroll（表头与数据行同容器）
 * 纵向：右侧 List 滚动，左侧名称列按 scrollY 位移，保证行对齐。
 */

interface ColDef {
  key: string;
  title: string;
  width: number;
}

const COLS: ColDef[] = [
  { key: 'last', title: '最新价', width: 76 },
  { key: 'chg', title: '涨跌', width: 70 },
  { key: 'pct', title: '涨跌幅', width: 78 },
  { key: 'volume', title: '总量', width: 82 },
  { key: 'current', title: '现量', width: 68 },
  { key: 'amount', title: '成交额', width: 78 },
  { key: 'amplitude', title: '振幅', width: 66 },
  { key: 'turnover', title: '换手', width: 66 },
  { key: 'pe', title: '市盈率', width: 70 },
  { key: 'pb', title: '市净率', width: 68 }
];

const TOTAL_W: number = 722;
const NAME_W: number = 112;
const ROW_H: number = 56;
const HEAD_H: number = 40;
const UP: string = '#E8402A';
const DOWN: string = '#12A150';
const FLAT: string = '#7A828F';
const INK: string = '#15171C';
const INK3: string = '#8D95A3';
const LINE: string = '#EEF0F3';

@Component
export struct WatchTable {
  private rows: WatchRow[] = MOCK_ROWS;
  private hScroller: Scroller = new Scroller();
  private listScroller: Scroller = new Scroller();
  @State scrollY: number = 0;

  private dirColor(dir: number): string {
    if (dir > 0) {
      return UP;
    }
    if (dir < 0) {
      return DOWN;
    }
    return FLAT;
  }

  private cellText(row: WatchRow, key: string): string {
    switch (key) {
      case 'last': return row.last;
      case 'chg': return row.chg;
      case 'pct': return row.pct;
      case 'volume': return row.volume;
      case 'current': return row.current;
      case 'amount': return row.amount;
      case 'amplitude': return row.amplitude;
      case 'turnover': return row.turnover;
      case 'pe': return row.pe;
      case 'pb': return row.pb;
      default: return '';
    }
  }

  private cellColor(row: WatchRow, key: string): string {
    if (key === 'last' || key === 'chg' || key === 'pct' || key === 'current') {
      return this.dirColor(row.dir);
    }
    return INK;
  }

  @Builder
  NameCell(row: WatchRow) {
    Column() {
      Text(row.name).fontSize(15).fontColor(INK).fontWeight(FontWeight.Medium)
      Row() {
        Text(row.code).fontSize(10).fontColor(INK3)
        if (row.tag.length > 0) {
          Text(row.tag)
            .fontSize(9)
            .fontColor('#C06AD8')
            .backgroundColor('#F6EDFA')
            .borderRadius(3)
            .padding({ left: 3, right: 3 })
            .margin({ left: 4 })
        }
      }
      .margin({ top: 2 })
    }
    .width(NAME_W)
    .height(ROW_H)
    .padding({ left: 16 })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .border({ width: { bottom: 0.5 }, color: LINE })
  }

  build() {
    Row() {
      Column() {
        Row() {
          Text('股票名称').fontSize(12).fontColor(INK3)
        }
        .width(NAME_W)
        .height(HEAD_H)
        .padding({ left: 16 })
        .alignItems(VerticalAlign.Center)

        Stack() {
          Column() {
            ForEach(this.rows, (row: WatchRow) => {
              this.NameCell(row)
            }, (row: WatchRow) => row.code)
          }
          .width('100%')
          .offset({ y: -this.scrollY })
        }
        .layoutWeight(1)
        .width('100%')
        .clip(true)
        .alignContent(Alignment.TopStart)
      }
      .width(NAME_W)
      .height('100%')

      Scroll(this.hScroller) {
        Column() {
          Row() {
            ForEach(COLS, (col: ColDef) => {
              Text(col.title)
                .fontSize(12)
                .fontColor(INK3)
                .width(col.width)
                .textAlign(TextAlign.End)
                .padding({ right: 6 })
            }, (col: ColDef) => col.key)
          }
          .width(TOTAL_W)
          .height(HEAD_H)
          .alignItems(VerticalAlign.Center)

          List({ scroller: this.listScroller }) {
            ForEach(this.rows, (row: WatchRow) => {
              ListItem() {
                Row() {
                  ForEach(COLS, (col: ColDef) => {
                    Text(this.cellText(row, col.key))
                      .fontSize(13)
                      .fontColor(this.cellColor(row, col.key))
                      .width(col.width)
                      .textAlign(TextAlign.End)
                      .padding({ right: 6 })
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }, (col: ColDef) => col.key)
                }
                .width(TOTAL_W)
                .height(ROW_H)
                .alignItems(VerticalAlign.Center)
                .border({ width: { bottom: 0.5 }, color: LINE })
              }
            }, (row: WatchRow) => row.code)
          }
          .width(TOTAL_W)
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.None)
          .onDidScroll((offset: number, state: ScrollState) => {
            this.scrollY = this.listScroller.currentOffset().yOffset;
          })
        }
        .width(TOTAL_W)
        .height('100%')
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .align(Alignment.TopStart)
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Top)
  }
}
