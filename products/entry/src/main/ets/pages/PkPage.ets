import { AppColor, AppDim } from 'commons_ui';
import { SafeAreaHost, SafeAreaService } from 'commons_basic';
import { PkParam } from '../router/AppRoutes';

/**
 * 多窗比价壳（M0：验证路由与 codes 参数；M4 接入 PkHost/WindowDeck 与订阅编排）。
 * 参数通过 NavDestination.onReady 的 pathInfo 取。
 */
@ComponentV2
export struct PkPage {
  @Local pkCodes: string[] = [];
  @Local focusIndex: number = 0;
  @Local safeArea: SafeAreaService = SafeAreaHost.getService();

  @Builder
  paneItem(code: string, index: number) {
    Column() {
      Text(code)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textPrimary)

      Column()
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(AppColor.bgSurface)
        .borderRadius(12)
        .margin({ top: AppDim.gap12 })
    }
    .layoutWeight(1)
    .height('100%')
    .padding(AppDim.gap12)
    .backgroundColor(AppColor.bgPage)
    .borderRadius(12)
    .border({
      width: 1,
      color: index === this.focusIndex ? AppColor.accent : AppColor.divider
    })
  }

  build() {
    NavDestination() {
      Column() {
        if (this.pkCodes.length === 0) {
          Text('--')
            .fontSize(16)
            .fontColor(AppColor.textSecondary)
        } else {
          Row({ space: 8 }) {
            ForEach(this.pkCodes, (code: string, index: number) => {
              this.paneItem(code, index)
            }, (code: string): string => code)
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .padding({
        left: AppDim.gap16,
        right: AppDim.gap16,
        top: AppDim.gap16,
        bottom: this.safeArea.bottomInset + 16
      })
      .alignItems(HorizontalAlign.Start)
    }
    .title($r('app.string.route_pk_title'))
    .backgroundColor(AppColor.bgPage)
    .onReady((context: NavDestinationContext) => {
      if (context.pathInfo.param !== undefined) {
        const param: PkParam = context.pathInfo.param as PkParam;
        this.pkCodes = param.codes;
        this.focusIndex = param.focus !== undefined ? param.focus : 0;
      }
    })
  }
}
