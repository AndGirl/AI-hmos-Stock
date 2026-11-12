import { AppColor, AppDim } from 'commons_ui';
import { ChartPeriod, DetailAction, DetailContent } from 'detail';
import { computeLayout, PkWindowTier, PkWindowVM, SlotLayout, windowRadius } from '../viewmodel/PkVM';
import { windowLabel } from './PkText';

/** 窗卡内左右留白（vp）。 */
const FRAME_PADDING: number = 8;

/**
 * 单窗卡片（FR-08.2 / INV-W1~W4）：窗内是独立 DetailContent 实例（window 紧凑形态），
 * 各自持 code / 周期 / 缩放 / 订阅；本组件只负责窗框、焦点高亮、换股与关闭入口。
 * 位置由 `computeLayout(count, viewport)` 现算（纯函数，三窗规模可忽略开销），
 * 卡宽 <360vp 时内容自动走 FR-06.11 紧凑版（由 DetailContent 依据 contentWidth 判定）。
 */
@ComponentV2
export struct PkWindowFrame {
  @Param window: PkWindowVM = new PkWindowVM(0, '', '');
  @Param index: number = 0;
  @Param count: number = 1;
  @Param viewport: number = 360;
  @Param tier: PkWindowTier = 'normal';
  @Event onSelect: (index: number) => void = (index: number): void => {
  };
  @Event onSwap: (index: number) => void = (index: number): void => {
  };
  @Event onClose: (index: number) => void = (index: number): void => {
  };
  @Event onAction: (index: number, code: string, action: DetailAction) => void =
    (index: number, code: string, action: DetailAction): void => {
    };
  @Event onPeriod: (id: number, period: string) => void = (id: number, period: string): void => {
  };

  private slot(): SlotLayout {
    const slots: SlotLayout[] = computeLayout(this.count, this.viewport);
    const index: number = this.index >= 0 && this.index < slots.length ? this.index : 0;
    return slots[index];
  }

  /** 内容宽 = 卡宽 − 内边距（不再兜底 200vp：388vp 三窗只有约 111vp，兜底会让内容比卡片还宽而被裁）。 */
  private contentWidth(): number {
    return Math.max(96, this.slot().width - FRAME_PADDING * 2);
  }

  /** 窗工具栏：窗序 + 换股 + 关闭（点击窗体内任意处也能聚焦，见根节点 onClick）。 */
  @Builder
  windowBar() {
    Row() {
      Text($r('app.string.pk_window_index', windowLabel(this.index)))
        .fontSize(11)
        .fontColor(this.window.focused ? AppColor.accent : AppColor.textSecondary)
        .maxLines(1)
        .height(28)
        .padding({ left: AppDim.gap4, right: AppDim.gap4 })
        .accessibilityText($r('app.string.pk_a11y_focus_window', windowLabel(this.index)))
        .onClick(() => {
          this.onSelect(this.index);
        })
      Blank()
      Text($r('app.string.pk_swap'))
        .fontSize(12)
        .fontColor(AppColor.textPrimary)
        .height(28)
        .padding({ left: AppDim.gap8, right: AppDim.gap8 })
        .onClick(() => {
          this.onSwap(this.index);
        })
      Text('×')
        .fontSize(16)
        .fontColor(AppColor.textSecondary)
        .width(28)
        .height(28)
        .textAlign(TextAlign.Center)
        .margin({ left: AppDim.gap4 })
        .accessibilityText($r('app.string.pk_close'))
        .onClick(() => {
          this.onClose(this.index);
        })
    }
    .width('100%')
    .height(32)
    .padding({ left: AppDim.gap8, right: AppDim.gap4 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      this.windowBar()

      DetailContent({
        code: this.window.code,
        mode: 'window',
        contentWidth: this.contentWidth(),
        bottomInset: 0,
        tier: this.tier,
        syncPeriod: this.window.period,
        syncSeq: this.window.syncSeq,
        onAction: (action: DetailAction): void => {
          this.onAction(this.index, this.window.code, action);
        },
        onPeriodChanged: (code: string, period: ChartPeriod): void => {
          this.onPeriod(this.window.id, period);
        }
      })
        .layoutWeight(1)
    }
    .width(this.slot().width)
    .height('100%')
    .position({ x: this.slot().x, y: 0 })
    .zIndex(this.slot().zIndex)
    .backgroundColor(AppColor.bgSurface)
    .borderRadius(windowRadius(this.count))
    .border({
      width: this.window.focused ? 1.5 : 0.5,
      color: this.window.focused ? AppColor.accent : AppColor.divider
    })
    .clip(true)
    .shadow({ radius: 12, color: AppColor.barShadow, offsetY: 2 })
    .accessibilityText($r('app.string.pk_a11y_window', windowLabel(this.index),
      this.count.toString(), this.window.code))
    .onClick(() => {
      this.onSelect(this.index);
    })
  }
}
