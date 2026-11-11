import { AppColor, AppDim } from 'commons_ui';
import { LayoutConst } from 'commons_basic';

/** 悬浮底栏的单个 Tab：图标 + 文字，选中态用主题强调色，整块可点。 */
@ComponentV2
struct TabBarItem {
  @Param itemIndex: number = 0;
  @Param itemLabel: ResourceStr = '';
  @Param itemIcon: Resource = $r('app.media.ic_tab_home');
  @Param selected: boolean = false;
  @Event onTap: (index: number) => void = (index: number) => {
  };

  build() {
    Column() {
      Image(this.itemIcon)
        .width(22)
        .height(22)
        .fillColor(this.selected ? AppColor.accent : AppColor.textSecondary)

      Text(this.itemLabel)
        .fontSize(10)
        .fontColor(this.selected ? AppColor.accent : AppColor.textSecondary)
        .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Normal)
        .maxLines(1)
        .margin({ top: AppDim.gap2 })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.onTap(this.itemIndex);
    })
  }
}

/**
 * 自绘悬浮胶囊底栏（不是系统 Tabs 默认 bar）：
 * Tabs 只负责切页，底栏悬浮在内容之上，四 Tab 等分。
 */
@ComponentV2
export struct FloatingTabBar {
  @Param currentIndex: number = 2;
  @Param maxWidth: number = 640;
  @Event onSelect: (index: number) => void = (index: number) => {
  };

  build() {
    Row() {
      TabBarItem({
        itemIndex: 0,
        itemLabel: $r('app.string.tab_home'),
        itemIcon: $r('app.media.ic_tab_home'),
        selected: this.currentIndex === 0,
        onTap: (index: number) => {
          this.onSelect(index);
        }
      })

      TabBarItem({
        itemIndex: 1,
        itemLabel: $r('app.string.tab_news'),
        itemIcon: $r('app.media.ic_tab_news'),
        selected: this.currentIndex === 1,
        onTap: (index: number) => {
          this.onSelect(index);
        }
      })

      TabBarItem({
        itemIndex: 2,
        itemLabel: $r('app.string.tab_watchlist'),
        itemIcon: $r('app.media.ic_tab_watchlist'),
        selected: this.currentIndex === 2,
        onTap: (index: number) => {
          this.onSelect(index);
        }
      })

      TabBarItem({
        itemIndex: 3,
        itemLabel: $r('app.string.tab_market'),
        itemIcon: $r('app.media.ic_tab_market'),
        selected: this.currentIndex === 3,
        onTap: (index: number) => {
          this.onSelect(index);
        }
      })
    }
    .width('100%')
    .height(LayoutConst.TAB_BAR_HEIGHT)
    .constraintSize({ maxWidth: this.maxWidth })
    .padding({ left: AppDim.gap4, right: AppDim.gap4 })
    .borderRadius(AppDim.tabBarRadius)
    .backgroundColor(AppColor.bgPage)
    .shadow({
      radius: 24,
      color: AppColor.barShadow,
      offsetX: 0,
      offsetY: 4
    })
    .margin({ left: AppDim.gap16, right: AppDim.gap16, bottom: AppDim.gap12 })
  }
}
