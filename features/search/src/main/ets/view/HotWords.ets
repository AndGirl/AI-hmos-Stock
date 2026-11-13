import { AppColor, AppDim } from 'commons_ui';

/**
 * 热门搜索（M6-5 / G-1）：两列 × 5 行，前 3 名左侧 18vp accent 角标；
 * 三态 loading/ready/hidden —— 失败整块不渲染（AC-90），不占位、不报错。
 */
@ComponentV2
export struct HotWordsView {
  @Param words: string[] = [];
  @Param state: string = 'loading';
  @Event onPick: (text: string) => void = (text: string): void => {
  };

  private rankOf(index: number): string {
    return `${index + 1}`;
  }

  build() {
    Column() {
      if (this.state === 'ready') {
        Row() {
          Text($r('app.string.search_hot_title'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.textPrimary)
        }
        .width('100%')
        .height(32)
        .padding({ left: AppDim.gap16, right: AppDim.gap16 })
        .alignItems(VerticalAlign.Center)

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.words, (word: string, index: number) => {
            Row() {
              if (index < 3) {
                Text(this.rankOf(index))
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColor.accent)
                  .width(18)
                  .textAlign(TextAlign.Start)
              }
              Text(word)
                .fontSize(13)
                .fontColor(AppColor.textPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('50%')
            .height(36)
            .padding({ left: AppDim.gap16, right: AppDim.gap8 })
            .alignItems(VerticalAlign.Center)
            .accessibilityText(index < 3 ? `第${index + 1}名 ${word}` : word)
            .onClick(() => {
              this.onPick(word);
            })
          }, (word: string) => word)
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
