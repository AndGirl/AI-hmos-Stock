import { AppColor } from 'commons_ui';
import { SafeAreaHost, SafeAreaService } from 'commons_basic';
import { GlobalBanner } from 'commons_ui';
import { SearchPage } from 'search';
import { TradeSheet, TradeVM } from 'trade';
import { AppServices } from '../di/AppServices';
import { SearchParam } from '../router/AppRoutes';

/**
 * 搜索路由壳（M6-6）：push 形态；深链 / 自选空态进入。
 * 壳只做装配：路由、返回栈、开窗与弹窗归属（与 DetailPage 同构，INV-T4）。
 */
@ComponentV2
export struct SearchRoutePage {
  @Local safeArea: SafeAreaService = SafeAreaHost.getService();
  @Local initialQuery: string = '';
  @Local ready: boolean = false;
  @Local tradeVM: TradeVM = new TradeVM();
  @Local tradeOpen: boolean = false;

  aboutToDisappear(): void {
    this.tradeVM.dispose();
  }

  private openTrade(code: string): void {
    if (this.tradeOpen || code.length === 0) {
      return;
    }
    this.tradeVM.attach(code, 'pane');
    this.tradeOpen = true;
  }

  private closeTrade(): void {
    if (!this.tradeOpen) {
      return;
    }
    this.tradeOpen = false;
    this.tradeVM.dispose();
  }

  @Builder
  tradeCover() {
    TradeSheet({
      vm: this.tradeVM,
      bottomInset: this.safeArea.bottomInset,
      onClosed: (): void => {
        this.closeTrade();
      }
    })
  }

  build() {
    NavDestination() {
      Column() {
        GlobalBanner()

        if (this.ready) {
          SearchPage({
            mode: 'push',
            initialQuery: this.initialQuery,
            onOpenDetail: (code: string, rank: number): void => {
              AppServices.get().pushDetail(code, 'search', rank);
            },
            onOpenTrade: (code: string): void => {
              this.openTrade(code);
            },
            onOpenAddWatchlist: (code: string): void => {
              // M7-7：右栏「自选设置」→ 添加页（带 code 预置）。
              AppServices.get().pushAddWatchlist(code, '', 'search');
            },
            onOpenPk: (codes: string[]): void => {
              AppServices.get().pushPk(codes, 0, 'search');
            },
            onClose: (): void => {
              AppServices.get().pop();
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColor.bgPage)

      if (this.tradeOpen) {
        this.tradeCover()
      }
    }
    .hideTitleBar(true)
    .backgroundColor(AppColor.bgPage)
    .onBackPressed((): boolean => {
      if (this.tradeOpen) {
        this.closeTrade();
        return true;
      }
      return false;
    })
    .onReady((context: NavDestinationContext) => {
      if (context.pathInfo.param !== undefined) {
        const param: SearchParam = context.pathInfo.param as SearchParam;
        if (param.q !== undefined) {
          this.initialQuery = param.q;
        }
      }
      this.ready = true;
    })
  }
}
