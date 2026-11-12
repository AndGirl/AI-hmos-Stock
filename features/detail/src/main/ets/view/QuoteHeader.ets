import { AppColor, AppDim } from 'commons_ui';
import { StockTag } from '../viewmodel/DetailExports';
import { DetailVM } from '../viewmodel/DetailVM';
import { marketLabel, statusLabel, tagLabel, toneColor } from './DetailLabels';

/**
 * 报价头（FR-06.3）：名称（代码）/ 市场 / 交易状态 + 行情时间 / 最新价 / 涨跌 / 涨跌幅。
 * 时间取快照时间（不读设备时钟）；停牌价格类全部 `--`；平盘中灰。
 */
@ComponentV2
export struct QuoteHeader {
  @Param vm: DetailVM = new DetailVM('');
  @Param compact: boolean = false;
  /** 极窄窗（多窗三窗叠放，<240vp）：只留名称/代码/价格/涨跌，其余收起避免挤压。 */
  @Param mini: boolean = false;
  /** 断线时不显示行内行情时间（CC-7.6），避免把延迟误读为个股信息。 */
  @Param offline: boolean = false;
  @Event onMore: () => void = (): void => {
  };
  /** debug 构建：长按名称开始/停止帧率采样（release 由调用方以 BuildProfile.DEBUG 关闭）。 */
  @Event onLongPressName: () => void = (): void => {
  };
  @Local flashAlpha: number = 0;

  @Monitor('vm.flashSeq')
  onFlash(): void {
    this.flashAlpha = 0.14;
    this.getUIContext().animateTo({ duration: 320, curve: Curve.EaseOut }, () => {
      this.flashAlpha = 0;
    });
  }

  build() {
    Column() {
      Row() {
        Text(this.vm.name)
          .fontSize(this.mini ? 16 : (this.compact ? 20 : 24))
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(this.mini ? 1 : 0)
          .gesture(
            LongPressGesture({ repeat: false })
              .onAction(() => {
                this.onLongPressName();
              })
          )
        if (this.mini) {
          Text(this.vm.code)
            .fontSize(11)
            .fontColor(AppColor.textSecondary)
            .margin({ left: AppDim.gap4 })
            .maxLines(1)
        } else {
          Text(this.vm.code)
            .fontSize(13)
            .fontColor(AppColor.textSecondary)
            .margin({ left: AppDim.gap8 })
          Text(marketLabel(this.vm.market))
            .fontSize(10)
            .fontColor(AppColor.textSecondary)
            .backgroundColor(AppColor.bgSurface)
            .borderRadius(3)
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .margin({ left: AppDim.gap4 })
        }
        Blank()
        if (!this.mini) {
          Row() {
            Text(statusLabel(this.vm.status))
              .fontSize(11)
              .fontColor(this.vm.status === 'suspended' || this.vm.status === 'delisted' ?
                AppColor.disabledText : AppColor.textSecondary)
            if (!this.offline) {
              Text(this.vm.timeText)
                .fontSize(11)
                .fontColor(AppColor.textSecondary)
                .margin({ left: AppDim.gap4 })
            }
          }
        }
        if (this.compact && !this.mini) {
          // 紧凑版右上「⋯」：动作收进菜单（FR-06.11 / INV-D4）。
          Text('⋯')
            .fontSize(18)
            .fontColor(AppColor.textPrimary)
            .width(this.mini ? 28 : 32)
            .height(28)
            .textAlign(TextAlign.Center)
            .margin({ left: AppDim.gap4 })
            .accessibilityText($r('app.string.detail_action_more'))
            .onClick(() => {
              this.onMore();
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .accessibilityGroup(true)

      Row() {
        Stack() {
          Text(this.vm.priceText)
            .fontSize(this.mini ? 22 : (this.compact ? 30 : 36))
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColor.transparent)
            .backgroundColor(toneColor(this.vm.priceTone))
            .opacity(this.flashAlpha)
          Text(this.vm.priceText)
            .fontSize(this.mini ? 22 : (this.compact ? 30 : 36))
            .fontWeight(FontWeight.Bold)
            .fontColor(toneColor(this.vm.priceTone))
        }
        .padding({ left: 2, right: 2 })

        if (this.mini) {
          Column() {
            Text(this.vm.chgText)
              .fontSize(11)
              .fontColor(toneColor(this.vm.priceTone))
            Text(this.vm.pctText)
              .fontSize(11)
              .fontColor(toneColor(this.vm.priceTone))
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: AppDim.gap8 })
        } else {
          Column() {
            Text(this.vm.chgText)
              .fontSize(14)
              .fontColor(toneColor(this.vm.priceTone))
            Text(this.vm.pctText)
              .fontSize(14)
              .fontColor(toneColor(this.vm.priceTone))
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: AppDim.gap12 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: this.mini ? AppDim.gap4 : AppDim.gap8 })
      .accessibilityGroup(true)

      if (!this.mini && this.vm.tags.length > 0) {
        Row() {
          ForEach(this.vm.tags, (tag: StockTag) => {
            Text(tagLabel(tag))
              .fontSize(10)
              .fontColor(AppColor.textSecondary)
              .border({ width: 0.5, color: AppColor.divider })
              .borderRadius(3)
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              .margin({ right: AppDim.gap4 })
          }, (tag: StockTag) => tag)
        }
        .width('100%')
        .margin({ top: AppDim.gap8 })
        .accessibilityGroup(true)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: AppDim.gap16, right: AppDim.gap16, top: AppDim.gap12 })
  }
}
