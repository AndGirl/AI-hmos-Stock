import { AppColor, AppDim } from 'commons_ui';
import { OrderLevelVM, OrderBookVM, TickVM } from '../viewmodel/DetailVM';
import { toneColor } from './DetailLabels';
import { DETAIL_BLOCK_HEIGHT } from './DetailLayout';

/** 单档：价格按昨收着色，档位变动闪一次（FR-06.8）。 */
@ComponentV2
struct OrderLevelRow {
  @Param level: OrderLevelVM = new OrderLevelVM();
  @Param sideSymbol: Resource = $r('app.string.detail_ask');
  @Param indexText: string = '';
  @Param frozen: boolean = false;
  @Local flashAlpha: number = 0;

  @Monitor('level.flashSeq')
  onFlash(): void {
    if (this.frozen) {
      return;
    }
    this.flashAlpha = 0.16;
    this.getUIContext().animateTo({ duration: 320, curve: Curve.EaseOut }, () => {
      this.flashAlpha = 0;
    });
  }

  build() {
    Stack() {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(toneColor(this.level.tone))
        .opacity(this.flashAlpha)
      Row() {
        Text(this.sideSymbol)
          .fontSize(10)
          .fontColor(AppColor.textSecondary)
          .width(11)
        Text(this.indexText)
          .fontSize(10)
          .fontColor(AppColor.textSecondary)
          .width(7)
        Text(this.level.priceText)
          .fontSize(11)
          .fontColor(this.frozen ? AppColor.disabledText : toneColor(this.level.tone))
          .layoutWeight(1)
          .textAlign(TextAlign.End)
        Text(this.level.volumeText)
          .fontSize(10)
          .fontColor(AppColor.textSecondary)
          .width(38)
          .textAlign(TextAlign.End)
          .maxLines(1)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 4, right: 4 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(18)
    .accessibilityGroup(true)
  }
}

/** 五档列（买/卖共用；narrow 时左右并排）。 */
@ComponentV2
struct LevelColumn {
  @Param levels: OrderLevelVM[] = [];
  @Param side: string = 'ask';
  @Param frozen: boolean = false;
  @Param title: string = '';

  build() {
    Column() {
      if (this.title.length > 0) {
        Text(this.title)
          .fontSize(10)
          .fontColor(AppColor.textSecondary)
          .width('100%')
          .padding({ left: 4, bottom: 2 })
      }
      ForEach(this.levels, (level: OrderLevelVM, index: number) => {
        OrderLevelRow({
          level: level,
          sideSymbol: this.side === 'ask' ? $r('app.string.detail_ask') : $r('app.string.detail_bid'),
          indexText: '' + (index + 1),
          frozen: this.frozen
        })
      }, (level: OrderLevelVM, index: number) => this.side + index)
    }
    .width('100%')
  }
}

/**
 * 盘口 + 成交明细（FR-06.8）：五档行情 → 卖1~5 → 红绿比例条 → 买1~5 → 成交明细。
 * 停牌/收盘后整块置灰、隐藏比例条、明细不再追加。
 */
@ComponentV2
export struct OrderBookPanel {
  @Param book: OrderBookVM = new OrderBookVM();
  @Param ticks: TickVM[] = [];
  @Param narrow: boolean = false;

  build() {
    Column() {
      Text($r('app.string.detail_orderbook_title'))
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.orderBookTitleText)
        .width('100%')
        .height(20)
        .textAlign(TextAlign.Center)
        .backgroundColor(AppColor.orderBookTitleBg)

      if (this.narrow) {
        Row() {
          Column() {
            LevelColumn({
              levels: this.book.asks,
              side: 'ask',
              frozen: this.book.frozen,
              title: ''
            })
          }
          .layoutWeight(1)

          Column() {
            LevelColumn({
              levels: this.book.bids,
              side: 'bid',
              frozen: this.book.frozen,
              title: ''
            })
          }
          .layoutWeight(1)
          .margin({ left: AppDim.gap8 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      } else {
        LevelColumn({ levels: this.book.asks, side: 'ask', frozen: this.book.frozen, title: '' })
      }

      if (!this.book.frozen) {
        Row() {
          Row()
            .width(this.book.bidPercent.toFixed(2) + '%')
            .height(5)
            .backgroundColor(AppColor.priceUp)
          Row()
            .layoutWeight(1)
            .height(5)
            .backgroundColor(AppColor.priceDown)
        }
        .width('100%')
        .height(5)
        .borderRadius(2.5)
        .clip(true)
        .margin({ top: 3, bottom: 3 })
      }

      if (!this.narrow) {
        LevelColumn({ levels: this.book.bids, side: 'bid', frozen: this.book.frozen, title: '' })
      }

      Text($r('app.string.detail_ticks_title'))
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textSecondary)
        .width('100%')
        .height(20)
        .textAlign(TextAlign.Center)
        .backgroundColor(AppColor.bgSurface)
        .margin({ top: AppDim.gap4 })

      List() {
        ForEach(this.ticks, (tick: TickVM) => {
          ListItem() {
            Row() {
              Text(tick.timeText)
                .fontSize(10)
                .fontColor(AppColor.textSecondary)
                .width(48)
              Text(tick.priceText)
                .fontSize(10)
                .fontColor(this.book.frozen ? AppColor.disabledText : toneColor(tick.tone))
                .layoutWeight(1)
                .textAlign(TextAlign.End)
              Text(tick.volumeText)
                .fontSize(10)
                .fontColor(AppColor.textSecondary)
                .width(34)
                .textAlign(TextAlign.End)
                .maxLines(1)
            }
            .width('100%')
            .height(16)
            .padding({ left: 4, right: 4 })
            .accessibilityGroup(true)
          }
        }, (tick: TickVM) => tick.key)
      }
      .width('100%')
      .layoutWeight(1)

      .scrollBar(BarState.Off)
      .cachedCount(4)
    }
    .width('100%')
    .height(DETAIL_BLOCK_HEIGHT)
    .alignItems(HorizontalAlign.Start)
  }
}

