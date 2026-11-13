import { KeyboardAvoidMode, window } from '@kit.ArkUI';
import { BreakpointHost, BreakpointService, ConnectionHost, ConnectionHub } from 'commons_basic';
import { AppColor } from 'commons_ui';
import { TradeVM } from '../viewmodel/TradeVM';
import { TradeEditView } from './TradeEditView';
import { TradeConfirmView } from './TradeConfirmView';
import { TradeLoginView } from './TradeLoginView';
import { toastText } from './TradeText';

/**
 * 买入弹窗壳（FR-07.2 / 设计 §5.4.1）：
 * - sm/md：底部 sheet（近满宽、上圆角、预留安全区）；lg/xl：640vp 居中模态。
 * - 单容器两层（INV-T2）：登录 / 编辑 / 确认任一时刻只渲染一层。
 * - 遮罩点击、系统返回、X 统一交 VM 的关闭矩阵处理。
 * - 键盘：不做系统避让（NONE），自持键盘高度把弹窗整体抬到键盘上沿（距 8vp），
 *   同时收紧卡片高度上限，保证主按钮可见可点（FR-07.2）。
 */
@ComponentV2
export struct TradeSheet {
  @Param vm: TradeVM = new TradeVM();
  @Param bottomInset: number = 0;
  @Event onClosed: () => void = (): void => {
  };
  @Local breakpoint: BreakpointService = BreakpointHost.getService();
  @Local hub: ConnectionHub = ConnectionHost.getService();
  @Local keyboardVp: number = 0;
  @Local windowHeightVp: number = 0;
  private prevAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET;
  private hostWindow: window.Window | undefined = undefined;
  /** 异步拿到窗口前组件可能已卸载：置位后不再注册监听。 */
  private detached: boolean = false;

  aboutToAppear(): void {
    try {
      this.prevAvoidMode = this.getUIContext().getKeyboardAvoidMode();
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    } catch (err) {
      // 老版本无该能力时保持系统默认避让。
    }
    window.getLastWindow(getContext(this)).then((win: window.Window): void => {
      if (this.detached) {
        return;
      }
      this.hostWindow = win;
      try {
        this.windowHeightVp = this.getUIContext().px2vp(win.getWindowProperties().windowRect.height);
      } catch (err) {
        this.windowHeightVp = 0;
      }
      win.on('keyboardHeightChange', (height: number): void => {
        try {
          this.keyboardVp = this.getUIContext().px2vp(height);
        } catch (err) {
          this.keyboardVp = 0;
        }
      });
    }).catch((): void => {
    });
  }

  aboutToDisappear(): void {
    this.detached = true;
    try {
      this.getUIContext().setKeyboardAvoidMode(this.prevAvoidMode);
    } catch (err) {
      // 忽略恢复失败。
    }
    if (this.hostWindow !== undefined) {
      this.hostWindow.off('keyboardHeightChange');
      this.hostWindow = undefined;
    }
  }

  @Monitor('hub.changeSeq')
  onNetChanged(): void {
    // 弹窗打开期间断线/恢复：提示条与主按钮状态实时跟随（CC-7.6）。
    this.vm.applyNetState(this.hub.isOffline());
  }

  @Monitor('vm.phase')
  onPhaseChanged(): void {
    if (this.vm.phase === 'closed') {
      // 让入口拦截的 toast 先出现，再交给壳层卸载。
      setTimeout((): void => {
        this.onClosed();
      }, 30);
    }
  }

  @Monitor('vm.toastSeq')
  onToast(): void {
    const message: ResourceStr = toastText(this.vm.toastCode, this.vm.queryOrderId);
    if (message === '') {
      return;
    }
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
  }

  /** lg/xl 居中模态；sm/md 底部 sheet（设计 §5.4.1）。 */
  private wide(): boolean {
    return this.breakpoint.viewportWidth >= 840;
  }

  /** 键盘弹起时把卡高上限压到「键盘上方可用高度」，主按钮才不会被键盘盖住。 */
  private maxCardHeight(): number {
    const screen: number = this.windowHeightVp > 0 ? this.windowHeightVp : 700;
    const ratio: number = this.wide() ? 0.82 : 0.9;
    const cap: number = screen * ratio;
    if (this.keyboardVp <= 0) {
      return cap;
    }
    return Math.max(260, Math.min(cap, screen - this.keyboardVp - 24));
  }

  @Builder
  scrimLayer() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(AppColor.scrim)
      .onClick(() => {
        this.vm.tapBackdrop();
      })
  }

  @Builder
  cardLayer() {
    Column() {
      if (this.vm.phase === 'login') {
        TradeLoginView({ vm: this.vm, bottomInset: this.bottomInset })
      } else if (this.vm.phase === 'confirm') {
        TradeConfirmView({ vm: this.vm, bottomInset: this.bottomInset, keyboardUp: this.keyboardVp > 0 })
      } else {
        TradeEditView({ vm: this.vm, bottomInset: this.bottomInset, keyboardUp: this.keyboardVp > 0 })
      }
    }
    .width(this.wide() ? 640 : '100%')
    .constraintSize({ maxHeight: this.maxCardHeight() })
    .margin({ bottom: this.keyboardVp > 0 ? this.keyboardVp + 8 : 0 })
    .backgroundColor(AppColor.bgPage)
    .borderRadius({
      topLeft: 22,
      topRight: 22,
      bottomLeft: this.wide() ? 22 : 0,
      bottomRight: this.wide() ? 22 : 0
    })
    .clip(true)
    .shadow({ radius: 24, color: AppColor.barShadow, offsetY: 8 })
  }

  build() {
    if (this.vm.phase === 'resolving' || this.vm.phase === 'closed') {
      // 加载/关闭期不留残影：不渲染遮罩与卡片。
      Stack() {
      }
      .width(0)
      .height(0)
    } else if (this.wide()) {
      // lg/xl：居中模态，640vp 恒定宽（不随屏宽拉伸）。
      Stack() {
        this.scrimLayer()
        this.cardLayer()
      }
      .width('100%')
      .height('100%')
    } else {
      // sm/md：底部 sheet（贴底、上圆角、预留安全区）。
      Stack({ alignContent: Alignment.Bottom }) {
        this.scrimLayer()
        this.cardLayer()
      }
      .width('100%')
      .height('100%')
    }
  }
}
