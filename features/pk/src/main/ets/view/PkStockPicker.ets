import { AppColor, AppDim } from 'commons_ui';
import { PkCandidate } from '../viewmodel/PkVM';
import { candidateSubtitle, pkPctText } from './PkText';

/**
 * 换股 / 新增窗选择器（FR-08.4）：本期候选池为自选列表（二期换 FR-05 搜索，只取 stock）。
 * 覆盖层形式（不新建页面）：点遮罩或「取消」关闭；点到已占用标的时由 VM 做两窗交换。
 */
@ComponentV2
export struct PkStockPicker {
  @Param candidates: PkCandidate[] = [];
  @Param codes: string[] = [];
  @Param targetIndex: number = -1;
  @Param loading: boolean = false;
  @Param bottomInset: number = 0;
  @Event onPick: (code: string) => void = (code: string): void => {
  };
  @Event onCancel: () => void = (): void => {
  };

  private occupiedAt(code: string): number {
    for (let i = 0; i < this.codes.length; i++) {
      if (this.codes[i] === code) {
        return i;
      }
    }
    return -1;
  }

  private title(): Resource {
    return this.targetIndex >= 0 ? $r('app.string.pk_picker_swap_title') : $r('app.string.pk_picker_title');
  }

  @Builder
  candidateRow(item: PkCandidate, occupied: number) {
    Row() {
      Column() {
        Text(item.name)
          .fontSize(15)
          .fontColor(AppColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(candidateSubtitle(item))
          .fontSize(11)
          .fontColor(AppColor.textSecondary)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.targetIndex >= 0 && occupied === this.targetIndex) {
        Text($r('app.string.pk_picker_current'))
          .fontSize(11)
          .fontColor(AppColor.accent)
      } else if (occupied >= 0) {
        Text($r('app.string.pk_picker_in_window', (occupied + 1).toString()))
          .fontSize(11)
          .fontColor(AppColor.textSecondary)
      } else {
        Text(pkPctText(item.pct))
          .fontSize(13)
          .fontColor(item.pct !== null && item.pct < 0 ? AppColor.priceDown :
            (item.pct !== null && item.pct > 0 ? AppColor.priceUp : AppColor.textPrimary))
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: AppDim.gap16, right: AppDim.gap16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(occupied >= 0 ? AppColor.accentSoft : AppColor.bgSurface)
    .border({ width: { bottom: 0.5 }, color: AppColor.divider })
    .onClick(() => {
      this.onPick(item.code);
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(AppColor.scrim)
        .onClick(() => {
          this.onCancel();
        })

      Column() {
        Row() {
          Text(this.title())
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.textPrimary)
          Blank()
          Text($r('app.string.pk_cancel'))
            .fontSize(14)
            .fontColor(AppColor.textSecondary)
            .height(36)
            .padding({ left: AppDim.gap8, right: AppDim.gap8 })
            .onClick(() => {
              this.onCancel();
            })
        }
        .width('100%')
        .height(48)
        .padding({ left: AppDim.gap16, right: AppDim.gap8 })
        .alignItems(VerticalAlign.Center)

        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(28)
              .height(28)
              .color(AppColor.accent)
          }
          .width('100%')
          .height(120)
          .justifyContent(FlexAlign.Center)
        } else if (this.candidates.length === 0) {
          Column() {
            Text($r('app.string.pk_picker_empty'))
              .fontSize(13)
              .fontColor(AppColor.textSecondary)
          }
          .width('100%')
          .height(120)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.candidates, (item: PkCandidate) => {
              ListItem() {
                this.candidateRow(item, this.occupiedAt(item.code))
              }
            }, (item: PkCandidate) => item.code)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .cachedCount(8)
        }

        Column()
          .width('100%')
          .height(this.bottomInset)
      }
      .width('100%')
      .constraintSize({ maxHeight: '72%' })
      .backgroundColor(AppColor.bgSurface)
      .borderRadius({ topLeft: 20, topRight: 20 })
      .clip(true)
      .shadow({ radius: 24, color: AppColor.barShadow, offsetY: -6 })
    }
    .width('100%')
    .height('100%')
  }
}
