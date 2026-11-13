import { AppColor, AppDim } from 'commons_ui';
import { ViewMode } from 'commons_basic';

/**
 * 视图切换（M8-3）：替换分组栏右侧原先的「卡片」文字占位。
 * 图标形态随状态（列表态显示「卡片」图标，卡片态显示「列表」图标），朗读文案同步。
 */
@ComponentV2
export struct ViewSwitch {
  @Param mode: ViewMode = 'list';
  @Event onToggle: () => void = (): void => {
  };

  build() {
    Row() {
      Image(this.mode === 'list' ? $r('app.media.ic_view_card') : $r('app.media.ic_view_list'))
        .width(18)
        .height(18)
        .fillColor(AppColor.textSecondary)
    }
    .id('view_switch')
    .width(32)
    .height(32)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppColor.bgSurface)
    .borderRadius(AppDim.gap8)
    .border({ width: 0.5, color: AppColor.divider })
    .accessibilityText(this.mode === 'list' ? $r('app.string.card_view_to_card') :
      $r('app.string.card_view_to_list'))
    .onClick(() => {
      this.onToggle();
    })
  }
}
