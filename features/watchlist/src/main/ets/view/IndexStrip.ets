import { AppColor, AppDim } from 'commons_ui';
import { IndexBarDataSource } from '../viewmodel/IndexBarDataSource';
import { DIR_DOWN, DIR_FLAT, DIR_UP, WatchRowVM } from '../viewmodel/WatchRowVM';

/** 单个条目宽度：名称 + 涨跌幅两行，超出后横向滚动。 */
const ITEM_WIDTH: number = 96;
const STRIP_HEIGHT: number = 56;
/** 推荐卡片：与指数条平级、固定在右侧，宽度固定不参与横滑。 */
const CARD_WIDTH: number = 88;
const CARD_HEIGHT: number = 48;

/**
 * 指数条 + 推荐卡片（平级）：
 * - 指数条与自选列表逐股票一一对应（同序），横向 List + LazyForEach，超出横向滚动；
 * - 推荐卡片固定在页面最右侧，与指数条同一水平带、垂直居中，不随横滑移动；
 * - 本期为样式占位（系统 token 定义），内容与点击行为后续再定。
 */
@ComponentV2
export struct IndexStrip {
  @Param source: IndexBarDataSource = new IndexBarDataSource();
  /** 集合/顺序/布局版本变化时把横向 List 复位到首项（折叠、切组、排序后都从第一只开始）。 */
  @Param version: number = 0;
  private scroller: Scroller = new Scroller();

  @Monitor('version')
  onVersionChanged(): void {
    try {
      this.scroller.scrollToIndex(0);
    } catch (err) {
      // 首帧尚未挂载时忽略
    }
  }

  private colorOf(dir: number): Resource {
    if (dir === DIR_UP) {
      return AppColor.priceUp;
    }
    if (dir === DIR_DOWN) {
      return AppColor.priceDown;
    }
    return AppColor.priceFlat;
  }

  @Builder
  recommendCard() {
    Row() {
      Text($r('app.string.watch_recommend'))
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColor.accent)
        .maxLines(1)
      Text('›')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColor.accent)
        .margin({ left: 2 })
    }
    .width(CARD_WIDTH)
    .height(CARD_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppColor.accentSoft)
    .borderRadius(AppDim.gap12)
    .margin({ left: AppDim.gap8 })
    .accessibilityText($r('app.string.watch_recommend'))
  }

  build() {
    Row() {
      List({ scroller: this.scroller }) {
        LazyForEach(this.source, (row: WatchRowVM) => {
          ListItem() {
            Column() {
              Text(row.name)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColor.textSecondary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(row.cells[2])
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.colorOf(row.dir))
                .maxLines(1)
                .width('100%')
                .margin({ top: 2 })
            }
            .width(ITEM_WIDTH)
            .height(STRIP_HEIGHT)
            .padding(AppDim.gap8)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Start)
          }
        }, (row: WatchRowVM) => row.code)
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .cachedCount(3)
      .layoutWeight(1)
      .height(STRIP_HEIGHT)

      this.recommendCard()
    }
    .width('100%')
    .height(STRIP_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .padding({ left: AppDim.gap8, right: AppDim.gap8 })
  }
}
