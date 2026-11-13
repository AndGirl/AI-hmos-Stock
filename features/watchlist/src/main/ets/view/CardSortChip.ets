import { AppColor, AppDim } from 'commons_ui';
import { SortDir, SortKey } from '../viewmodel/WatchlistVM';

/**
 * 卡片排序 chip（M8-5 / AC-102，CK-2）：
 * 只**展示与清除**排序，不新增第三套排序态——状态就是列表列头的那一套 `sortKey/sortDir`。
 * - 无排序时整条隐藏（不占位）；
 * - 点 chip 本体 = 复用列头的循环（降序→升序→取消）；
 * - 点「×」= 清除回默认序。
 */
@ComponentV2
export struct CardSortChip {
  @Param sortKey: SortKey | null = null;
  @Param sortDir: SortDir = 'none';
  @Event onCycle: () => void = (): void => {
  };
  @Event onClear: () => void = (): void => {
  };

  private columnLabel(): Resource {
    if (this.sortKey === 'price') {
      return $r('app.string.watch_col_last');
    }
    if (this.sortKey === 'chg') {
      return $r('app.string.watch_col_chg');
    }
    if (this.sortKey === 'pct') {
      return $r('app.string.watch_col_pct');
    }
    if (this.sortKey === 'vol') {
      return $r('app.string.watch_col_volume');
    }
    if (this.sortKey === 'amt') {
      return $r('app.string.watch_col_amount');
    }
    if (this.sortKey === 'amp') {
      return $r('app.string.watch_col_amplitude');
    }
    if (this.sortKey === 'turn') {
      return $r('app.string.watch_col_turnover');
    }
    if (this.sortKey === 'pe') {
      return $r('app.string.watch_col_pe');
    }
    return $r('app.string.watch_col_pb');
  }

  private dirSymbol(): string {
    return this.sortDir === 'asc' ? '↑' : '↓';
  }

  build() {
    Row() {
      Text($r('app.string.card_sort_chip', this.columnLabel(), this.dirSymbol()))
        .fontSize(12)
        .fontColor(AppColor.accent)
        .maxLines(1)
        .accessibilityText($r('app.string.card_sort_chip', this.columnLabel(), this.dirSymbol()))
        .onClick(() => {
          this.onCycle();
        })

      Text('×')
        .id('card_sort_clear')
        .fontSize(14)
        .fontColor(AppColor.accent)
        .width(20)
        .height(20)
        .textAlign(TextAlign.Center)
        .margin({ left: AppDim.gap4 })
        .accessibilityText($r('app.string.card_sort_clear'))
        .onClick(() => {
          this.onClear();
        })
    }
    .height(26)
    .padding({ left: AppDim.gap8, right: AppDim.gap4 })
    .backgroundColor(AppColor.accentSoft)
    .borderRadius(13)
    .margin({ left: AppDim.gap16, bottom: AppDim.gap4 })
  }
}
