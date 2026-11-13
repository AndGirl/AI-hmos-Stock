import { AppColor, AppDim } from 'commons_ui';

/** 输入上限（FR-05.2 / AC-87-4）：与 normalizeTerm 的 20 字截断保持一致。 */
const TERM_MAX_LENGTH: number = 20;

/**
 * 搜索输入条（M6-4 / G-1）：44vp 高、22vp 圆角、左侧放大镜、右侧清除；
 * push 形态追加「取消」。键盘为 search 类型，Enter 立即查（FR-05.3）。
 */
@ComponentV2
export struct SearchBar {
  @Param term: string = '';
  @Param placeholder: ResourceStr = $r('app.string.search_bar_placeholder');
  @Param showCancel: boolean = false;
  @Param autoFocus: boolean = false;
  @Event onTermChange: (text: string) => void = (text: string): void => {
  };
  @Event onSubmit: () => void = (): void => {
  };
  @Event onCancel: () => void = (): void => {
  };

  build() {
    Row() {
      Row() {
        Image($r('app.media.ic_search'))
          .width(16)
          .height(16)
          .fillColor(AppColor.textSecondary)
          .margin({ left: 16 })

        TextInput({ text: this.term, placeholder: this.placeholder })
          .layoutWeight(1)
          .height(44)
          .padding({ left: 8, right: 8 })
          .backgroundColor(AppColor.transparent)
          .borderRadius(0)
          .fontSize(15)
          .fontColor(AppColor.textPrimary)
          .placeholderColor(AppColor.textSecondary)
          .type(InputType.Normal)
          .maxLength(TERM_MAX_LENGTH)
          .enterKeyType(EnterKeyType.Search)
          .defaultFocus(this.autoFocus)
          .onChange((value: string): void => {
            this.onTermChange(value);
          })
          .onSubmit((enterKey: EnterKeyType): void => {
            this.onSubmit();
          })

        if (this.term.length > 0) {
          Image($r('app.media.ic_close'))
            .width(20)
            .height(20)
            .fillColor(AppColor.textSecondary)
            .margin({ right: 12 })
            .accessibilityText($r('app.string.search_clear'))
            .onClick(() => {
              this.onTermChange('');
            })
        }
      }
      .layoutWeight(1)
      .height(44)
      .backgroundColor(AppColor.bgSurface)
      .borderRadius(22)
      .border({ width: 0.5, color: AppColor.divider })
      .alignItems(VerticalAlign.Center)

      if (this.showCancel) {
        Text($r('app.string.search_cancel'))
          .fontSize(15)
          .fontColor(AppColor.accent)
          .height(44)
          .padding({ left: AppDim.gap12, right: AppDim.gap4 })
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onCancel();
          })
      }
    }
    .width('100%')
    .padding({ left: AppDim.gap16, right: AppDim.gap16, top: AppDim.gap8, bottom: AppDim.gap8 })
    .alignItems(VerticalAlign.Center)
  }
}
