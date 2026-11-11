import { AppColor, AppDim } from 'commons_ui';
import { GroupTabVM } from '../viewmodel/WatchlistVM';

/** 分组 Tab：全部 + 系统组（融/创）+ 用户组，显示只数，选中红色下划线 3vp（FR-02.5）。 */
@ComponentV2
export struct GroupTabs {
  @Param groups: GroupTabVM[] = [];
  @Event onSelect: (id: string) => void = () => {
  };

  private labelOf(id: string): Resource {
    if (id === 'fin') {
      return $r('app.string.watch_group_fin');
    }
    if (id === 'star') {
      return $r('app.string.watch_group_star');
    }
    if (id === 'user') {
      return $r('app.string.watch_group_user');
    }
    return $r('app.string.watch_group_all');
  }

  build() {
    Scroll() {
      Row() {
        ForEach(this.groups, (group: GroupTabVM) => {
          Column() {
            Row() {
              Text(this.labelOf(group.id))
                .fontSize(14)
                .fontWeight(group.selected ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(group.selected ? AppColor.textPrimary : AppColor.textSecondary)
                .maxLines(1)
              Text(`${group.count}`)
                .fontSize(11)
                .fontColor(AppColor.textSecondary)
                .margin({ left: 2 })
                .maxLines(1)
            }
            .height(32)
            .alignItems(VerticalAlign.Center)

            Row()
              .width(20)
              .height(3)
              .borderRadius(2)
              .backgroundColor(group.selected ? AppColor.accent : AppColor.transparent)
          }
          .padding({ left: AppDim.gap12, right: AppDim.gap12 })
          .onClick(() => {
            this.onSelect(group.id);
          })
        }, (group: GroupTabVM) => group.id)
      }
      .padding({ left: AppDim.gap4, right: AppDim.gap4 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .padding({ left: AppDim.gap8, right: AppDim.gap8 })
  }
}
