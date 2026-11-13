import { LayoutConst } from 'commons_basic';
import { AppColor, AppDim } from '../theme/TokenRegistry';

/** 底部导航的单个 Tab：图标 + 文字，选中态用主题强调色，整块可点。 */
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
 * 自绘底部导航栏（不是系统 Tabs 默认 bar）：
 * 贴底固定、铺满所给宽度，顶部一条 0.5vp 分割线与内容区分隔；
 * 常规由 TabShell 的 Column 让位；平板 xl 分栏时改由左列承载（§10-83），右栏因此能贴到窗口底部。
 * 底部安全区由自身 padding 吃掉，白底一直铺到导航条下沿。
 */
@ComponentV2
export struct BottomTabBar {
  @Param currentIndex: number = 2;
  /** 底部安全区高度（vp） */
  @Param bottomInset: number = 0;
  @Event onSelect: (index: number) => void = (index: number) => {
  };

  build() {
    Column() {
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
      .constraintSize({ maxWidth: LayoutConst.TAB_BAR_CONTENT_MAX_WIDTH })
      .height(LayoutConst.TAB_BAR_HEIGHT)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ bottom: this.bottomInset })
    .backgroundColor(AppColor.bgPage)
    .border({ width: { top: 0.5 }, color: AppColor.dividerStrong })
  }
}
