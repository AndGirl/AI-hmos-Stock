import { promptAction } from '@kit.ArkUI';
import { AppColor, AppDim, StateMode, StateView } from 'commons_ui';
import { DEBUG } from '../../../../BuildProfile';
import { PositionAddOutcome, PositionSortKey, PositionVM } from '../viewmodel/PositionVM';
import { PositionRowVM } from '../viewmodel/PositionRowVM';
import {
  moneyText,
  percentText,
  priceText,
  qtyText,
  signedMoneyText,
  sortArrowText,
  sortKeyText,
  Tone,
  toneOf
} from './PositionText';

/** 排序字段顺序（与 AC-119 一致：市值 / 盈亏 / 盈亏比）。 */
const SORT_KEYS: PositionSortKey[] = ['marketValue', 'pnl', 'pnlRatio'];

/**
 * 持仓页（M11-2 / M11-3 / AC-119/120）。
 *
 * 结构：标题 + 口径声明 + 汇总卡 + 排序 chip + 列表（下拉刷新 / 空态 / 失败重试）+ 页脚说明。
 * 行：名称/代码（停牌标「停」）+ 市值 / 持仓·成本·现价 / 盈亏（额+率）· 仓位 + 行尾「＋」。
 * 约束：只吃 VM 暴露的类型（R-07）；颜色只用 token（D-03）；文案走资源。
 */
@ComponentV2
export struct PositionsView {
  /** 点行进详情（路由由壳层装配，本层不依赖 products）。 */
  @Param onOpenDetail: (code: string) => void = (code: string): void => {
  };
  @Local vm: PositionVM = new PositionVM();
  @Local refreshing: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.vm.load();
  }

  aboutToDisappear(): void {
    this.vm.dispose();
  }

  build() {
    Column() {
      this.header()
      this.notice()
      if (this.vm.state === 'error') {
        this.errorState()
      } else if (this.vm.state === 'loading') {
        this.loading()
      } else if (this.vm.state === 'empty') {
        this.emptyState()
      } else {
        this.summaryCard()
        this.sortBar()
        this.list()
        this.footerNote()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bgPage)
  }

  @Builder
  header() {
    Row() {
      Text($r('app.string.position_title'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColor.textPrimary)
        .layoutWeight(1)
        .gesture(
          LongPressGesture({ repeat: false })
            .onAction(() => {
              this.openDebugMenu();
            })
        )
      Text($r('app.string.position_refresh'))
        .fontSize(13)
        .fontColor(AppColor.textSecondary)
        .height(32)
        .padding({ left: AppDim.gap8, right: AppDim.gap8 })
        .onClick(() => {
          this.vm.load();
        })
    }
    .width('100%')
    .padding({ left: AppDim.gap16, right: AppDim.gap16, top: AppDim.gap8, bottom: AppDim.gap4 })
    .alignItems(VerticalAlign.Center)
  }

  /** 口径声明（T-09 / AC-121）：常显「模拟持仓」，不宣称实时行情。 */
  @Builder
  notice() {
    Row() {
      Text($r('app.string.position_notice'))
        .fontSize(11)
        .fontColor(AppColor.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(22)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppColor.bgSurface)
    .border({ width: { bottom: 0.5 }, color: AppColor.divider })
  }

  @Builder
  loading() {
    Column() {
      LoadingProgress()
        .width(32)
        .height(32)
        .color(AppColor.textSecondary)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  emptyState() {
    StateView({
      mode: StateMode.EMPTY,
      stateDesc: $r('app.string.position_empty_desc'),
      iconRes: $r('app.media.ic_tab_watchlist')
    })
      .width('100%')
      .layoutWeight(1)
  }

  @Builder
  errorState() {
    StateView({
      mode: StateMode.ERROR,
      stateDesc: $r('app.string.position_error'),
      showAction: true,
      actionLabel: $r('app.string.retry'),
      onAction: (): void => {
        this.vm.load();
      }
    })
      .width('100%')
      .layoutWeight(1)
  }

  /** 汇总卡：总市值 / 当日盈亏 / 持仓只数 / 累计盈亏+比率 / 账户 / 成本。 */
  @Builder
  summaryCard() {
    Column() {
      Row() {
        Column() {
          Text($r('app.string.position_sum_market_value'))
            .fontSize(11)
            .fontColor(AppColor.textSecondary)
          Text(moneyText(this.vm.marketValue))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColor.textPrimary)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column() {
          Text($r('app.string.position_sum_day_pnl'))
            .fontSize(11)
            .fontColor(AppColor.textSecondary)
          Text(signedMoneyText(this.vm.dayPnl))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.toneColor(toneOf(this.vm.dayPnl)))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')

      Row() {
        Text($r('app.string.position_sum_count', `${this.vm.count}`))
          .fontSize(12)
          .fontColor(AppColor.textSecondary)
        Blank()
        Text($r('app.string.position_sum_total_pnl'))
          .fontSize(11)
          .fontColor(AppColor.textSecondary)
          .margin({ right: AppDim.gap4 })
        Text(`${signedMoneyText(this.vm.totalPnl)}（${percentText(this.vm.pnlRatio, true)}）`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.toneColor(toneOf(this.vm.totalPnl)))
      }
      .width('100%')
      .margin({ top: AppDim.gap8 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Text($r('app.string.position_account_line', this.vm.accountMask))
          .fontSize(11)
          .fontColor(AppColor.textSecondary)
        Blank()
        Text($r('app.string.position_sum_cost', moneyText(this.vm.costTotal)))
          .fontSize(11)
          .fontColor(AppColor.textSecondary)
      }
      .width('100%')
      .margin({ top: AppDim.gap4 })
      .alignItems(VerticalAlign.Center)

      if (this.vm.unvalued > 0) {
        Text($r('app.string.position_unvalued', `${this.vm.unvalued}`))
          .fontSize(11)
          .fontColor(AppColor.textSecondary)
          .width('100%')
          .margin({ top: AppDim.gap4 })
      }

      Text($r('app.string.position_metrics_note'))
        .fontSize(10)
        .fontColor(AppColor.textSecondary)
        .width('100%')
        .margin({ top: AppDim.gap8 })
    }
    .width('100%')
    .padding({
      left: AppDim.gap16,
      right: AppDim.gap16,
      top: AppDim.gap12,
      bottom: AppDim.gap12
    })
    .backgroundColor(AppColor.bgSurface)
    .border({ width: { bottom: 0.5 }, color: AppColor.divider })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  sortBar() {
    Row() {
      ForEach(SORT_KEYS, (key: PositionSortKey) => {
        this.sortChip(key)
      }, (key: PositionSortKey) => key)
      Blank()
    }
    .width('100%')
    .height(40)
    .padding({ left: AppDim.gap16, right: AppDim.gap16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppColor.bgPage)
  }

  @Builder
  sortChip(key: PositionSortKey) {
    Row() {
      Text(sortKeyText(key))
        .fontSize(12)
        // 选中态用「浅红底 + 主文本色」：`accent` 打在 `accentSoft` 上浅色对比度不足（3.83），
        // 文字改 `textPrimary`，箭头仍用 `accent` 表达方向。
        .fontColor(this.isActiveSort(key) ? AppColor.textPrimary : AppColor.textSecondary)
        .fontWeight(this.isActiveSort(key) ? FontWeight.Medium : FontWeight.Normal)
      if (this.isActiveSort(key)) {
        Text(sortArrowText(this.vm.sortDir))
          .fontSize(12)
          .fontColor(AppColor.accent)
          .margin({ left: 2 })
      }
    }
    .height(28)
    .padding({ left: AppDim.gap12, right: AppDim.gap12 })
    .borderRadius(AppDim.pillRadius)
    .backgroundColor(this.isActiveSort(key) ? AppColor.accentSoft : AppColor.bgSurface)
    .margin({ right: AppDim.gap8 })
    .accessibilityText(`${this.stringOf(sortKeyText(key))}，` +
      `${this.stringOf(this.sortHint(this.isActiveSort(key) ? this.vm.sortDir : 'none'))}`)
    .onClick(() => {
      this.vm.cycleSort(key);
    })
  }

  @Builder
  list() {
    Refresh({ refreshing: $$this.refreshing }) {
      List({ scroller: this.scroller }) {
        ForEach(this.vm.rows, (row: PositionRowVM) => {
          ListItem() {
            this.positionRow(row)
          }
        }, (row: PositionRowVM) => row.code)
      }
      .id('position_list')
      .width('100%')
      .height('100%')
      .divider({ strokeWidth: 0.5, color: AppColor.divider })
    }
    .layoutWeight(1)
    .onRefreshing(() => {
      this.vm.load().then((): void => {
        this.refreshing = false;
      }).catch((): void => {
        this.refreshing = false;
      });
    })
  }

  /** 单行：名称/代码 + 市值 / 持仓·成本·现价 / 盈亏（额+率）· 仓位 + 行尾操作。 */
  @Builder
  positionRow(row: PositionRowVM) {
    Column() {
      Row() {
        Column() {
          Text(row.name)
            .fontSize(15)
            .fontColor(AppColor.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row() {
            Text(row.code)
              .fontSize(11)
              .fontColor(AppColor.textSecondary)
            if (row.suspended) {
              Text($r('app.string.position_status_suspended'))
                .fontSize(10)
                .fontColor(AppColor.textSecondary)
                .padding({ left: 3, right: 3 })
                .border({ width: 0.5, color: AppColor.dividerStrong, radius: 2 })
                .margin({ left: AppDim.gap4 })
            }
          }
          .margin({ top: 2 })
          .alignItems(VerticalAlign.Center)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column() {
          Text(moneyText(row.marketValue))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.textPrimary)
          Text($r('app.string.position_row_value'))
            .fontSize(10)
            .fontColor(AppColor.textSecondary)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.End)

        if (row.added) {
          Text($r('app.string.search_added'))
            .fontSize(11)
            .fontColor(AppColor.textSecondary)
            .height(32)
            .width(52)
            .textAlign(TextAlign.Center)
            .margin({ left: AppDim.gap8 })
            .accessibilityText($r('app.string.search_a11y_added'))
        } else {
          Text('＋')
            .fontSize(18)
            .fontColor(AppColor.accent)
            .height(32)
            .width(40)
            .textAlign(TextAlign.Center)
            .margin({ left: AppDim.gap8 })
            .accessibilityText($r('app.string.search_add_watchlist'))
            .onClick(() => {
              this.addWatch(row);
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row() {
        Text($r('app.string.position_row_qty_cost', qtyText(row.qty), priceText(row.costPrice)))
          .fontSize(12)
          .fontColor(AppColor.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text($r('app.string.position_row_last', priceText(row.last)))
          .fontSize(12)
          .fontColor(row.suspended ? AppColor.textSecondary : AppColor.textPrimary)
      }
      .width('100%')
      .margin({ top: 6 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Text($r('app.string.position_row_pnl', signedMoneyText(row.pnl),
          percentText(row.pnlRatio, true)))
          .fontSize(12)
          .fontColor(this.toneColor(toneOf(row.pnl)))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text($r('app.string.position_row_weight', percentText(row.weight, false)))
          .fontSize(12)
          .fontColor(AppColor.textSecondary)
      }
      .width('100%')
      .margin({ top: 4 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({
      left: AppDim.gap16,
      right: AppDim.gap16,
      top: AppDim.gap12,
      bottom: AppDim.gap12
    })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(AppColor.bgSurface)
    .id(`position_row_${row.code}`)
    .accessibilityGroup(true)
    .accessibilityText($r('app.string.position_a11y_row', row.name, row.code,
      moneyText(row.marketValue), signedMoneyText(row.pnl), percentText(row.weight, false)))
    .onClick(() => {
      this.onOpenDetail(row.code);
    })
  }

  /** 页脚：卖出入口说明（M11 持仓页不做买卖，卖出走个股详情交易弹窗）。 */
  @Builder
  footerNote() {
    Row() {
      Text($r('app.string.position_sell_note'))
        .fontSize(11)
        .fontColor(AppColor.textSecondary)
    }
    .width('100%')
    .height(28)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppColor.bgPage)
  }

  private isActiveSort(key: PositionSortKey): boolean {
    return this.vm.sortKey === key && this.vm.sortDir !== 'none';
  }

  private sortHint(dir: string): Resource {
    if (dir === 'desc') {
      return $r('app.string.position_sort_hint_desc');
    }
    if (dir === 'asc') {
      return $r('app.string.position_sort_hint_asc');
    }
    return $r('app.string.position_sort_hint_none');
  }

  private toneColor(tone: Tone): Resource {
    if (tone === 'up') {
      return AppColor.priceUp;
    }
    if (tone === 'down') {
      return AppColor.priceDown;
    }
    return AppColor.priceFlat;
  }

  /** 取资源字符串（异步能力不可用时回落空串，不阻塞读屏）。 */
  private stringOf(res: Resource): string {
    try {
      const ctx = this.getUIContext().getHostContext();
      if (ctx === undefined) {
        return '';
      }
      return ctx.resourceManager.getStringSync(res.id);
    } catch (err) {
      return '';
    }
  }

  /** 加自选（AC-120）：结果 → 文案；失败不改变按钮态。 */
  private addWatch(row: PositionRowVM): void {
    this.vm.toggleWatch(row).then((outcome: PositionAddOutcome): void => {
      if (outcome === 'added') {
        this.toast($r('app.string.search_add_success'));
      } else if (outcome === 'existed') {
        this.toast($r('app.string.position_added_existed'));
      } else if (outcome === 'limit') {
        this.toast($r('app.string.add_limit_hint', '50'));
      } else {
        this.toast($r('app.string.add_failed'));
      }
    }).catch((): void => {
    });
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
  }

  /**
   * 调试菜单（仅 debug，长按标题）：验失败态与空态。
   * release 由 BuildProfile.DEBUG=false 关闭。
   */
  private openDebugMenu(): void {
    if (!DEBUG) {
      return;
    }
    const b0: promptAction.Button = { text: '模拟加载失败', color: AppColor.debug };
    const b1: promptAction.Button = { text: '恢复加载', color: AppColor.debug };
    const b2: promptAction.Button = { text: '重置账户与委托（回种子）', color: AppColor.debug };
    const b3: promptAction.Button = { text: '清空持仓（空态）', color: AppColor.debug };
    const b4: promptAction.Button = { text: '加停牌持仓（600000）', color: AppColor.debug };
    const b5: promptAction.Button = { text: '稳定性…（采集/压测）', color: AppColor.debug };
    const buttons: [promptAction.Button, promptAction.Button, promptAction.Button,
      promptAction.Button, promptAction.Button, promptAction.Button] = [b0, b1, b2, b3, b4, b5];
    this.getUIContext().getPromptAction().showActionMenu({ title: '持仓调试（debug）', buttons: buttons })
      .then((res: promptAction.ActionMenuSuccessResponse): void => {
        if (res.index === 0) {
          this.vm.debugFail(true);
        } else if (res.index === 1) {
          this.vm.debugFail(false);
        } else if (res.index === 2) {
          this.vm.debugResetAccount().then((): void => {
            this.toast('已重置账户与持仓（3 只样例）');
          }).catch((): void => {
          });
        } else if (res.index === 3) {
          this.vm.debugClearHoldings().then((): void => {
            this.toast('已清空持仓，可用「重置账户」恢复');
          }).catch((): void => {
          });
        } else if (res.index === 4) {
          this.vm.debugAddSuspended().then((): void => {
            this.toast('已加 600000 停牌持仓（1000 股 @9.80）');
          }).catch((): void => {
          });
        } else if (res.index === 5) {
          this.openStabilityMenu();
        }
      }).catch((): void => {
      });
  }

  /**
   * M13-3 稳定性子菜单（仅 debug）：查看计数 / 触发一次异常 / 切网 30 次压测 / 清空计数。
   * 采集只在本机（`stability_v1`），不上报、不接三方 SDK；release 由 `DEBUG` 守卫关闭。
   */
  private openStabilityMenu(): void {
    const b0: promptAction.Button = { text: '查看稳定性计数', color: AppColor.debug };
    const b1: promptAction.Button = { text: '触发一次异常（验证采集）', color: AppColor.debug };
    const b2: promptAction.Button = { text: '切网 30 次压测', color: AppColor.debug };
    const b3: promptAction.Button = { text: '清空计数', color: AppColor.debug };
    const buttons: [promptAction.Button, promptAction.Button, promptAction.Button,
      promptAction.Button] = [b0, b1, b2, b3];
    this.getUIContext().getPromptAction().showActionMenu({ title: '稳定性（debug）', buttons: buttons })
      .then((res: promptAction.ActionMenuSuccessResponse): void => {
        if (res.index === 0) {
          this.getUIContext().getPromptAction().showDialog({
            title: '稳定性计数',
            message: this.vm.debugStabilityText(),
            buttons: [{ text: '知道了', color: AppColor.accent }]
          }).catch((): void => {
          });
        } else if (res.index === 1) {
          this.vm.debugStabilityRaise();
        } else if (res.index === 2) {
          this.vm.debugNetStress(30).then((done: number): void => {
            this.toast(`已切换网络 ${done} 次，未崩溃`);
          }).catch((): void => {
          });
        } else if (res.index === 3) {
          this.vm.debugStabilityClear();
          this.toast('已清空稳定性计数');
        }
      }).catch((): void => {
      });
  }
}
