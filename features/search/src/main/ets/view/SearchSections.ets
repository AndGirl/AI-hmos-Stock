import { AppColor, AppDim } from 'commons_ui';
import { SearchRowVM } from '../viewmodel/SearchRowVM';
import { SearchItemVM } from '../viewmodel/SearchSectionVM';
import { SearchRowView } from './SearchRowView';

/**
 * 结果分段（M6-4 / FR-05.5）：股票 / 指数 / 板块三段，每段默认 20 条可展开。
 * 消费 VM 拍平后的 `items`（标题 / 行 / 展开），key 由 VM 生成，结果刷新必换 key。
 */
@ComponentV2
export struct SearchSections {
  @Param items: SearchItemVM[] = [];
  @Param showAdd: boolean = true;
  @Event onTapRow: (row: SearchRowVM) => void = (row: SearchRowVM): void => {
  };
  @Event onAddRow: (row: SearchRowVM) => void = (row: SearchRowVM): void => {
  };
  @Event onToggle: (sectionIndex: number) => void = (sectionIndex: number): void => {
  };

  private titleOf(kind: string): ResourceStr {
    if (kind === 'index') {
      return $r('app.string.search_section_index');
    }
    if (kind === 'sector') {
      return $r('app.string.search_section_sector');
    }
    return $r('app.string.search_section_stock');
  }

  build() {
    List() {
      ForEach(this.items, (item: SearchItemVM) => {
        ListItem() {
          if (item.kind === 'header') {
            Row() {
              Text(this.titleOf(item.sectionKind))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColor.textSecondary)
              Text(`${item.total}`)
                .fontSize(11)
                .fontColor(AppColor.textSecondary)
                .margin({ left: AppDim.gap4 })
            }
            .width('100%')
            .height(32)
            .padding({ left: AppDim.gap16, right: AppDim.gap16 })
            .alignItems(VerticalAlign.Center)
            .backgroundColor(AppColor.bgPage)
          } else if (item.kind === 'row') {
            SearchRowView({
              row: item.row,
              showAdd: this.showAdd,
              onTap: (tapped: SearchRowVM): void => {
                this.onTapRow(tapped);
              },
              onAdd: (target: SearchRowVM): void => {
                this.onAddRow(target);
              }
            })
          } else {
            Row() {
              Text(item.kind === 'expand' ? $r('app.string.search_section_more') :
                $r('app.string.search_section_less'))
                .fontSize(13)
                .fontColor(AppColor.accent)
            }
            .width('100%')
            .height(40)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.onToggle(item.sectionIndex);
            })
          }
        }
      }, (item: SearchItemVM) => item.key)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}
