import { AppColor, AppDim } from 'commons_ui';
import { DIR_DOWN, DIR_UP, WatchRowVM } from '../viewmodel/WatchRowVM';

/** 卡片 6 项指标的标签资源（顺序必须与 `WatchRowVM.cardValues` 一致）。 */
const METRIC_LABELS: Resource[] = [
  $r('app.string.detail_metric_open'),
  $r('app.string.detail_metric_high'),
  $r('app.string.detail_metric_low'),
  $r('app.string.detail_metric_amount'),
  $r('app.string.detail_metric_turnover'),
  $r('app.string.detail_metric_volume_ratio')
];

/**
 * 单张行情卡（M8-2，规格 §4.4-G4）：
 * 名称 + 标签 / 代码 / 最新价 + 涨跌 + 涨跌幅 / 固定 6 项指标（sm 4 项，窄卡改单列）。
 * 与列表行共用 `WatchRowVM`：推送只改该行对象 → 只重绘本卡（AC-101）。
 */
@ComponentV2
export struct CardCell {
  @Param row: WatchRowVM = new WatchRowVM('', '', []);
  @Param minCardH: number = 132;
  /** 该断点展示的指标条数（sm 4 / md 及以上 6）。 */
  @Param metricCount: number = 6;
  /** 指标区列数：卡宽 ≥200 双列，否则单列（避免 1.45× 挤压）。 */
  @Param metricColumns: number = 2;
  @Param selectMode: boolean = false;
  @Param editMode: boolean = false;
  @Param selected: boolean = false;
  @Event onTap: (code: string) => void = (code: string): void => {
  };
  @Event onLongPress: (code: string) => void = (code: string): void => {
  };
  @Local flashAlpha: number = 0;
  /** 卡身实测高度：闪烁层按它铺满（不能写 `height('100%')`，否则在自适应高度的 Stack 里会被解析成整屏高）。 */
  @Local bodyH: number = 0;

  @Monitor('row.quote.flashSeq')
  onFlashChanged(): void {
    this.flashAlpha = 0.16;
    this.getUIContext().animateTo({ duration: 320, curve: Curve.EaseOut }, () => {
      this.flashAlpha = 0;
    });
  }

  private syncBodyHeight(area: Area): void {
    const height: number = typeof area.height === 'number' ? area.height : parseFloat(`${area.height}`);
    if (isNaN(height) || Math.abs(height - this.bodyH) < 0.5) {
      return;
    }
    this.bodyH = height;
  }

  private priceColor(): Resource {
    if (this.row.dir === DIR_UP) {
      return AppColor.priceUp;
    }
    if (this.row.dir === DIR_DOWN) {
      return AppColor.priceDown;
    }
    return AppColor.priceFlat;
  }

  private flashColor(): Resource {
    if (this.row.dir === DIR_UP) {
      return AppColor.priceUp;
    }
    if (this.row.dir === DIR_DOWN) {
      return AppColor.priceDown;
    }
    return AppColor.accent;
  }

  @Builder
  tag(text: Resource, color: Resource) {
    Text(text)
      .fontSize(10)
      .fontColor(color)
      .borderWidth(0.5)
      .borderColor(color)
      .borderRadius(2)
      .padding({ left: 2, right: 2 })
      .margin({ left: AppDim.gap4 })
  }

  @Builder
  metricCell(index: number) {
    if (index < this.metricCount) {
      Column() {
        Text(METRIC_LABELS[index])
          .fontSize(11)
          .fontColor(AppColor.textSecondary)
          .maxLines(1)
        Text(this.row.cardValues[index])
          .fontSize(12)
          .fontColor(AppColor.textPrimary)
          .maxLines(1)
          .margin({ top: 1 })
      }
      .width('50%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  metricLine(index: number) {
    if (index < this.metricCount) {
      Row() {
        Text(METRIC_LABELS[index])
          .fontSize(11)
          .fontColor(AppColor.textSecondary)
          .maxLines(1)
        Blank()
        Text(this.row.cardValues[index])
          .fontSize(12)
          .fontColor(AppColor.textPrimary)
          .maxLines(1)
      }
      .width('100%')
      .height(18)
      .alignItems(VerticalAlign.Center)
    }
  }

  /** 指标区（双列 × 3 行）：md 及以上、卡宽足够时使用。 */
  @Builder
  metricGrid() {
    Column() {
      Row() {
        this.metricCell(0)
        this.metricCell(1)
      }
      .width('100%')

      Row() {
        this.metricCell(2)
        this.metricCell(3)
      }
      .width('100%')

      if (this.metricCount > 4) {
        Row() {
          this.metricCell(4)
          this.metricCell(5)
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: AppDim.gap8 })
  }

  /** 指标区（单列，标签左 / 值右）：sm 窄卡与 1.45× 字号时使用。 */
  @Builder
  metricList() {
    Column() {
      this.metricLine(0)
      this.metricLine(1)
      this.metricLine(2)
      this.metricLine(3)
      if (this.metricCount > 4) {
        this.metricLine(4)
        this.metricLine(5)
      }
    }
    .width('100%')
    .margin({ top: AppDim.gap8 })
  }

  @Builder
  cardBody() {
    Column() {
      Row() {
        Text(this.row.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.row.suspended ? AppColor.textSecondary : AppColor.textPrimary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.row.suspended) {
          this.tag($r('app.string.watch_tag_suspended'), AppColor.textSecondary)
        }
        if (this.row.isNew) {
          this.tag($r('app.string.watch_tag_new'), AppColor.priceUp)
        }
        if (this.row.pending) {
          this.tag($r('app.string.watch_pending_tag'), AppColor.textSecondary)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Text(this.row.code)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textSecondary)
        .maxLines(1)
        .margin({ top: 2 })

      Row() {
        Text(this.row.cells[0])
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.priceColor())
          .maxLines(1)
        Column() {
          Text(this.row.cells[1])
            .fontSize(12)
            .fontColor(this.priceColor())
            .maxLines(1)
          Text(this.row.cells[2])
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.priceColor())
            .maxLines(1)
            .margin({ top: 1 })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: AppDim.gap4 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: 6 })

      if (this.metricColumns === 2) {
        this.metricGrid()
      } else {
        this.metricList()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(AppDim.gap12)
    .constraintSize({ minHeight: this.minCardH })
    .backgroundColor(this.selected ? AppColor.accentSoft : AppColor.bgSurface)
    .borderRadius(AppDim.gap12)
    .border({ width: this.selected ? 1 : 0, color: AppColor.accent })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.cardBody()
      }
      .width('100%')
      .onAreaChange((old: Area, area: Area): void => {
        this.syncBodyHeight(area);
      })

      // 变动高亮（320ms 淡出，与列表行同语义）：叠一层低透明度涨跌色。
      if (this.flashAlpha > 0) {
        Column()
          .width('100%')
          .height(this.bodyH)
          .backgroundColor(this.flashColor())
          .opacity(this.flashAlpha)
          .borderRadius(AppDim.gap12)
          .hitTestBehavior(HitTestMode.None)
      }

      // 多选/编辑态勾选标（与列表中「✓」同语义）。
      if (this.selectMode || this.editMode) {
        Row() {
          Text(this.selected ? '✓' : '')
            .fontSize(12)
            .fontColor(AppColor.textOnAccent)
            .width(20)
            .height(20)
            .textAlign(TextAlign.Center)
            .borderRadius(10)
            .border({
              width: this.selected ? 0 : 1,
              color: this.selected ? AppColor.accent : AppColor.disabledText
            })
            .backgroundColor(this.selected ? AppColor.accent : AppColor.transparent)
            .accessibilityText(this.selected ? $r('app.string.watch_select_a11y') :
              $r('app.string.watch_select_a11y_off'))
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ top: AppDim.gap8, right: AppDim.gap8 })
      }
    }
    .width('100%')
    .opacity(this.row.suspended ? 0.55 : 1)
    .accessibilityGroup(true)
    .accessibilityText(this.row.cardAccessibilityLabel(this.metricCount))
    .onClick(() => {
      this.onTap(this.row.code);
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.onLongPress(this.row.code);
        })
    )
  }
}
