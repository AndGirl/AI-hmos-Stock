import { SafeAreaHost, SafeAreaService } from 'commons_basic';
import { AppColor, GlobalBanner } from 'commons_ui';
import { WatchlistPage } from 'watchlist';
import { AppServices } from '../di/AppServices';
import { BottomTabBar } from './BottomTabBar';
import { HomePage } from '../pages/HomePage';
import { NewsPage } from '../pages/NewsPage';
import { MarketPage } from '../pages/MarketPage';

/**
 * 四 Tab 壳：Tabs 只负责承载页面（默认 TabBar 高度置 0），
 * 底部导航由自绘的 BottomTabBar 贴底固定展示（在布局流内，不悬浮遮挡内容）；
 * 自选为默认页（index = 2）。
 * 全屏布局下由 SafeAreaService 提供上下避让：顶部由 Navigation 吃，底部由底栏吃。
 */
@ComponentV2
export struct TabShell {
  @Local currentIndex: number = 2;
  @Local safeArea: SafeAreaService = SafeAreaHost.getService();
  private tabsController: TabsController = new TabsController();

  build() {
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

      BottomTabBar({
        currentIndex: this.currentIndex,
        bottomInset: this.safeArea.bottomInset,
        onSelect: (index: number) => {
          this.tabsController.changeIndex(index);
          this.currentIndex = index;
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bgPage)
  }
}
