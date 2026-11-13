import { AppColor, AppDim } from 'commons_ui';

/**
 * 编辑模式底部操作条（M7-5）：
 * 已选 N 只 | 全选/取消选择 | 取消（退出编辑） | 移出（N）。
 * 只做展示与事件，确认框与删除逻辑在页面/VM。
 */
@ComponentV2
export struct EditBar {
  @Param count: number = 0;
  @Param allSelected: boolean = false;
  @Event onSelectAll: () => void = (): void => {
  };
  @Event onCancel: () => void = (): void => {
  };
  @Event onRemove: () => void = (): void => {
  };

  build() {
    Row() {
      Text($r('app.string.watch_select_count', `${this.count}`))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textPrimary)
        .layoutWeight(1)

      Text(this.allSelected ? $r('app.string.watch_edit_clear') : $r('app.string.watch_edit_select_all'))
        .fontSize(14)
        .fontColor(AppColor.textSecondary)
        .height(40)
        .padding({ left: AppDim.gap12, right: AppDim.gap12 })
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.onSelectAll();
        })

      Text($r('app.string.watch_select_cancel'))
        .fontSize(14)
        .fontColor(AppColor.textSecondary)
        .height(40)
        .padding({ left: AppDim.gap12, right: AppDim.gap12 })
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.onCancel();
        })

      Text($r('app.string.watch_edit_remove', `${this.count}`))
        .fontSize(15)
        .fontColor(this.count > 0 ? AppColor.textOnAccent : AppColor.disabledText)
        .height(40)
        .padding({ left: AppDim.gap16, right: AppDim.gap16 })
        .textAlign(TextAlign.Center)
        .backgroundColor(this.count > 0 ? AppColor.accentFill : AppColor.disabledBg)
        .borderRadius(AppDim.pillRadius)
        .margin({ left: AppDim.gap8 })
        .enabled(this.count > 0)
        .onClick(() => {
          this.onRemove();
        })
    }
    .width('100%')
    .height(60)
    .padding({ left: AppDim.gap16, right: AppDim.gap16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppColor.bgSurface)
    .border({ width: { top: 0.5 }, color: AppColor.divider })
  }
}
