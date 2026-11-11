import { AppColor, AppDim } from 'commons_ui';
import { SafeAreaHost, SafeAreaService } from 'commons_basic';
import { DetailParam } from '../router/AppRoutes';

/**
 * 个股详情壳（M0：只验证路由、参数与返回栈；M2 用 QuoteHeader/ChartArea 等替换骨架）。
 * 参数通过 NavDestination.onReady 的 pathInfo 取，页面不感知调用方。
 */
@ComponentV2
export struct DetailPage {
  @Local detailCode: string = '';
  @Local safeArea: SafeAreaService = SafeAreaHost.getService();

  build() {
    NavDestination() {
      Column() {
        Text(this.detailCode.length > 0 ? this.detailCode : '--')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.textPrimary)

        Column()
          .width('100%')
          .height(180)
          .backgroundColor(AppColor.bgSurface)
          .borderRadius(12)
          .margin({ top: AppDim.gap16 })

        Column()
          .width('100%')
          .height(96)
          .backgroundColor(AppColor.bgSurface)
          .borderRadius(12)
          .margin({ top: AppDim.gap12 })

        Column()
          .width('100%')
          .height(96)
          .backgroundColor(AppColor.bgSurface)
          .borderRadius(12)
          .margin({ top: AppDim.gap12 })
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
    .title($r('app.string.route_detail_title'))
    .backgroundColor(AppColor.bgPage)
    .onReady((context: NavDestinationContext) => {
      if (context.pathInfo.param !== undefined) {
        const param: DetailParam = context.pathInfo.param as DetailParam;
        this.detailCode = param.code;
      }
    })
  }
}
