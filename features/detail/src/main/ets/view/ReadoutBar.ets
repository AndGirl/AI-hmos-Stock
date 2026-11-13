import { AppColor, AppDim } from 'commons_ui';
import { ChartReadout } from '../viewmodel/DetailVM';

/**
 * 十字光标读数条（M12-1）：
 * - 竖屏叠在图表上沿；
 * - 横屏由 DetailContent 放到动作栏上方，做 22vp 通栏（G2-5：不遮挡 K 线）。
 * readout 为 null 时保留高度但不显示静态标签。
 */
@ComponentV2
export struct ReadoutBar {
  @Param readout: ChartReadout | null = null;

  build() {
    if (this.readout === null) {
      Row()
        .width('100%')
        .height(22)
        .backgroundColor(AppColor.bgPage)
    } else {
      Row() {
        Text(this.readout.timeText)
          .fontSize(11)
          .fontColor(AppColor.textPrimary)
        Text(this.readout.priceText)
          .fontSize(11)
          .fontColor(AppColor.textPrimary)
          .margin({ left: AppDim.gap8 })
        if (this.readout.avgText.length > 0) {
          Text($r('app.string.detail_readout_avg'))
            .fontSize(10)
            .fontColor(AppColor.textSecondary)
            .margin({ left: AppDim.gap8 })
          Text(this.readout.avgText)
            .fontSize(11)
            .fontColor(AppColor.chartAvg)
            .margin({ left: 2 })
        }
        Text($r('app.string.detail_readout_volume'))
          .fontSize(10)
          .fontColor(AppColor.textSecondary)
          .margin({ left: AppDim.gap8 })
        Text(this.readout.volumeText)
          .fontSize(11)
          .fontColor(AppColor.textPrimary)
          .margin({ left: 2 })
        Text(this.readout.pctText)
          .fontSize(11)
          .fontColor(AppColor.textPrimary)
          .margin({ left: AppDim.gap8 })
      }
      .width('100%')
      .height(22)
      .padding({ left: AppDim.gap16, right: AppDim.gap16 })
      .backgroundColor(AppColor.bgPage)
      .hitTestBehavior(HitTestMode.None)
    }
  }
}
