import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppColor } from 'commons_ui';
import { BreakpointHost, BreakpointService, OrientationHost, SafeAreaHost, SafeAreaService } from 'commons_basic';
import { GlobalBanner, StateMode, StateView } from 'commons_ui';
import { DetailAction, DetailContent, showDetailActionMenu } from 'detail';
import { TradeSheet, TradeVM } from 'trade';
import { DetailParam } from '../router/AppRoutes';
import { AppServices } from '../di/AppServices';

const DOMAIN: number = 0x0001;
const TAG: string = 'DetailPage';

/**
 * 个股详情壳（FR-06.1）：路由、返回栈、沉浸式与动作栏归属在壳；
 * 内容全部由 features/detail 的 DetailContent 提供（pane 形态复用同一组件）。
 * M3：买入弹窗（TradeSheet）挂在本页 Stack 上，弹窗归属当前窗口（INV-T4）。
 */
@ComponentV2
export struct DetailPage {
  @Local detailCode: string = '';
  @Local safeArea: SafeAreaService = SafeAreaHost.getService();
  @Local breakpoint: BreakpointService = BreakpointHost.getService();
  @Local tradeVM: TradeVM = new TradeVM();
  @Local tradeOpen: boolean = false;

  aboutToDisappear(): void {
    // 离开详情页恢复系统方向策略（M12-1：仅详情页允许横屏）。
    OrientationHost.restore();
    this.tradeVM.dispose();
  }

  private contentWidth(): number {
    const screen: number = this.breakpoint.viewportWidth > 0 ? this.breakpoint.viewportWidth : 360;
    return Math.max(240, screen);
  }

  private handleAction(action: DetailAction): void {
    if (action === 'watchlist') {
      // M7-7 E4：详情「自选设置」→ 添加页（带当前 code，已在自选时直接展示归属）。
      AppServices.get().pushAddWatchlist(this.detailCode, '', 'detail');
      return;
    }
    if (action === 'pk') {
      AppServices.get().pushPk([this.detailCode], 0, 'detail');
      return;
    }
    if (action === 'more') {
      showDetailActionMenu(this.getUIContext(), false, (picked: DetailAction): void => {
        this.handleAction(picked);
      });
      return;
    }
    // 去交易：入口只透传 code + 来源位，门禁/弹层由 features/trade 处理（FR-07.1）。
    if (this.detailCode.length === 0) {
      return;
    }
    hilog.info(DOMAIN, TAG, 'trade_entry code=%{public}s source=detail', this.detailCode);
    this.tradeVM.attach(this.detailCode, 'detail');
    this.tradeOpen = true;
  }

  /** 标题栏右上 ⧉：进入多窗比价（FR-08.1 第二入口 / 设计稿 Q5）。 */
  @Builder
  pkMenu() {
    Row() {
      Image($r('app.media.ic_detail_pk'))
        .width(22)
        .height(22)
        .fillColor(this.detailCode.length > 0 ? AppColor.textPrimary : AppColor.disabledText)
    }
    .width(44)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .accessibilityText($r('app.string.detail_action_pk'))
    .onClick(() => {
      if (this.detailCode.length === 0) {
        return;
      }
      AppServices.get().pushPk([this.detailCode], 0, 'icon');
    })
  }

  build() {
    NavDestination() {
      Column() {
        GlobalBanner()

        Stack() {
          if (this.detailCode.length === 0) {
            StateView({ mode: StateMode.LOADING })
              .width('100%')
              .height('100%')
          } else {
            DetailContent({
              code: this.detailCode,
              mode: 'page',
              contentWidth: this.contentWidth(),
              viewportHeight: this.breakpoint.viewportHeight,
              bottomInset: this.safeArea.bottomInset,
              onAction: (action: DetailAction): void => {
                this.handleAction(action);
              },
              onLoaded: (code: string): void => {
                hilog.info(DOMAIN, TAG, 'detail_loaded code=%{public}s', code);
              }
            })
          }

          if (this.tradeOpen) {
            TradeSheet({
              vm: this.tradeVM,
              bottomInset: this.safeArea.bottomInset,
              onClosed: (): void => {
                this.tradeOpen = false;
                this.tradeVM.dispose();
              }
            })
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
    .title($r('app.string.route_detail_title'))
    .menus(this.pkMenu())
    .backgroundColor(AppColor.bgPage)
    // M12-1：详情页可见时允许系统旋转；被 Pk/交易等覆盖时恢复，避免其它页横屏。
    .onShown((): void => {
      OrientationHost.allowAutoRotation();
    })
    .onHidden((): void => {
      OrientationHost.restore();
    })
    .onBackPressed((): boolean => {
      if (this.tradeOpen) {
        this.tradeVM.back();
        return true;
      }
      return false;
    })
    .onReady((context: NavDestinationContext) => {
      if (context.pathInfo.param !== undefined) {
        const param: DetailParam = context.pathInfo.param as DetailParam;
        this.detailCode = param.code;
      }
    })
  }
}
