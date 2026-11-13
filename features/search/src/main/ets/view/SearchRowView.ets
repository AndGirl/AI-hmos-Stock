import { AppColor, AppDim } from 'commons_ui';
import { SearchRowVM, SEARCH_DIR_DOWN, SEARCH_DIR_UP } from '../viewmodel/SearchRowVM';
import { HighlightText } from './HighlightText';

/**
 * 搜索结果行（M6-4 / G-1）：
 * 左列名称 16sp + 代码 12sp；右列最新价 15sp + 涨跌幅 12sp；行尾 32vp「＋」
 * （已添加则显示「已添加」文字，再点一次撤出自选 —— AC-91 变更，M6 追加）。
 * 停牌/新股带标签；指数行不给「＋」，板块行不给价格。
 */
@ComponentV2
export struct SearchRowView {
  @Param row: SearchRowVM = new SearchRowVM();
  @Param showAdd: boolean = true;
  @Event onTap: (row: SearchRowVM) => void = (row: SearchRowVM): void => {
  };
  @Event onAdd: (row: SearchRowVM) => void = (row: SearchRowVM): void => {
  };

  private pctColor(): Resource {
    if (this.row.dir === SEARCH_DIR_UP) {
      return AppColor.priceUp;
    }
    if (this.row.dir === SEARCH_DIR_DOWN) {
      return AppColor.priceDown;
    }
    return AppColor.textSecondary;
  }

  private priceColor(): Resource {
    if (this.row.suspended) {
      return AppColor.textSecondary;
    }
    if (this.row.dir === SEARCH_DIR_UP) {
      return AppColor.priceUp;
    }
    if (this.row.dir === SEARCH_DIR_DOWN) {
      return AppColor.priceDown;
    }
    return AppColor.textPrimary;
  }

  /** 读屏：名称、代码、价格、涨跌幅、已添加/停牌/新股（AC-89 / FR-05.12）。 */
  private accessibilityLabel(): string {
    const parts: string[] = [this.row.name, this.row.code];
    if (this.row.kind === 'sector') {
      parts.push(`涨跌幅${this.row.pctText}`);
    } else {
      parts.push(`最新价${this.row.priceText}`);
      parts.push(`涨跌幅${this.row.pctText}`);
    }
    if (this.row.suspended) {
      parts.push('停牌');
    }
    if (this.row.isNew) {
      parts.push('新股');
    }
    if (this.row.added) {
      parts.push('已添加');
    }
    return parts.join('，');
  }

  @Builder
  addAction() {
    if (this.row.added) {
      // 已添加可再点：撤出自选（AC-91 变更，M6 追加），点按不再穿透进详情。
      Text($r('app.string.search_added'))
        .fontSize(12)
        .fontColor(this.row.pending ? AppColor.disabledText : AppColor.textSecondary)
        .width(52)
        .height(32)
        .textAlign(TextAlign.End)
        .enabled(!this.row.pending)
        .accessibilityText($r('app.string.search_a11y_added'))
        .onClick(() => {
          this.onAdd(this.row);
        })
    } else {
      Text('＋')
        .fontSize(20)
        .fontColor(this.row.pending ? AppColor.disabledText : AppColor.accent)
        .width(32)
        .height(32)
        .textAlign(TextAlign.Center)
        .borderRadius(16)
        .border({ width: 1, color: AppColor.divider })
        .enabled(!this.row.pending)
        .accessibilityText($r('app.string.search_add_watchlist'))
        .onClick(() => {
          this.onAdd(this.row);
        })
    }
  }

  build() {
    Row() {
      Column() {
        Row() {
          HighlightText({
            text: this.row.name,
            ranges: this.row.nameRanges,
            textSize: 16,
            color: AppColor.textPrimary,
            a11yText: this.row.name
          })
            .layoutWeight(1)

          if (this.row.suspended) {
            Text($r('app.string.watch_tag_suspended'))
              .fontSize(10)
              .fontColor(AppColor.textSecondary)
              .borderWidth(0.5)
              .borderColor(AppColor.divider)
              .borderRadius(2)
              .padding({ left: 2, right: 2 })
              .margin({ left: AppDim.gap4 })
          }
          if (this.row.isNew) {
            Text($r('app.string.watch_tag_new'))
              .fontSize(10)
              .fontColor(AppColor.priceUp)
              .borderWidth(0.5)
              .borderColor(AppColor.priceUp)
              .borderRadius(2)
              .padding({ left: 2, right: 2 })
              .margin({ left: AppDim.gap4 })
          }
        }
        .width('100%')

        HighlightText({
          text: this.row.code,
          ranges: this.row.codeRanges,
          textSize: 12,
          weight: FontWeight.Normal,
          color: AppColor.textSecondary,
          a11yText: this.row.code
        })
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column() {
        if (this.row.kind === 'sector') {
          Text('--')
            .fontSize(15)
            .fontColor(AppColor.textSecondary)
        } else {
          Text(this.row.priceText)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.priceColor())
        }
        Text(this.row.pctText)
          .fontSize(12)
          .fontColor(this.row.kind === 'sector' ? this.pctColor() : this.priceColor())
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.End)
      .width(88)

      if (this.showAdd && this.row.kind === 'stock') {
        Row() {
          this.addAction()
        }
        .width(60)
        .justifyContent(FlexAlign.End)
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: AppDim.gap16, right: AppDim.gap16 })
    .alignItems(VerticalAlign.Center)
    .opacity(this.row.suspended ? 0.55 : 1)
    .backgroundColor(AppColor.transparent)
    .border({ width: { bottom: 0.5 }, color: AppColor.divider })
    .accessibilityText(this.accessibilityLabel())
    .onClick(() => {
      this.onTap(this.row);
    })
  }
}
