import { promptAction } from '@kit.ArkUI';
import { DEBUG } from '../../../../BuildProfile';
import { AppColor, AppDim } from 'commons_ui';
import { OrderListVM, OrderRowVM, ORDER_FILTERS } from '../viewmodel/OrderListVM';
import {
  filterText,
  priceText,
  progressText,
  qtyText,
  reasonText,
  sideText,
  stateText
} from './OrderText';

/**
 * 委托列表（M10-4 / M10-5 / AC-112/115/116）。
 *
 * 结构：标题 + 模拟交易声明 + 状态筛选 + 列表（下拉刷新 / 上拉分页 / 空态 / 错误重试）。
 * 未开通账户时整页换成引导卡（AC-112），不阻塞其它页面。
 * 所有文案走资源；颜色只用 token（D-03）。
 */
@ComponentV2
export struct OrdersView {
  @Param vm: OrderListVM = new OrderListVM();
  @Local refreshing: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.vm.load();
  }

  build() {
    Column() {
      this.header()
      this.notice()
      if (this.vm.state === 'no_account') {
        this.noAccountGuide()
      } else {
        this.filters()
        if (this.vm.state === 'loading') {
          this.loading()
        } else if (this.vm.state === 'error') {
          this.errorState()
        } else if (this.vm.state === 'empty') {
          this.emptyState()
        } else {
          this.orderList()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bgPage)
  }

  @Builder
  header() {
    Row() {
      Text($r('app.string.trade_orders_title'))
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
      Text('刷新')
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
  }

  @Builder
  notice() {
    Row() {
      Text($r('app.string.trade_orders_sim_notice'))
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
  filters() {
    Row() {
      Scroll() {
        Row() {
          ForEach(ORDER_FILTERS, (item: string) => {
            Text(filterText(item))
              .fontSize(13)
              .fontColor(this.vm.filter === item ? AppColor.accent : AppColor.textSecondary)
              .fontWeight(this.vm.filter === item ? FontWeight.Medium : FontWeight.Normal)
              .height(36)
              .padding({ left: AppDim.gap12, right: AppDim.gap12 })
              .onClick(() => {
                this.vm.setFilter(item);
              })
          }, (item: string) => item)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%')
    .height(44)
    .padding({ left: AppDim.gap8, right: AppDim.gap8 })
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
  errorState() {
    Column() {
      Text($r('app.string.trade_orders_error'))
        .fontSize(15)
        .fontColor(AppColor.textPrimary)
        .margin({ bottom: AppDim.gap8 })
      Text($r('app.string.trade_orders_retry'))
        .fontSize(14)
        .fontColor(AppColor.accent)
        .height(36)
        .onClick(() => {
          this.vm.load();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  emptyState() {
    Column() {
      Text($r('app.string.trade_orders_empty'))
        .fontSize(16)
        .fontColor(AppColor.textPrimary)
        .margin({ bottom: AppDim.gap8 })
      Text($r('app.string.trade_orders_empty_desc'))
        .fontSize(13)
        .fontColor(AppColor.textSecondary)
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  noAccountGuide() {
    Column() {
      Text($r('app.string.trade_orders_no_account'))
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textPrimary)
        .margin({ bottom: AppDim.gap8 })
      Text($r('app.string.trade_orders_no_account_desc'))
        .fontSize(13)
        .fontColor(AppColor.textSecondary)
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24 })
        .margin({ bottom: AppDim.gap16 })
      Button($r('app.string.trade_orders_open_account'))
        .type(ButtonType.Capsule)
        .backgroundColor(AppColor.accentFill)
        .fontColor(AppColor.textOnAccent)
        .fontSize(15)
        .height(44)
        .padding({ left: AppDim.gap24, right: AppDim.gap24 })
        .onClick(() => {
          this.vm.openAccount().then((ok: boolean): void => {
            this.toast(ok ? $r('app.string.trade_orders_opened_toast') :
              $r('app.string.trade_reason_busy'));
          });
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  orderList() {
    Refresh({ refreshing: $$this.refreshing }) {
      List({ scroller: this.scroller }) {
        ForEach(this.vm.rows, (row: OrderRowVM) => {
          ListItem() {
            this.orderRow(row)
          }
        }, (row: OrderRowVM) => row.clientOrderId)
        if (this.vm.hasMore) {
          ListItem() {
            Row() {
              Text($r('app.string.trade_orders_retry'))
                .fontSize(13)
                .fontColor(AppColor.textSecondary)
            }
            .width('100%')
            .height(44)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.vm.loadMore();
            })
          }
        }
      }
      .width('100%')
      .height('100%')
      .divider({ strokeWidth: 0.5, color: AppColor.divider })
      .onReachEnd(() => {
        this.vm.loadMore();
      })
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

  @Builder
  orderRow(row: OrderRowVM) {
    Column() {
      Row() {
        Text(sideText(row.side))
          .fontSize(12)
          .fontColor(row.side === 'sell' ? AppColor.priceDown : AppColor.priceUp)
          .fontWeight(FontWeight.Medium)
          .width(36)
        Text(row.name)
          .fontSize(15)
          .fontColor(AppColor.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(stateText(row.state))
          .fontSize(13)
          .fontColor(row.state === 'filled' ? AppColor.textPrimary :
            (row.state === 'rejected' ? AppColor.error : AppColor.textSecondary))
        if (row.cancelable) {
          Text(row.canceling ? '撤单中' : $r('app.string.trade_order_cancel'))
            .fontSize(13)
            .fontColor(row.canceling ? AppColor.textSecondary : AppColor.accent)
            .height(32)
            .padding({ left: AppDim.gap8, right: AppDim.gap8 })
            .onClick(() => {
              if (row.canceling) {
                return;
              }
              this.confirmCancel(row);
            })
        }
      }
      .width('100%')

      Row() {
        Text(`${row.code} · ${priceText(row.price)} × ${qtyText(row.qty)}`)
          .fontSize(12)
          .fontColor(AppColor.textSecondary)
          .layoutWeight(1)
        if (row.filledQty > 0 && row.state !== 'filled') {
          Text(progressText(row.filledQty, row.qty))
            .fontSize(12)
            .fontColor(AppColor.textSecondary)
        }
      }
      .width('100%')
      .margin({ top: AppDim.gap4 })

      if (row.state === 'rejected' && row.reasonCode.length > 0) {
        Text(reasonText(row.reasonCode))
          .fontSize(12)
          .fontColor(AppColor.error)
          .width('100%')
          .margin({ top: AppDim.gap4 })
      }
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
  }

  /**
   * 调试菜单（仅 debug，长按标题）：模拟未开户 / 恢复开户 / 重置账户与委托 / 清空委托。
   * release 由 BuildProfile.DEBUG=false 关闭。
   */
  private openDebugMenu(): void {
    if (!DEBUG) {
      return;
    }
    const b0: promptAction.Button = { text: '模拟未开户', color: AppColor.debug };
    const b1: promptAction.Button = { text: '恢复开户', color: AppColor.debug };
    const b2: promptAction.Button = { text: '重置账户与委托', color: AppColor.debug };
    const b3: promptAction.Button = { text: '清空委托', color: AppColor.debug };
    const buttons: [promptAction.Button, promptAction.Button, promptAction.Button,
      promptAction.Button] = [b0, b1, b2, b3];
    this.getUIContext().getPromptAction().showActionMenu({ title: '委托调试（debug）', buttons: buttons })
      .then((res: promptAction.ActionMenuSuccessResponse): void => {
        if (res.index === 0) {
          this.vm.debugSetOpened(false);
        } else if (res.index === 1) {
          this.vm.debugSetOpened(true);
        } else if (res.index === 2) {
          this.vm.debugResetAll();
        } else if (res.index === 3) {
          this.vm.debugClearOrders();
        }
      }).catch((): void => {
      });
  }

  /** 撤单二次确认（AC-116）。 */
  private confirmCancel(row: OrderRowVM): void {
    this.getUIContext().getPromptAction().showDialog({
      title: $r('app.string.trade_order_cancel'),
      message: $r('app.string.trade_order_cancel_confirm'),
      buttons: [
        { text: '取消', color: AppColor.textSecondary },
        { text: '确认撤单', color: AppColor.accent }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index !== 1) {
        return;
      }
      this.vm.cancel(row).then((code: string): void => {
        if (code === 'canceled') {
          this.toast($r('app.string.trade_order_canceled_toast'));
        } else if (code.startsWith('cancel_failed:')) {
          const reason: string = code.substring('cancel_failed:'.length);
          this.toast($r('app.string.trade_order_cancel_failed', reasonText(reason)));
        }
      });
    }).catch((): void => {
    });
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
  }
}
