import { AppColor, AppDim } from 'commons_ui';

const BASE_TABS: Resource[] = [
  $r('app.string.detail_content_discuss'),
  $r('app.string.detail_content_must_read'),
  $r('app.string.detail_content_report'),
  $r('app.string.detail_content_capital'),
  $r('app.string.detail_content_profile')
];

const WIDE_TABS: Resource[] = [
  $r('app.string.detail_content_discuss'),
  $r('app.string.detail_content_must_read'),
  $r('app.string.detail_content_report'),
  $r('app.string.detail_content_capital'),
  $r('app.string.detail_content_profile'),
  $r('app.string.detail_content_notice')
];

/** Tab 标题：选中强调色 + 底部短横线（不用系统蓝色默认样式）。 */
@ComponentV2
struct ContentTabItem {
  @Param label: Resource = $r('app.string.detail_content_discuss');
  @Param selected: boolean = false;

  build() {
    Column() {
      Text(this.label)
        .fontSize(13)
        .fontColor(this.selected ? AppColor.accent : AppColor.textSecondary)
        .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Normal)
      Row()
        .width(16)
        .height(2)
        .borderRadius(1)
        .backgroundColor(this.selected ? AppColor.accent : AppColor.transparent)
        .margin({ top: 4 })
    }
    .padding({ left: AppDim.gap12, right: AppDim.gap12, top: AppDim.gap8, bottom: AppDim.gap4 })
    .justifyContent(FlexAlign.Center)
  }
}

/**
 * 内容 Tab 容器（FR-06.9）：讨论/必读/研报/资金/资料（lg/xl 加公告），默认讨论。
 * 本期只定义容器与空态，内容归各业务模块；单 Tab 失败不整页报错。
 */
@ComponentV2
export struct ContentTabs {
  @Param wide: boolean = false;
  @Local currentIndex: number = 0;
  private controller: TabsController = new TabsController();

  private labels(): Resource[] {
    return this.wide ? WIDE_TABS : BASE_TABS;
  }

  @Builder
  tabBar(label: Resource, index: number) {
    ContentTabItem({ label: label, selected: this.currentIndex === index })
  }

  build() {
    Tabs({ barPosition: BarPosition.Start, controller: this.controller, index: 0 }) {
      ForEach(this.labels(), (label: Resource, index: number) => {
        TabContent() {
          Column() {
            Text($r('app.string.detail_content_empty'))
              .fontSize(13)
              .fontColor(AppColor.textSecondary)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        .tabBar(this.tabBar(label, index))
      }, (label: Resource, index: number) => 'content-tab-' + index)
    }
    .barMode(BarMode.Scrollable)
    .barHeight(44)
    .width('100%')
    .height(168)
    .divider({ strokeWidth: 0.5, color: AppColor.divider })
    .onChange((index: number) => {
      this.currentIndex = index;
    })
    .backgroundColor(AppColor.bgPage)
  }
}
