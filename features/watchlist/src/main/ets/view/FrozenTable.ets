import { AppColor, AppDim } from 'commons_ui';
import { emptyMetrics, NUMERIC_SORT_KEYS, SortDir, SortKey, TableMetrics } from '../viewmodel/WatchlistVM';
import { WatchRowVM } from '../viewmodel/WatchRowVM';
import { NameCell } from './NameCell';
import { QuoteRow } from './QuoteRow';

const CELL_INDEXES: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

const SORT_ASC_RES: Resource = $r('app.string.watch_sort_asc');
const SORT_DESC_RES: Resource = $r('app.string.watch_sort_desc');

const COLUMN_TITLES: Resource[] = [
  $r('app.string.watch_col_last'),
  $r('app.string.watch_col_chg'),
  $r('app.string.watch_col_pct'),
  $r('app.string.watch_col_volume'),
  $r('app.string.watch_col_last_volume'),
  $r('app.string.watch_col_amount'),
  $r('app.string.watch_col_amplitude'),
  $r('app.string.watch_col_turnover'),
  $r('app.string.watch_col_pe'),
  $r('app.string.watch_col_pb')
];

/**
 * 11 列冻结表（设计 §5.2.3 方案 C）：
 * 横向 Scroll 内含「表头 + 竖向 List」，名称列在外侧按竖向偏移 translate；
 * 表头与数据列同源横滑（零同步），名称列竖向冻结。
 */
@ComponentV2
export struct FrozenTable {
  @Param rows: WatchRowVM[] = [];
  @Param metrics: TableMetrics = emptyMetrics();
  @Param sortKey: SortKey | null = null;
  @Param sortDir: SortDir = 'none';
  @Param initialVOffset: number = 0;
  @Param initialHOffset: number = 0;
  /** 调试用：持续等速滚动（帧率采样时提供稳定负载）。 */
  @Param autoScroll: boolean = false;
  /** 多选比价态（FR-08.1）：行内出现选中圈与浅强调底。 */
  @Param selectMode: boolean = false;
  @Param selectedCodes: string[] = [];
  /** 断线置灰（CC-7.6）：只灰数据行，表头与名称列保持可读。 */
  @Param offline: boolean = false;
  /** 延迟角标（CC-7.4）：挂在涨跌幅列头。 */
  @Param delayed: boolean = false;
  @Event onSort: (key: SortKey) => void = () => {
  };
  @Event onRowTap: (code: string) => void = () => {
  };
  @Event onRowLongPress: (code: string) => void = () => {
  };
  @Event onScrollY: (offset: number) => void = () => {
  };
  @Event onScrollX: (offset: number) => void = () => {
  };
  @Local vOffset: number = 0;
  @Local hOffset: number = 0;
  private hScroller: Scroller = new Scroller();
  private vScroller: Scroller = new Scroller();
  private panX: number = 0;
  private panY: number = 0;
  private driveTimer: number = -1;
  private driveCycle: number = 0;
  private driveDown: boolean = true;
  private driveRight: boolean = true;

  aboutToAppear(): void {
    this.syncAutoScroll();
  }

  aboutToDisappear(): void {
    this.stopAutoScroll();
  }

  @Monitor('autoScroll')
  onAutoScrollChanged(): void {
    this.syncAutoScroll();
  }

  private syncAutoScroll(): void {
    if (this.autoScroll) {
      if (this.driveTimer === -1) {
        this.driveTimer = setInterval((): void => {
          this.driveScrollStep();
        }, 1600);
      }
    } else {
      this.stopAutoScroll();
    }
  }

  private stopAutoScroll(): void {
    if (this.driveTimer !== -1) {
      clearInterval(this.driveTimer);
      this.driveTimer = -1;
    }
  }

  private driveScrollStep(): void {
    this.driveCycle++;
    if (this.driveCycle % 2 === 1) {
      const target: number = this.driveDown ? 2100 : 0;
      this.driveDown = !this.driveDown;
      this.vScroller.scrollTo({
        xOffset: 0,
        yOffset: target,
        animation: { duration: 1400, curve: Curve.Linear }
      });
    } else {
      const target: number = this.driveRight ? 700 : 0;
      this.driveRight = !this.driveRight;
      this.hScroller.scrollTo({
        xOffset: target,
        yOffset: 0,
        animation: { duration: 1400, curve: Curve.Linear }
      });
    }
  }

  private fadeOpacity(): number {
    if (this.metrics.overflow <= 0) {
      return 0;
    }
    return this.hOffset < this.metrics.overflow - 8 ? 1 : 0;
  }

  private isSelected(code: string): boolean {
    return this.selectedCodes.indexOf(code) >= 0;
  }

  private sortedBy(index: number): boolean {
    const key: SortKey | null = NUMERIC_SORT_KEYS[index];
    return key !== null && this.sortKey === key && this.sortDir !== 'none';
  }

  /** 表头朗读文本：列名 + 当前排序方向（设计 §5.2.10）。 */
  private headerLabel(index: number): string {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return '';
    }
    try {
      const title: string = ctx.resourceManager.getStringSync(COLUMN_TITLES[index].id);
      if (!this.sortedBy(index)) {
        return title;
      }
      const suffix: string = ctx.resourceManager.getStringSync(
        this.sortDir === 'asc' ? SORT_ASC_RES.id : SORT_DESC_RES.id);
      return `${title}，${suffix}`;
    } catch (err) {
      return '';
    }
  }

  @Builder
  nameHeader() {
    Text($r('app.string.watch_col_name'))
      .width(this.metrics.nameWidth)
      .height(this.metrics.headerHeight)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppColor.textSecondary)
      .textAlign(TextAlign.Start)
      .padding({ left: AppDim.gap12 })
      .accessibilityText($r('app.string.watch_col_name'))
      .border({ width: { bottom: 0.5 }, color: AppColor.divider })
  }

  @Builder
  numericHeader() {
    Row() {
      ForEach(CELL_INDEXES, (index: number) => {
        Row() {
          Text(COLUMN_TITLES[index])
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.sortedBy(index) ? AppColor.accent : AppColor.textSecondary)
            .maxLines(1)
          if (this.sortedBy(index)) {
            Text(this.sortDir === 'asc' ? '↑' : '↓')
              .fontSize(10)
              .fontColor(AppColor.accent)
              .margin({ left: 2 })
          }
          // 延迟角标（CC-7.4）：只挂在涨跌幅列头，不占 banner。
          if (this.delayed && index === 2) {
            Text($r('app.string.conn_delayed_badge'))
              .fontSize(9)
              .fontColor(AppColor.textOnAccent)
              .backgroundColor(AppColor.textSecondary)
              .borderRadius(2)
              .padding({ left: 3, right: 3 })
              .margin({ left: 3 })
              .accessibilityText($r('app.string.conn_a11y_delayed'))
          }
        }
        .width(this.metrics.widths[index + 1])
        .height(this.metrics.headerHeight)
        .justifyContent(FlexAlign.End)
        .padding({ right: 4 })
        .accessibilityText(this.headerLabel(index))
        .onClick(() => {
          const key: SortKey | null = NUMERIC_SORT_KEYS[index];
          if (key !== null) {
            this.onSort(key);
          }
        })
      }, (index: number) => `h${index}`)
    }
    .width(this.metrics.numericWidth)
    .height(this.metrics.headerHeight)
    .border({ width: { bottom: 0.5 }, color: AppColor.divider })
  }

  build() {
    Row() {
      Column() {
        this.nameHeader()

        // 名称列不参与竖向滚动：内容整体 translate，用外层 Stack 做裁剪，
        // 避免 translate 后的内容视觉上盖住固定表头。
        Stack({ alignContent: Alignment.TopStart }) {
          Column() {
            ForEach(this.rows, (row: WatchRowVM) => {
              NameCell({
                row: row,
                metrics: this.metrics,
                selectMode: this.selectMode,
                selected: this.isSelected(row.code),
                onTap: (code: string): void => {
                  this.onRowTap(code);
                },
                onLongPress: (code: string): void => {
                  this.onRowLongPress(code);
                }
              })
            }, (row: WatchRowVM) => row.code)
          }
          .width(this.metrics.nameWidth)
          .translate({ y: -this.vOffset })
          .alignItems(HorizontalAlign.Start)
        }
        .width(this.metrics.nameWidth)
        .layoutWeight(1)
        .clip(true)
        .opacity(this.offline ? 0.55 : 1)
      }
      .width(this.metrics.nameWidth)
      .height('100%')
      .clip(true)
      .backgroundColor(AppColor.bgPage)
      .gesture(
        PanGesture({ direction: PanDirection.All })
          .onActionStart(() => {
            this.panX = 0;
            this.panY = 0;
          })
          .onActionUpdate((event: GestureEvent) => {
            const dx: number = event.offsetX - this.panX;
            const dy: number = event.offsetY - this.panY;
            this.panX = event.offsetX;
            this.panY = event.offsetY;
            // 名称列自身不滚动：把位移转发给数据区两个 scroller（惯性不转发，松手即停）。
            this.hScroller.scrollBy(-dx, 0);
            this.vScroller.scrollBy(0, -dy);
          })
      )

      Stack({ alignContent: Alignment.TopEnd }) {
        Scroll(this.hScroller) {
          Column() {
            this.numericHeader()

            List({ scroller: this.vScroller }) {
              ForEach(this.rows, (row: WatchRowVM) => {
                ListItem() {
                  QuoteRow({
                    row: row,
                    metrics: this.metrics,
                    selectMode: this.selectMode,
                    selected: this.isSelected(row.code),
                    onTap: (code: string): void => {
                      this.onRowTap(code);
                    },
                    onLongPress: (code: string): void => {
                      this.onRowLongPress(code);
                    }
                  })
                }
              }, (row: WatchRowVM) => row.code)
            }
            .width(this.metrics.numericWidth)
            .layoutWeight(1)
            .cachedCount(6)
            .edgeEffect(EdgeEffect.None)
            .scrollBar(BarState.Off)
            .opacity(this.offline ? 0.55 : 1)
            .onDidScroll(() => {
              this.vOffset = this.vScroller.currentOffset().yOffset;
              this.onScrollY(this.vOffset);
            })
          }
          .width(this.metrics.numericWidth)
          .height('100%')
          // 滑动条已隐藏（产品要求），底部仅保留 8vp 呼吸位
          .padding({ bottom: AppDim.gap8 })
          .backgroundColor(AppColor.bgPage)
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .width('100%')
        .height('100%')
        .onDidScroll(() => {
          this.hOffset = this.hScroller.currentOffset().xOffset;
          this.onScrollX(this.hOffset);
        })

        /*Row()
          .width(AppDim.fadeWidth)
          .height('100%')
          .linearGradient({
            angle: 90,
            colors: [[AppColor.transparent, 0.0], [AppColor.bgSurface, 1.0]]
          })
          .opacity(this.fadeOpacity())
          .hitTestBehavior(HitTestMode.None)*/
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .padding({left:AppDim.gap8,right:AppDim.gap8})
    .alignItems(VerticalAlign.Top)
    .onAppear(() => {
      if (this.initialVOffset > 0) {
        this.vScroller.scrollTo({ xOffset: 0, yOffset: this.initialVOffset, animation: false });
      }
      if (this.initialHOffset > 0) {
        this.hScroller.scrollTo({ xOffset: this.initialHOffset, yOffset: 0, animation: false });
      }
    })
  }
}
