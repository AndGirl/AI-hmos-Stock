import { ConnectionHost, ConnectionHub } from 'commons_basic';
import { AppColor, AppDim } from '../theme/TokenRegistry';

/**
 * 全局连接提示条（CC-7.3 / CC-7.4）：全应用唯一文案，页面只挂一次、不各自叠加。
 * - weak：「网络较弱，行情更新较慢」
 * - offline：「行情连接中断，数据可能延迟」
 * - delayed：不占 banner，改用「延迟」角标（涨跌幅列头）
 * - online：不渲染（高度为 0，不占位）
 */
@ComponentV2
export struct GlobalBanner {
  @Local hub: ConnectionHub = ConnectionHost.getService();

  private isWeak(): boolean {
    return this.hub.state === 'weak';
  }

  private isOffline(): boolean {
    return this.hub.state === 'offline';
  }

  build() {
    if (this.bannerShown()) {
      Row() {
        Row()
          .width(6)
          .height(6)
          .borderRadius(3)
          .backgroundColor(this.isOffline() ? AppColor.error : AppColor.textSecondary)
          .margin({ right: AppDim.gap8 })

        if (this.isOffline()) {
          Text($r('app.string.conn_offline'))
            .fontSize(12)
            .fontColor(AppColor.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else {
          Text($r('app.string.conn_weak'))
            .fontSize(12)
            .fontColor(AppColor.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .height(28)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.isOffline() ? AppColor.accentSoft : AppColor.bannerBg)
      .border({ width: { bottom: 0.5 }, color: AppColor.divider })
      .accessibilityGroup(true)
      .accessibilityText(this.isOffline() ? $r('app.string.conn_offline') :
        $r('app.string.conn_weak'))
    }
  }

  /** 只有 weak / offline 占位；delayed 用列头角标，online 不渲染。 */
  private bannerShown(): boolean {
    return this.hub.bannerVisible();
  }
}
