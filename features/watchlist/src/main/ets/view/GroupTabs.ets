import { AppColor, AppDim } from 'commons_ui';
import { GroupTabVM } from '../viewmodel/WatchlistVM';

/** 分组 Tab 最多展示 5 个（含「全部」），超出后横向滑动查看。 */
const MAX_VISIBLE_GROUPS: number = 5;
/** 右侧两个占位符（卡片切换 / 排序）的尺寸。 */
const PLACEHOLDER_SIZE: number = 32;

/**
 * 分组 Tab：全部 + 系统组（融/创）+ 用户组，显示只数，选中红色下划线 3vp（FR-02.5）。
 * - 最多展示 5 个，最少 1 个（「全部」）；可横向滑动，内容始终居左；
 * - 最右侧固定预留两个占位符（卡片切换 / 排序），不随 Tab 横滑移动。
 */
@ComponentV2
export struct GroupTabs {
  @Param groups: GroupTabVM[] = [];
  @Event onSelect: (id: string) => void = () => {
  };
  @Local barWidth: number = 0;

  /** 超过 5 个时每个 Tab 最多占 1/5 视口，保证「最多展示 5 个」且其余可横滑。 */
  private tabMaxWidth(): number {
    if (this.groups.length <= MAX_VISIBLE_GROUPS || this.barWidth <= 0) {
      return 10000;
    }
    return this.barWidth / MAX_VISIBLE_GROUPS;
  }

  private labelOf(id: string): Resource {
    if (id === 'fin') {
      return $r('app.string.watch_group_fin');
    }
    if (id === 'star') {
      return $r('app.string.watch_group_star');
    }
    if (id === 'kcb') {
      return $r('app.string.watch_group_kcb');
    }
    if (id === 'user') {
      return $r('app.string.watch_group_user');
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
                Text(this.labelOf(group.id))
                  .fontSize(14)
                  .fontWeight(group.selected ? FontWeight.Medium : FontWeight.Regular)
                  .fontColor(group.selected ? AppColor.textPrimary : AppColor.textSecondary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
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
            .padding({
              left: this.groups.length >= MAX_VISIBLE_GROUPS ? AppDim.gap8 : AppDim.gap12,
              right: this.groups.length >= MAX_VISIBLE_GROUPS ? AppDim.gap8 : AppDim.gap12
            })
            .constraintSize({ maxWidth: this.tabMaxWidth() })
            .onClick(() => {
              this.onSelect(group.id);
            })
          }
        }, (group: GroupTabVM) => group.id)
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .layoutWeight(1)
      .height(40)
      .onAreaChange((oldValue: Area, newValue: Area): void => {
        this.barWidth = Number(newValue.width);
      })

      this.placeholder($r('app.string.watch_entry_card'))
      this.placeholder($r('app.string.watch_entry_sort'))
    }
    .width('100%')
    .height(40)
    .alignItems(VerticalAlign.Center)
    .padding({ left: AppDim.gap8, right: AppDim.gap8 })
  }
}
