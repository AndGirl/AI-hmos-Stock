import { ConnectionHost, ConnectionHub, QuoteHealth, QuoteHealthHost } from 'commons_basic';
import { AppColor, AppDim } from '../theme/TokenRegistry';

/**
 * 全局提示条（CC-7.3 / CC-7.4：全应用唯一，只在页面挂一次、不各自叠加）。
 *
 * 常驻行 + 状态行（同一个组件内的两行，不是两条 banner）：
 * - 常驻行：**「模拟数据 · 仅供学习参考」**——本项目永不接入真实行情/真实交易，
 *   这是必须常显的合规声明（M9 口径变更，见 docs/api-policy 与进度文档）；
 * - 状态行：按优先级只显示一条
 *   offline > weak > unauthorized（鉴权失效）> throttled（限流降频）；
 * - delayed 不占状态行，改用「延迟」角标（涨跌幅列头）。
 */
@ComponentV2
export struct GlobalBanner {
  @Local hub: ConnectionHub = ConnectionHost.getService();
  @Local health: QuoteHealth = QuoteHealthHost.getService();

  private isWeak(): boolean {
    return this.hub.state === 'weak';
  }

  private isOffline(): boolean {
    return this.hub.state === 'offline';
  }

  private isUnauthorized(): boolean {
    return !this.isOffline() && this.health.unauthorized();
  }

  private isThrottled(): boolean {
    return !this.isOffline() && !this.isUnauthorized() && this.health.degraded();
  }

  /** 是否有状态行（online 且未降级时不显示）。 */
  private stateShown(): boolean {
    return this.isOffline() || this.isWeak() || this.isUnauthorized() || this.isThrottled();
  }

  private stateText(): Resource {
    if (this.isOffline()) {
      return $r('app.string.conn_offline');
    }
    if (this.isWeak()) {
      return $r('app.string.conn_weak');
    }
    if (this.isUnauthorized()) {
      return $r('app.string.quote_unauthorized');
    }
    return $r('app.string.quote_throttled');
  }

  private stateIsError(): boolean {
    return this.isOffline() || this.isUnauthorized();
  }

  build() {
    Column() {
      // 常驻：模拟数据声明（不随连接状态消失）
      Row() {
        Text($r('app.string.simulated_data_notice'))
          .fontSize(11)
          .fontColor(AppColor.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(22)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(AppColor.bgPage)
      .border({ width: { bottom: 0.5 }, color: AppColor.divider })
      .accessibilityGroup(true)
      .accessibilityText($r('app.string.simulated_data_notice'))

      // 状态行：仅在有连接/通道问题时出现
      if (this.stateShown()) {
        Row() {
          Row()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(this.stateIsError() ? AppColor.error : AppColor.textSecondary)
            .margin({ right: AppDim.gap8 })

          Text(this.stateText())
            .fontSize(12)
            .fontColor(AppColor.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(28)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.stateIsError() ? AppColor.accentSoft : AppColor.bannerBg)
        .border({ width: { bottom: 0.5 }, color: AppColor.divider })
        .accessibilityGroup(true)
        .accessibilityText(this.stateText())
      }
    }
    .width('100%')
  }
}
