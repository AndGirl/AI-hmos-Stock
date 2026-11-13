import { AppColor, AppDim } from 'commons_ui';
import { GroupTabVM } from '../viewmodel/WatchlistVM';

/**
 * 分组管理（M7-6）：新建 / 重命名 / 删除用户组，「全部」与系统组只读。
 * - 用户组 ≤7（CC-2.1），名字 ≤8 字（校验在 Store 的 WatchlistRules，本组件只收集输入）；
 * - 删除二次确认由页面弹（需要分组名），本组件只上抛 id。
 */
@ComponentV2
export struct GroupManageSheet {
  @Param groups: GroupTabVM[] = [];
  @Param nameMax: number = 8;
  @Event onCreate: (name: string) => void = (name: string): void => {
  };
  @Event onRename: (id: string, name: string) => void = (id: string, name: string): void => {
  };
  @Event onDelete: (id: string) => void = (id: string): void => {
  };
  @Event onClose: () => void = (): void => {
  };
  @Local input: string = '';
  @Local renameId: string = '';

  private labelOf(group: GroupTabVM): ResourceStr {
    if (group.isUser && group.name.length > 0) {
      return group.name;
    }
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

  private submitInput(): void {
    if (this.input.trim().length === 0) {
      return;
    }
    const name: string = this.input.trim();
    if (this.renameId.length > 0) {
      this.onRename(this.renameId, name);
    } else {
      // 上限由 Store 判定并回 'limit'，这里不再本地拦截（否则提示永远不可达）。
      this.onCreate(name);
    }
    this.input = '';
    this.renameId = '';
  }

  @Builder
  groupRow(group: GroupTabVM) {
    Row() {
      Text(this.labelOf(group))
        .fontSize(15)
        .fontColor(AppColor.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (group.id === 'all') {
        Text($r('app.string.watch_group_all'))
          .fontSize(11)
          .fontColor(AppColor.textSecondary)
      } else if (group.system) {
        Text($r('app.string.group_system_tag'))
          .fontSize(11)
          .fontColor(AppColor.textSecondary)
          .padding({ left: AppDim.gap4, right: AppDim.gap4 })
          .borderRadius(2)
          .backgroundColor(AppColor.disabledBg)
      } else {
        Text($r('app.string.group_rename'))
          .fontSize(13)
          .fontColor(AppColor.textSecondary)
          .height(36)
          .padding({ left: AppDim.gap8, right: AppDim.gap8 })
          .onClick(() => {
            this.renameId = group.id;
            this.input = group.name;
          })
        Text($r('app.string.group_delete'))
          .fontSize(13)
          .fontColor(AppColor.error)
          .height(36)
          .padding({ left: AppDim.gap8, right: AppDim.gap8 })
          .onClick(() => {
            this.onDelete(group.id);
          })
      }

      Text(`${group.count}`)
        .fontSize(12)
        .fontColor(AppColor.textSecondary)
        .width(36)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .height(48)
    .padding({ left: AppDim.gap16, right: AppDim.gap16 })
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: 0.5 }, color: AppColor.divider })
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.group_manage'))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
          .layoutWeight(1)
        Text($r('app.string.group_manage_close'))
          .fontSize(14)
          .fontColor(AppColor.accent)
          .height(40)
          .padding({ left: AppDim.gap12, right: AppDim.gap12 })
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .height(52)
      .padding({ left: AppDim.gap16, right: AppDim.gap8 })
      .alignItems(VerticalAlign.Center)

      Text($r('app.string.group_manage_desc'))
        .fontSize(11)
        .fontColor(AppColor.textSecondary)
        .width('100%')
        .padding({ left: AppDim.gap16, right: AppDim.gap16, bottom: AppDim.gap8 })

      List() {
        ForEach(this.groups, (group: GroupTabVM) => {
          ListItem() {
            this.groupRow(group)
          }
        }, (group: GroupTabVM) => `${group.id}-${group.name}`)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Row() {
        TextInput({ text: this.input, placeholder: $r('app.string.group_new_placeholder') })
          .layoutWeight(1)
          .height(40)
          .maxLength(this.nameMax)
          .fontSize(14)
          .backgroundColor(AppColor.bgSurface)
          .borderRadius(AppDim.gap8)
          .onChange((value: string): void => {
            this.input = value;
          })

        Text(this.renameId.length > 0 ? $r('app.string.group_save') : $r('app.string.group_new'))
          .fontSize(14)
          .fontColor(this.input.trim().length > 0 ? AppColor.textOnAccent : AppColor.disabledText)
          .height(40)
          .padding({ left: AppDim.gap16, right: AppDim.gap16 })
          .textAlign(TextAlign.Center)
          .backgroundColor(this.input.trim().length > 0 ? AppColor.accentFill : AppColor.disabledBg)
          .opacity(this.input.trim().length > 0 ? 1 : 0.4)
          .borderRadius(AppDim.pillRadius)
          .margin({ left: AppDim.gap8 })
          .onClick(() => {
            this.submitInput();
          })

        if (this.renameId.length > 0) {
          Text($r('app.string.group_cancel'))
            .fontSize(13)
            .fontColor(AppColor.textSecondary)
            .height(40)
            .padding({ left: AppDim.gap8, right: AppDim.gap8 })
            .onClick(() => {
              this.input = '';
              this.renameId = '';
            })
        }
      }
      .width('100%')
      .padding({ left: AppDim.gap16, right: AppDim.gap16, top: AppDim.gap8, bottom: AppDim.gap8 })
      .alignItems(VerticalAlign.Center)
      .border({ width: { top: 0.5 }, color: AppColor.divider })
    }
    .width('100%')
    .height(440)
    .backgroundColor(AppColor.bgPage)
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
