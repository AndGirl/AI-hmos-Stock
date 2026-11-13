import { hilog } from '@kit.PerformanceAnalysisKit';
import { BreakpointHost, BreakpointService, SafeAreaHost, SafeAreaService } from 'commons_basic';
import { AppColor, BottomTabBar, GlobalBanner } from 'commons_ui';
import { WatchlistPage } from 'watchlist';
import { TradeSheet, TradeVM } from 'trade';
import { AppServices } from '../di/AppServices';
import { HomePage } from '../pages/HomePage';
import { NewsPage } from '../pages/NewsPage';
import { MarketPage } from '../pages/MarketPage';

const DOMAIN: number = 0x0001;
const TAG: string = 'TabShell';

/**
 * 四 Tab 壳：Tabs 只负责承载页面（默认 TabBar 高度置 0），
 * 底部导航由自绘的 BottomTabBar 贴底固定展示（在布局流内，不悬浮遮挡内容）；
 * 自选为默认页（index = 2）。
 * 全屏布局下由 SafeAreaService 提供上下避让：顶部由 Navigation 吃，底部由底栏吃。
 * M3（§10-83）：平板 xl 分栏时底栏下移到自选左列（右栏动作栏才能贴到窗口底部），
 * 右栏「去交易」由本壳开窗——弹窗归属当前窗口（INV-T4），用全屏模态承载，
 * 系统返回/侧滑交给系统模态关闭（不会直接退出应用）。
 */
@ComponentV2
export struct TabShell {
  @Local currentIndex: number = 2;
  @Local safeArea: SafeAreaService = SafeAreaHost.getService();
  @Local breakpoint: BreakpointService = BreakpointHost.getService();
  @Local tradeVM: TradeVM = new TradeVM();
  @Local tradeOpen: boolean = false;
  private tabsController: TabsController = new TabsController();

  /** xl 分栏的自选页：底栏由 WatchlistPage 放在左列（§10-83），壳层不再铺通栏底栏。 */
  private splitWatchlist(): boolean {
    return this.breakpoint.isSplit && this.currentIndex === 2;
  }

  aboutToDisappear(): void {
    this.tradeVM.dispose();
  }

  /** 右栏「去交易」：全局同时只允许一个弹窗实例（FR-08 Q8 / INV-T4）。 */
  private openTrade(code: string): void {
    if (this.tradeOpen || code.length === 0) {
      return;
    }
    hilog.info(DOMAIN, TAG, 'trade_entry code=%{public}s source=pane', code);
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
    Stack() {
      // 顶部 GlobalBanner（M5）：连接状态唯一 banner 由 ConnectionHub 驱动，页面不得自绘。
      Column() {
        GlobalBanner()

        Tabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.tabsController }) {
          TabContent() {
            HomePage()
          }

          TabContent() {
            NewsPage()
          }

          TabContent() {
            WatchlistPage({
              onOpenDetail: (code: string): void => {
                AppServices.get().pushDetail(code, 'list');
              },
              onOpenPk: (codes: string[]): void => {
                AppServices.get().pushPk(codes, 0, 'watchlist');
              },
              onOpenTrade: (code: string): void => {
                this.openTrade(code);
              },
              bottomBarIndex: this.currentIndex,
              onSelectBottomTab: (index: number): void => {
                this.tabsController.changeIndex(index);
                this.currentIndex = index;
              }
            })
          }

          TabContent() {
            MarketPage()
          }
        }
        .barHeight(0)
        .scrollable(false)
        .animationDuration(0)
        .width('100%')
        .layoutWeight(1)
        .onChange((index: number) => {
          this.currentIndex = index;
        })

        if (!this.splitWatchlist()) {
          BottomTabBar({
            currentIndex: this.currentIndex,
            bottomInset: this.safeArea.bottomInset,
            onSelect: (index: number) => {
              this.tabsController.changeIndex(index);
              this.currentIndex = index;
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColor.bgPage)
    }
    .width('100%')
    .height('100%')
    // 全屏模态（bindContentCover）：系统返回键 / 侧滑先关弹窗，不会直接退出应用（§10-83）。
    .bindContentCover(this.tradeOpen, this.tradeCover, {
      modalTransition: ModalTransition.NONE,
      onDisappear: (): void => {
        this.closeTrade();
      }
    })
  }
}
