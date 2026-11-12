import { AppColor, AppDim } from 'commons_ui';
import { PK_MAX_WINDOWS } from '../viewmodel/PkVM';

/**
 * PK 顶部工具栏（FR-08.3 / FR-08.5）：
 * - 左：三窗时的页面指示器（可点切换焦点；2 窗不显示，设计 §5.5.2）+ 窗数；
 * - 右：一次性「同步周期」（FR-08.6）+「+」新建窗（达 3 窗禁用，不挤掉已有窗）。
 * 长按整行 → 调试面板（release 由调用方以 BuildProfile.DEBUG 关闭）。
 */
@ComponentV2
export struct PkToolbar {
  @Param count: number = 0;
  @Param focus: number = 0;
  @Param deck: boolean = false;
  @Event onSelect: (index: number) => void = (index: number): void => {
  };
  @Event onSync: () => void = (): void => {
  };
  @Event onAdd: () => void = (): void => {
  };
  @Event onLongPress: () => void = (): void => {
  };

  private canAdd(): boolean {
    return this.count < PK_MAX_WINDOWS;
  }

  @Builder
  dot(index: number) {
    Row()
      .width(index === this.focus ? 16 : 6)
      .height(6)
      .borderRadius(3)
      .backgroundColor(index === this.focus ? AppColor.accent : AppColor.disabledText)
      .margin({ right: AppDim.gap4 })
      .onClick(() => {
        this.onSelect(index);
      })
      .accessibilityText($r('app.string.pk_a11y_indicator', (this.focus + 1).toString(),
        this.count.toString()))
  }

  build() {
    Row() {
      if (this.deck) {
        Row() {
          ForEach([0, 1, 2], (index: number) => {
            this.dot(index)
          }, (index: number) => `dot${index}`)
        }
        .margin({ right: AppDim.gap8 })
      }

      Text($r('app.string.pk_window_count', this.count.toString()))
        .fontSize(12)
        .fontColor(AppColor.textSecondary)

      Blank()

      Text($r('app.string.pk_sync_period'))
        .fontSize(12)
        .fontColor(this.count >= 2 ? AppColor.textPrimary : AppColor.disabledText)
        .height(32)
        .padding({ left: AppDim.gap8, right: AppDim.gap8 })
        .textAlign(TextAlign.Center)
        .onClick(() => {
          if (this.count >= 2) {
            this.onSync();
          }
        })

      Text('+')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.canAdd() ? AppColor.textPrimary : AppColor.disabledText)
        .width(36)
        .height(32)
        .textAlign(TextAlign.Center)
        .margin({ left: AppDim.gap4 })
        .accessibilityText($r('app.string.pk_add'))
        .backgroundColor(this.canAdd() ? AppColor.bgSurface : AppColor.disabledBg)
        .borderRadius(8)
        .onClick(() => {
          this.onAdd();
        })
    }
    .width('100%')
    .height(44)
    .padding({ left: AppDim.gap12, right: AppDim.gap8 })
    .alignItems(VerticalAlign.Center)
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.onLongPress();
        })
    )
  }
}
