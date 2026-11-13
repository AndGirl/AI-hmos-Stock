import { AppColor, AppDim } from 'commons_ui';

/**
 * 搜索历史（M6-5 / FR-05.7）：≤10 条 chip，长按单删，右上「清空」走二次确认（确认框在页面层）。
 */
@ComponentV2
export struct SearchHistoryView {
  @Param items: string[] = [];
  @Event onPick: (text: string) => void = (text: string): void => {
  };
  @Event onRemove: (text: string) => void = (text: string): void => {
  };
  @Event onClear: () => void = (): void => {
  };

  build() {
    Column() {
      Row() {
        Text($r('app.string.search_history_title'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
        Blank()
        if (this.items.length > 0) {
          Text($r('app.string.search_history_clear'))
            .fontSize(12)
            .fontColor(AppColor.textSecondary)
            .height(28)
            .onClick(() => {
              this.onClear();
            })
        }
      }
      .width('100%')
      .height(32)
      .padding({ left: AppDim.gap16, right: AppDim.gap16 })
      .alignItems(VerticalAlign.Center)

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.items, (item: string) => {
          Text(item)
            .fontSize(13)
            .fontColor(AppColor.textPrimary)
            .height(30)
            .padding({ left: AppDim.gap12, right: AppDim.gap12 })
            .backgroundColor(AppColor.fieldBg)
            .borderRadius(15)
            .margin({ right: AppDim.gap8, bottom: AppDim.gap8 })
            .accessibilityText(item)
            .accessibilityDescription($r('app.string.search_history_delete'))
            .onClick(() => {
              this.onPick(item);
            })
            .gesture(
              LongPressGesture({ repeat: false })
                .onAction(() => {
                  this.onRemove(item);
                })
            )
        }, (item: string) => item)
      }
      .width('100%')
      .padding({ left: AppDim.gap16, right: AppDim.gap16 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
