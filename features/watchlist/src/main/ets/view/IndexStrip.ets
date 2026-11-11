import { AppColor, AppDim } from 'commons_ui';
import { IndexBarDataSource } from '../viewmodel/IndexBarDataSource';
import { DIR_DOWN, DIR_FLAT, DIR_UP, WatchRowVM } from '../viewmodel/WatchRowVM';

/** 单个条目宽度：名称 + 涨跌幅两行，超出后横向滚动。 */
const ITEM_WIDTH: number = 96;
const STRIP_HEIGHT: number = 56;

/**
 * 指数条：与自选列表逐股票一一对应（同序），横向 List + LazyForEach，
 * 超出可视宽度横向滚动；切分组/排序时随列表行整体变化。
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

  build() {
    Column() {
      List({ scroller: this.scroller }) {
        LazyForEach(this.source, (row: WatchRowVM) => {
          ListItem() {
            Column() {
              Text(row.name)
                .fontSize(11)
                .fontColor(AppColor.textSecondary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(row.cells[2])
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.colorOf(row.dir))
                .maxLines(1)
                .width('100%')
                .margin({ top: 2 })
            }
            .width(ITEM_WIDTH)
            .height(STRIP_HEIGHT)
            .padding({ left: AppDim.gap8, right: AppDim.gap8 })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Start)
          }
        }, (row: WatchRowVM) => row.code)
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .cachedCount(3)
      .width('100%')
      .height(STRIP_HEIGHT)
      .padding({ left: AppDim.gap8, right: AppDim.gap8 })
    }
    .width('100%')
  }
}
