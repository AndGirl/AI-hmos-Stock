import { promptAction } from '@kit.ArkUI';
import { AppColor } from 'commons_ui';
import { DEBUG } from '../../../../BuildProfile';
import { TradeFaultKind, TradeVM } from '../viewmodel/TradeVM';
import { blockText, fieldErrorText, hintText } from './TradeText';

/** 调试菜单按钮色（非产品 UI，release 不展示）。 */
const DEBUG_BTN_COLOR: string = '#E84026';

/**
 * 编辑层（FR-07.4~07.6）：标的/账户上下文、价格与数量（步进 + 手输）、
 * 涨跌停与可买、字段级错误、提示条、三态主按钮（可用/禁用/loading）。
 */
@ComponentV2
export struct TradeEditView {
  @Param vm: TradeVM = new TradeVM();
  @Param bottomInset: number = 0;
  /** 键盘弹起：收紧间距并把主按钮顶到键盘上沿（FR-07.2）。 */
  @Param keyboardUp: boolean = false;
  private readonly priceInputId: string = 'trade_price_input';
  private readonly qtyInputId: string = 'trade_qty_input';
  private priceController: TextInputController = new TextInputController();
  private qtyController: TextInputController = new TextInputController();

  private ctaEnabled(): boolean {
    return this.vm.blockCode === '' && !this.vm.submitting;
  }

  private focusLater(id: string): void {
    setTimeout((): void => {
      try {
        focusControl.requestFocus(id);
      } catch (err) {
        // 输入框可能已被移除（快速连续点击），忽略即可。
      }
    }, 60);
    // 聚焦是异步的：稍后再全选，键入即覆盖旧值（避免与步进值拼接）。
    setTimeout((): void => {
      try {
        if (id === this.priceInputId) {
          this.priceController.setTextSelection(0, this.vm.priceInput.length);
        } else {
          this.qtyController.setTextSelection(0, this.vm.qtyInput.length);
        }
      } catch (err) {
        // 输入框已移除或尚未聚焦，忽略。
      }
    }, 200);
  }

  /** debug：长按标题逐态验收（未登录/未开户/断线/非交易时段/资金不足/拒单/超时）。 */
  private openDebugMenu(): void {
    if (!DEBUG) {
      return;
    }
    const b0: promptAction.Button = { text: '未登录（登录回流）', color: DEBUG_BTN_COLOR };
    const b1: promptAction.Button = { text: '未开户（入口禁用）', color: DEBUG_BTN_COLOR };
    const b2: promptAction.Button = { text: '断线（弹窗内提示）', color: DEBUG_BTN_COLOR };
    const b3: promptAction.Button = { text: '非交易时段（可填不可提）', color: DEBUG_BTN_COLOR };
    const b4: promptAction.Button = { text: '更多故障（资金/拒单/超时）', color: DEBUG_BTN_COLOR };
    const b5: promptAction.Button = { text: '恢复正常', color: DEBUG_BTN_COLOR };
    const buttons: [promptAction.Button, promptAction.Button, promptAction.Button,
      promptAction.Button, promptAction.Button, promptAction.Button] = [b0, b1, b2, b3, b4, b5];
    this.getUIContext().getPromptAction().showActionMenu({
      title: '交易调试面板（debug）',
      buttons: buttons
    }).then((res: promptAction.ActionMenuSuccessResponse): void => {
      if (res.index === 0) {
        this.vm.applyMockFault('login');
      } else if (res.index === 1) {
        this.vm.applyMockFault('account');
      } else if (res.index === 2) {
        this.vm.applyMockFault('offline');
      } else if (res.index === 3) {
        this.vm.applyMockFault('closed');
      } else if (res.index === 4) {
        this.openDebugFaultMenu();
      } else {
        this.vm.applyMockFault('reset');
      }
    }).catch((): void => {
    });
  }

  private openDebugFaultMenu(): void {
    const b0: promptAction.Button = { text: '资金不足（可买 0）', color: DEBUG_BTN_COLOR };
    const b1: promptAction.Button = { text: '拒单（风控拦截）', color: DEBUG_BTN_COLOR };
    const b2: promptAction.Button = { text: '提交超时（结果未知）', color: DEBUG_BTN_COLOR };
    const b3: promptAction.Button = { text: '恢复正常', color: DEBUG_BTN_COLOR };
    const buttons: [promptAction.Button, promptAction.Button, promptAction.Button,
      promptAction.Button] = [b0, b1, b2, b3];
    this.getUIContext().getPromptAction().showActionMenu({
      title: '提交类故障（debug）',
      buttons: buttons
    }).then((res: promptAction.ActionMenuSuccessResponse): void => {
      const kinds: TradeFaultKind[] = ['fund', 'reject', 'timeout', 'reset'];
      if (res.index >= 0 && res.index < kinds.length) {
        this.vm.applyMockFault(kinds[res.index]);
      }
    }).catch((): void => {
    });
  }

  private openAccountPicker(): void {
    const labels: string[] = this.vm.accountLabels;
    if (labels.length === 0) {
      return;
    }
    if (labels.length === 1) {
      const single: promptAction.Button = { text: labels[0], color: AppColor.textPrimary };
      const buttons: [promptAction.Button] = [single];
      this.getUIContext().getPromptAction().showActionMenu({
        title: $r('app.string.trade_account_picker'),
        buttons: buttons
      }).then((res: promptAction.ActionMenuSuccessResponse): void => {
        this.vm.switchAccount(res.index);
      }).catch((): void => {
      });
      return;
    }
    const first: promptAction.Button = { text: labels[0], color: AppColor.textPrimary };
    const second: promptAction.Button = { text: labels[1], color: AppColor.textPrimary };
    const buttons: [promptAction.Button, promptAction.Button] = [first, second];
    this.getUIContext().getPromptAction().showActionMenu({
      title: $r('app.string.trade_account_picker'),
      buttons: buttons
    }).then((res: promptAction.ActionMenuSuccessResponse): void => {
      this.vm.switchAccount(res.index);
    }).catch((): void => {
    });
  }

  @Builder
  stepButton(label: string, field: string, delta: number, a11y: Resource) {
    Stack() {
      Text(label)
        .fontSize(18)
        .fontColor(AppColor.textPrimary)
        .textAlign(TextAlign.Center)
    }
    .width(36)
    .height(36)
    .borderRadius(18)
    .backgroundColor(AppColor.bgPage)
    .accessibilityGroup(true)
    .accessibilityText(a11y)
    .onClick(() => {
      if (field === 'price') {
        this.vm.stepPrice(delta);
      } else {
        this.vm.stepQty(delta);
      }
    })
  }

  @Builder
  priceValue() {
    if (this.vm.editing === 'price') {
      TextInput({ text: this.vm.priceInput, controller: this.priceController })
        .id(this.priceInputId)
        .type(InputType.NUMBER_DECIMAL)
        .enterKeyType(EnterKeyType.Done)
        .fontSize(18)
        .fontColor(AppColor.textPrimary)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .constraintSize({ maxWidth: 180 })
        .height(40)
        .padding(0)
        .backgroundColor(AppColor.bgPage)
        .borderRadius(8)
        .onChange((value: string): void => {
          this.vm.priceInput = value;
        })
        .onSubmit((): void => {
          this.vm.commitPrice(this.vm.priceInput);
        })
        .onBlur((): void => {
          this.vm.commitPrice(this.vm.priceInput);
        })
    } else {
      Text(this.vm.priceText)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textPrimary)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .constraintSize({ maxWidth: 180 })
        .height(40)
        .maxLines(1)
        .accessibilityText($r('app.string.trade_a11y_price'))
        .onClick(() => {
          this.vm.beginEdit('price');
          this.focusLater(this.priceInputId);
        })
    }
  }

  @Builder
  qtyValue() {
    if (this.vm.editing === 'qty') {
      TextInput({ text: this.vm.qtyInput, controller: this.qtyController })
        .id(this.qtyInputId)
        .type(InputType.Number)
        .enterKeyType(EnterKeyType.Done)
        .fontSize(18)
        .fontColor(AppColor.textPrimary)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .constraintSize({ maxWidth: 180 })
        .height(40)
        .padding(0)
        .backgroundColor(AppColor.bgPage)
        .borderRadius(8)
        .onChange((value: string): void => {
          this.vm.qtyInput = value;
        })
        .onSubmit((): void => {
          this.vm.commitQty(this.vm.qtyInput);
        })
        .onBlur((): void => {
          this.vm.commitQty(this.vm.qtyInput);
        })
    } else {
      Text(this.vm.qtyText)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textPrimary)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .constraintSize({ maxWidth: 180 })
        .height(40)
        .maxLines(1)
        .accessibilityText($r('app.string.trade_a11y_qty'))
        .onClick(() => {
          this.vm.beginEdit('qty');
          this.focusLater(this.qtyInputId);
        })
    }
  }

  @Builder
  closeButton() {
    Stack() {
      Text('\u2715')
        .fontSize(15)
        .fontColor(AppColor.textSecondary)
    }
    .width(32)
    .height(32)
    .borderRadius(16)
    .backgroundColor(AppColor.bgSurface)
    .accessibilityGroup(true)
    .accessibilityText($r('app.string.trade_close'))
    .onClick(() => {
      this.vm.tryClose();
    })
  }

  @Builder
  header() {
    Row() {
      Text($r('app.string.trade_title'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColor.textPrimary)
        .gesture(
          LongPressGesture({ repeat: false })
            .onAction(() => {
              this.openDebugMenu();
            })
        )
      Blank()
      this.closeButton()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  contextRow() {
    Row() {
      Text(this.vm.symbolText + ' ' + this.vm.codeText)
        .fontSize(14)
        .fontColor(AppColor.textPrimary)
        .maxLines(1)
        .layoutWeight(1)
      Row() {
        Text($r('app.string.trade_account'))
          .fontSize(13)
          .fontColor(AppColor.textSecondary)
        Text(this.vm.accountText)
          .fontSize(13)
          .fontColor(AppColor.textPrimary)
          .margin({ left: 4 })
      }
      .accessibilityGroup(true)
      .accessibilityText($r('app.string.trade_a11y_account'))
      .onClick(() => {
        this.openAccountPicker();
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: 16, bottom: 16 })
  }

  @Builder
  priceSection() {
    Column() {
      Row() {
        Text($r('app.string.trade_price'))
          .fontSize(16)
          .fontColor(AppColor.textPrimary)
        Blank()
        Row() {
          this.stepButton('\u2212', 'price', -1, $r('app.string.trade_step_price_minus'))
          this.priceValue()
          this.stepButton('+', 'price', 1, $r('app.string.trade_step_price_plus'))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .height(48)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 4, bottom: 4 })
    .backgroundColor(AppColor.fieldBg)
    .borderRadius(12)

    Row() {
      Text($r('app.string.trade_limit_down'))
        .fontSize(12)
        .fontColor(AppColor.priceDown)
      Text(this.vm.limitDownText)
        .fontSize(12)
        .fontColor(AppColor.priceDown)
        .margin({ left: 4 })
      Text($r('app.string.trade_limit_up'))
        .fontSize(12)
        .fontColor(AppColor.priceUp)
        .margin({ left: 12 })
      Text(this.vm.limitUpText)
        .fontSize(12)
        .fontColor(AppColor.priceUp)
        .margin({ left: 4 })
    }
    .width('100%')
    .margin({ top: 6 })

    if (this.vm.priceError !== '') {
      Text(fieldErrorText(this.vm.priceError, this.vm.limitUpText, this.vm.limitDownText,
        this.vm.canBuyText))
        .fontSize(12)
        .fontColor(AppColor.error)
        .width('100%')
        .margin({ top: 6 })
    }
  }

  @Builder
  qtySection() {
    Column() {
      Row() {
        Text($r('app.string.trade_qty'))
          .fontSize(16)
          .fontColor(AppColor.textPrimary)
        Blank()
        Row() {
          this.stepButton('\u2212', 'qty', -1, $r('app.string.trade_step_qty_minus'))
          this.qtyValue()
          this.stepButton('+', 'qty', 1, $r('app.string.trade_step_qty_plus'))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .height(48)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 4, bottom: 4 })
    .backgroundColor(AppColor.fieldBg)
    .borderRadius(12)

    Row() {
      Text($r('app.string.trade_held_value', this.vm.holdText))
        .fontSize(12)
        .fontColor(AppColor.textSecondary)
      Blank()
      Text($r('app.string.trade_can_buy_value', this.vm.canBuyText))
        .fontSize(12)
        .fontColor(AppColor.textSecondary)
    }
    .width('100%')
    .margin({ top: 6 })

    if (this.vm.qtyError !== '') {
      Text(fieldErrorText(this.vm.qtyError, this.vm.limitUpText, this.vm.limitDownText,
        this.vm.canBuyText))
        .fontSize(12)
        .fontColor(AppColor.error)
        .width('100%')
        .margin({ top: 6 })
    }
  }

  @Builder
  cta() {
    Row() {
      if (this.vm.submitting) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(AppColor.textOnAccent)
        Text($r('app.string.trade_submitting'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textOnAccent)
          .margin({ left: 8 })
      } else {
        Text($r('app.string.trade_buy'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.ctaEnabled() ? AppColor.textOnAccent : AppColor.disabledText)
      }
    }
    .width('100%')
    .height(48)
    .borderRadius(24)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.ctaEnabled() ? AppColor.accent : AppColor.disabledBg)
    .margin({ top: this.keyboardUp ? 8 : 16 })
    .accessibilityGroup(true)
    .accessibilityText($r('app.string.trade_buy'))
    .enabled(this.ctaEnabled())
    .onClick(() => {
      this.vm.buy();
    })
  }

  @Builder
  contentColumn() {
    this.header()
    this.contextRow()
    this.priceSection()
    Column()
      .height(this.keyboardUp ? 8 : 16)
    this.qtySection()

    if (this.vm.hintCode !== '') {
      Text(hintText(this.vm.hintCode, this.vm.limitUpText, this.vm.limitDownText,
        this.vm.canBuyText))
        .fontSize(12)
        .fontColor(AppColor.textSecondary)
        .width('100%')
        .margin({ top: 8 })
    }

    if (this.vm.blockCode !== '') {
      Row() {
        Text(blockText(this.vm.blockCode, this.vm.canBuyText))
          .fontSize(13)
          .fontColor(AppColor.error)
      }
      .width('100%')
      .padding(10)
      .margin({ top: 12 })
      .backgroundColor(AppColor.bannerBg)
      .borderRadius(8)
    }
  }

  build() {
    // 内容可滚动、主按钮固定在卡片底部：键盘弹起时卡片被压到键盘上方，按钮始终可见（FR-07.2）。
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Column() {
          this.contentColumn()
          Column()
            .height(72)
        }
        .width('100%')
        .padding({
          left: 20,
          right: 20,
          top: this.keyboardUp ? 8 : 16,
          bottom: this.keyboardUp ? 8 : this.bottomInset + 16
        })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      Column() {
        this.cta()
      }
      .width('100%')
      .padding({
        left: 20,
        right: 20,
        top: 8,
        bottom: this.keyboardUp ? 8 : this.bottomInset + 16
      })
      .backgroundColor(AppColor.bgPage)
    }
    .width('100%')
  }
}
