import { AppColor, AppDim } from 'commons_ui';
import { GroupTabVM } from '../viewmodel/WatchlistVM';

/** 分组 Tab 超过 5 个后横向滑动查看（每个 Tab 保持自然宽度，不截断名称）。 */
const MAX_VISIBLE_GROUPS: number = 5;
/** 右侧两个占位符（卡片切换 / 排序）的尺寸。 */
const PLACEHOLDER_SIZE: number = 32;

/**
 * 分组 Tab：全部 + 系统组（融/创）+ 用户组，显示只数，选中红色下划线 3vp（FR-02.5）。
 * - 最多展示 5 个，最少 1 个（「全部」）；可横向滑动，内容始终居左；
 * - 最右侧固定预留两个占位符（卡片切换 / 排序），不随 Tab 横滑移动；
 * - 用户组直接渲染 `name`（M7-6 关闭 T-03），系统组仍走 i18n；长按进入分组管理。
 */
@ComponentV2
export struct GroupTabs {
  @Param groups: GroupTabVM[] = [];
  @Event onSelect: (id: string) => void = (id: string): void => {
  };
  @Event onLongPress: (id: string) => void = (id: string): void => {
  };

  private labelOf(group: GroupTabVM): ResourceStr {
    if (group.isUser && group.name.length > 0) {
      return group.name;
    }
    // 阶段一遗留的用户组 id `user` 没有自带 name（显示名走 i18n），改名后才有 name。
    if (group.id === 'user') {
      return $r('app.string.watch_group_user');
    }
    if (group.id === 'fin') {
      return $r('app.string.watch_group_fin');
    }
    if (group.id === 'star') {
      return $r('app.string.watch_group_star');
    }
    if (group.id === 'kcb') {
      return $r('app.string.watch_group_kcb');
    }
    return $r('app.string.watch_group_all');
  }

  @Builder
  placeholder(label: ResourceStr) {
    Text(label)
      .width(PLACEHOLDER_SIZE)
      .height(PLACEHOLDER_SIZE)
      .fontSize(11)
      .textAlign(TextAlign.Center)
      .fontColor(AppColor.textSecondary)
      .backgroundColor(AppColor.bgSurface)
      .borderRadius(AppDim.gap8)
      .border({ width: 0.5, color: AppColor.divider })
      .margin({ left: AppDim.gap8 })
  }

  build() {
    Row() {
      List({ space: 0 }) {
        ForEach(this.groups, (group: GroupTabVM) => {
          ListItem() {
            Column() {
              Row() {
                Text(this.labelOf(group))
                  .fontSize(16)
                  .fontWeight(group.selected ? FontWeight.Bold : FontWeight.Medium)
                  .fontColor(group.selected ? AppColor.accent : AppColor.textSecondary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${group.count}`)
                  .fontSize(12)
                  .fontColor(group.selected ? AppColor.accent : AppColor.textSecondary)
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
            .padding({
              left: this.groups.length >= MAX_VISIBLE_GROUPS ? AppDim.gap8 : AppDim.gap12,
              right: this.groups.length >= MAX_VISIBLE_GROUPS ? AppDim.gap8 : AppDim.gap12
            })
            .onClick(() => {
              this.onSelect(group.id);
            })
            .gesture(
              LongPressGesture({ repeat: false })
                .onAction(() => {
                  this.onLongPress(group.id);
                })
            )
          }
        }, (group: GroupTabVM) => `${group.id}-${group.name}`)
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .layoutWeight(1)
      .height(40)

      this.placeholder($r('app.string.watch_entry_card'))
      this.placeholder($r('app.string.watch_entry_sort'))
    }
    .width('100%')
    .height(40)
    .alignItems(VerticalAlign.Center)
    .padding({ left: AppDim.gap8, right: AppDim.gap8 })
  }
}
