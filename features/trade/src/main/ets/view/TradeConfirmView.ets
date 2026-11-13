import { AppColor } from 'commons_ui';
import { TradeVM } from '../viewmodel/TradeVM';
import { blockText, failText, queryStatusText } from './TradeText';

/**
 * 确认层（FR-07.7）：四项摘要（账户 / 标的 / 价格 / 数量）与编辑层逐字一致，
 * 不含金额与手续费；提交三态 + 结果未知的「查询委托」；点遮罩不关闭（由壳处理）。
 */
@ComponentV2
export struct TradeConfirmView {
  @Param vm: TradeVM = new TradeVM();
  @Param bottomInset: number = 0;
  /** 键盘弹起：收紧间距并把主按钮顶到键盘上沿（FR-07.2）。 */
  @Param keyboardUp: boolean = false;

  private ctaEnabled(): boolean {
    // 断线 / 非交易时段 / 资金不足：确认层与编辑层同口径禁用（FR-07.10）。
    return !this.vm.submitting && !this.vm.unknown && this.vm.blockCode === '';
  }

  @Builder
  backButton() {
    Stack() {
      Text('\u2039')
        .fontSize(22)
        .fontColor(AppColor.textPrimary)
    }
    .width(32)
    .height(32)
    .borderRadius(16)
    .backgroundColor(AppColor.bgSurface)
    .accessibilityGroup(true)
    .accessibilityText($r('app.string.trade_back'))
    .onClick(() => {
      this.vm.back();
    })
  }

  @Builder
  closeButton() {
    Stack() {
      Text('\u2715')
        .fontSize(15)
        .fontColor(AppColor.textSecondary)
    }
    .width(32)
    .height(32)
    .borderRadius(16)
    .backgroundColor(AppColor.bgSurface)
    .accessibilityGroup(true)
    .accessibilityText($r('app.string.trade_close'))
    .onClick(() => {
      this.vm.tryClose();
    })
  }

  @Builder
  header() {
    Row() {
      this.backButton()
      Column() {
        Text($r('app.string.trade_title_confirm'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.textPrimary)
        Text(this.vm.symbolText + ' ' + this.vm.codeText)
          .fontSize(12)
          .fontColor(AppColor.textSecondary)
          .margin({ top: 2 })
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)

      this.closeButton()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  accountRow() {
    Row() {
      Text($r('app.string.trade_account'))
        .fontSize(14)
        .fontColor(AppColor.textSecondary)
      Text(this.vm.accountText)
        .fontSize(14)
        .fontColor(AppColor.textPrimary)
        .margin({ left: 4 })
    }
    .width('100%')
    .margin({ top: 20 })
    .accessibilityGroup(true)
    .accessibilityText($r('app.string.trade_a11y_account'))
  }

  @Builder
  summaryRow(label: Resource, value: string, valueColor: Resource, a11y: Resource) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontColor(AppColor.textPrimary)
      Blank()
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(valueColor)
    }
    .width('100%')
    .height(56)
    .alignItems(VerticalAlign.Center)
    .accessibilityGroup(true)
    .accessibilityText(a11y)
  }

  @Builder
  blockBanner() {
    Row() {
      Text(blockText(this.vm.blockCode, this.vm.canBuyText))
        .fontSize(13)
        .fontColor(AppColor.error)
    }
    .width('100%')
    .padding(10)
    .margin({ top: 12 })
    .backgroundColor(AppColor.bannerBg)
    .borderRadius(8)
  }

  @Builder
  failBanner() {
    Row() {
      Text(failText(this.vm.failCode))
        .fontSize(13)
        .fontColor(AppColor.error)
    }
    .width('100%')
    .padding(10)
    .margin({ top: 12 })
    .backgroundColor(AppColor.bannerBg)
    .borderRadius(8)
  }

  @Builder
  queryResult() {
    Column() {
      Row() {
        Text($r('app.string.trade_query_order_id'))
          .fontSize(12)
          .fontColor(AppColor.textSecondary)
        Text(this.vm.queryOrderId.length > 0 ? this.vm.queryOrderId : '--')
          .fontSize(12)
          .fontColor(AppColor.textPrimary)
          .margin({ left: 8 })
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      Row() {
        Text($r('app.string.trade_query_time'))
          .fontSize(12)
          .fontColor(AppColor.textSecondary)
        Text(this.vm.queryTimeText)
          .fontSize(12)
          .fontColor(AppColor.textPrimary)
          .margin({ left: 8 })
        Blank()
        Text(queryStatusText(this.vm.queryStatus))
          .fontSize(12)
          .fontColor(this.vm.queryStatus === 'accepted' ? AppColor.priceUp : AppColor.textSecondary)
      }
      .width('100%')
      .margin({ top: 6 })

      Row() {
        Text($r('app.string.trade_query_client_id'))
          .fontSize(12)
          .fontColor(AppColor.textSecondary)
        Text(this.vm.clientOrderIdText)
          .fontSize(12)
          .fontColor(AppColor.textPrimary)
          .margin({ left: 8 })
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .padding(12)
    .margin({ top: 12 })
    .backgroundColor(AppColor.bgSurface)
    .borderRadius(8)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  unknownCard() {
    Column() {
      Text($r('app.string.trade_unknown_title'))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColor.textPrimary)
      Text($r('app.string.trade_unknown_desc'))
        .fontSize(12)
        .fontColor(AppColor.textSecondary)
        .margin({ top: 6 })
        .lineHeight(18)
      if (this.vm.queryStatus === '') {
        Text(this.vm.querying ? $r('app.string.trade_querying') : $r('app.string.trade_query_action'))
          .fontSize(13)
          .fontColor(AppColor.accent)
          .margin({ top: 10 })
          .onClick(() => {
            this.vm.query();
          })
      } else {
        this.queryResult()
      }
    }
    .width('100%')
    .padding(12)
    .margin({ top: 12 })
    .backgroundColor(AppColor.bannerBg)
    .borderRadius(8)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  cta() {
    Row() {
      if (this.vm.submitting) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(AppColor.textOnAccent)
        Text($r('app.string.trade_submitting'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textOnAccent)
          .margin({ left: 8 })
      } else {
        Text($r('app.string.trade_confirm_buy'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.ctaEnabled() ? AppColor.textOnAccent : AppColor.disabledText)
      }
    }
    .width('100%')
    .height(48)
    .borderRadius(24)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.ctaEnabled() ? AppColor.accentFill : AppColor.disabledBg)
    .margin({ top: this.keyboardUp ? 8 : 16 })
    .accessibilityGroup(true)
    .accessibilityText($r('app.string.trade_confirm_buy'))
    .enabled(this.ctaEnabled())
    .onClick(() => {
      this.vm.submit();
    })
  }

  @Builder
  contentColumn() {
    this.header()
    this.accountRow()

    Column() {
      this.summaryRow($r('app.string.trade_order_price'), this.vm.priceText, AppColor.priceUp,
        $r('app.string.trade_order_price'))
      Divider().color(AppColor.divider).strokeWidth(0.5)
      this.summaryRow($r('app.string.trade_order_qty'), this.vm.qtyText, AppColor.textPrimary,
        $r('app.string.trade_order_qty'))
    }
    .width('100%')
    .margin({ top: 8 })

    if (this.vm.blockCode !== '') {
      this.blockBanner()
    }

    if (this.vm.failCode !== '') {
      this.failBanner()
    }

    if (this.vm.unknown) {
      this.unknownCard()
    }
  }

  build() {
    Scroll() {
      Column() {
        this.contentColumn()
        this.cta()
      }
      .width('100%')
      .padding({
        left: 20,
        right: 20,
        top: this.keyboardUp ? 8 : 16,
        bottom: this.keyboardUp ? 8 : this.bottomInset + 16
      })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }
}
