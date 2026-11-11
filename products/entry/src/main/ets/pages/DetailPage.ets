import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppColor } from 'commons_ui';
import { BreakpointHost, BreakpointService, ComingSoonText, SafeAreaHost, SafeAreaService } from 'commons_basic';
import { showComingSoon, StateMode, StateView } from 'commons_ui';
import { DetailAction, DetailContent, showDetailActionMenu } from 'detail';
import { DetailParam } from '../router/AppRoutes';
import { AppServices } from '../di/AppServices';

const DOMAIN: number = 0x0001;
const TAG: string = 'DetailPage';

/**
 * 个股详情壳（FR-06.1）：路由、返回栈、沉浸式与动作栏归属在壳；
 * 内容全部由 features/detail 的 DetailContent 提供（pane 形态复用同一组件）。
 */
@ComponentV2
export struct DetailPage {
  @Local detailCode: string = '';
  @Local safeArea: SafeAreaService = SafeAreaHost.getService();
  @Local breakpoint: BreakpointService = BreakpointHost.getService();

  private contentWidth(): number {
    const screen: number = this.breakpoint.viewportWidth > 0 ? this.breakpoint.viewportWidth : 360;
    return Math.max(240, screen);
  }

  private handleAction(action: DetailAction): void {
    if (action === 'watchlist') {
      showComingSoon(this.getUIContext(), ComingSoonText.ADD_WATCHLIST);
      return;
    }
    if (action === 'pk') {
      AppServices.get().pushPk([this.detailCode], 0);
      return;
    }
    if (action === 'more') {
      showDetailActionMenu(this.getUIContext(), (picked: DetailAction): void => {
        this.handleAction(picked);
      });
      return;
    }
    // FR-06 §4 / INV-D4：详情只做入口与参数透传，买入弹层归 M3（不新增占位文案，ADR-08 锁 5 条）。
    hilog.info(DOMAIN, TAG, 'trade_entry code=%{public}s', this.detailCode);
  }

  build() {
    NavDestination() {
      if (this.detailCode.length === 0) {
        StateView({ mode: StateMode.LOADING })
          .width('100%')
          .height('100%')
      } else {
        DetailContent({
          code: this.detailCode,
          mode: 'page',
          contentWidth: this.contentWidth(),
          bottomInset: this.safeArea.bottomInset,
          onAction: (action: DetailAction): void => {
            this.handleAction(action);
          },
          onLoaded: (code: string): void => {
            hilog.info(DOMAIN, TAG, 'detail_loaded code=%{public}s', code);
          }
        })
      }
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
