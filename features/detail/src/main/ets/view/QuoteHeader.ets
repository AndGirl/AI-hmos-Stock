import { AppColor, AppDim } from 'commons_ui';
import { arrowOfTone } from 'commons_basic';
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
  /** 超窄窗（三窗叠放在 388vp 屏上约 133vp/窗）：再降一档字号，避免价格与涨跌互相挤压。 */
  @Param narrow: boolean = false;
  /** 窄窗（紧凑版且内容宽 <360vp）：隐藏状态/时间，避免 1.45× 下挤压截断。 */
  @Param hideStatus: boolean = false;
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

  /** 涨跌/涨跌幅（M12-3）：数值前加 ▲/▼，符号用小字号，颜色仍按方向。 */
  @Builder
  changeText(text: string, size: number) {
    Text() {
      Span(arrowOfTone(this.vm.priceTone)).fontSize(Math.max(9, size - 3))
      Span(text)
    }
    .fontSize(size)
    .fontColor(toneColor(this.vm.priceTone))
    .maxLines(1)
  }

  build() {
    Column() {
      Row() {
        Text(this.vm.name)
          .fontSize(this.narrow ? 14 : (this.mini ? 16 : (this.compact ? 20 : 24)))
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
        if (!this.mini && !this.hideStatus) {
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
            .fontSize(this.narrow ? 18 : (this.mini ? 22 : (this.compact ? 30 : 36)))
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColor.transparent)
            .backgroundColor(toneColor(this.vm.priceTone))
            .opacity(this.flashAlpha)
          Text(this.vm.priceText)
            .fontSize(this.narrow ? 18 : (this.mini ? 22 : (this.compact ? 30 : 36)))
            .fontWeight(FontWeight.Bold)
            .fontColor(toneColor(this.vm.priceTone))
        }
        .padding({ left: 2, right: 2 })

        if (this.mini) {
          if (this.narrow) {
            // 超窄窗：涨跌与涨跌幅换行到价格下方，避免右侧被裁。
            Blank()
          } else {
            Column() {
              this.changeText(this.vm.chgText, 11)
              this.changeText(this.vm.pctText, 11)
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: AppDim.gap8 })
          }
        } else {
          Column() {
            this.changeText(this.vm.chgText, 14)
            this.changeText(this.vm.pctText, 14)
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: AppDim.gap12 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: this.mini ? AppDim.gap4 : AppDim.gap8 })
      .accessibilityGroup(true)

      if (this.narrow) {
        Row() {
          this.changeText(this.vm.chgText, 10)
          Text('  ')
            .fontSize(10)
          this.changeText(this.vm.pctText, 10)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .accessibilityGroup(true)
      }

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
