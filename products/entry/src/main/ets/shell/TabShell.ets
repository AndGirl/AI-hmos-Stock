import { BreakpointHost, BreakpointService } from 'commons_basic';
import { AppColor } from 'commons_ui';
import { WatchlistPage } from 'watchlist';
import { FloatingTabBar } from './FloatingTabBar';
import { HomePage } from '../pages/HomePage';
import { NewsPage } from '../pages/NewsPage';
import { MarketPage } from '../pages/MarketPage';

/**
 * 四 Tab 壳：Tabs 只负责承载页面（默认 TabBar 高度置 0），
 * 底部导航由自绘的 FloatingTabBar 悬浮展示；自选为默认页（index = 2）。
 */
@ComponentV2
export struct TabShell {
  @Local currentIndex: number = 2;
  @Local breakpoint: BreakpointService = BreakpointHost.getService();
  private tabsController: TabsController = new TabsController();

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Tabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.tabsController }) {
        TabContent() {
          HomePage()
        }

        TabContent() {
          NewsPage()
        }

        TabContent() {
          WatchlistPage()
        }

        TabContent() {
          MarketPage()
        }
      }
      .barHeight(0)
      .scrollable(false)
      .animationDuration(0)
      .width('100%')
      .height('100%')
      .onChange((index: number) => {
        this.currentIndex = index;
      })

      FloatingTabBar({
        currentIndex: this.currentIndex,
        maxWidth: this.breakpoint.widthBp === 'sm' ? 600 : 480,
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
