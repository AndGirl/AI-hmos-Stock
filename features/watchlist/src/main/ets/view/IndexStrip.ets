import { AppColor, AppDim } from 'commons_ui';
import { IndexItemVM } from '../viewmodel/WatchlistVM';
import { DIR_DOWN, DIR_FLAT, DIR_UP } from '../viewmodel/WatchRowVM';

/** 指数条：只取前 N 项（3/5/5/3），不做横向滚动；无配置时整块隐藏（FR-02.6）。 */
@ComponentV2
export struct IndexStrip {
  @Param items: IndexItemVM[] = [];

  private colorOf(dir: number): Resource {
    if (dir === DIR_UP) {
      return AppColor.priceUp;
    }
    if (dir === DIR_DOWN) {
      return AppColor.priceDown;
    }
    return AppColor.priceFlat;
  }

  build() {
    Column() {
      if (this.items.length > 0) {
        Row() {
          ForEach(this.items, (item: IndexItemVM) => {
            Column() {
              Text(item.name)
                .fontSize(11)
                .fontColor(AppColor.textSecondary)
                .maxLines(1)
              Text(item.pctText)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.colorOf(item.dir))
                .maxLines(1)
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }, (item: IndexItemVM) => item.code)
        }
        .width('100%')
        .padding({ left: AppDim.gap16, right: AppDim.gap16, top: AppDim.gap8, bottom: AppDim.gap8 })
      }
    }
    .width('100%')
  }
}
