import { promptAction } from '@kit.ArkUI';
import { accessibility } from '@kit.AccessibilityKit';
import { AppColor, AppDim, GlobalBanner, showComingSoon } from 'commons_ui';
import { BreakpointHost, BreakpointService, ComingSoonText } from 'commons_basic';
import { DetailAction, showDetailActionMenu } from 'detail';
import { DEBUG } from '../../../../BuildProfile';
import { PkEntrySource, PkVM, PkWindowVM, SlotLayout } from '../viewmodel/PkVM';
import { PkToolbar } from './PkToolbar';
import { PkWindowFrame } from './PkWindowFrame';
import { PkStockPicker } from './PkStockPicker';
import { pkToastText } from './PkText';

/** 页内左右留白（窗卡与页边距）。 */
const PAGE_GUTTER: number = 12;

/**
 * 多窗宿主（DEC-08-01 的 `PaneHost` 落地）：一个页面内并排/叠放 N 个 DetailContent。
 * 约束：INV-W5 —— 本组件只持有 code 与布局参数，窗内容归各 `DetailContent`；
 * 全局 banner 与 toast 只在宿主这一层（窗内不各自叠加）。
 */
@ComponentV2
export struct PkHost {
  @Param codes: string[] = [];
  @Param focus: number = 0;
  @Param source: PkEntrySource = 'detail';
  @Param bottomInset: number = 0;
  @Event onExit: () => void = (): void => {
  };
  @Local vm: PkVM = new PkVM();
  @Local breakpoint: BreakpointService = BreakpointHost.getService();

  aboutToAppear(): void {
    this.syncViewport();
    if (this.codes.length === 0) {
      this.vm.attachEmpty();
    } else {
      this.vm.attach(this.codes, this.focus, this.source);
    }
  }

  @Monitor('breakpoint.viewportWidth')
  onViewportChanged(): void {
    this.syncViewport();
  }

  @Monitor('vm.toastSeq')
  onToast(): void {
    const message: ResourceStr = pkToastText(this.vm.toastCode);
    if (message === '') {
      return;
    }
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
  }

  /** 切窗播报（FR-08.11）：读屏用户切焦点时朗读「第 N 个窗，共 M 个」+ 标的。 */
  @Monitor('vm.focus')
  onFocusChanged(): void {
    const index: number = this.vm.focus;
    const code: string = this.vm.codeAt(index);
    if (code.length === 0) {
      return;
    }
    this.announce($r('app.string.pk_a11y_window', (index + 1).toString(),
      this.vm.windows.length.toString(), code));
  }

  @Monitor('vm.exitRequested')
  onExitRequested(): void {
    if (this.vm.exitRequested) {
      this.vm.logExit();
      this.onExit();
    }
  }

  /** 主动播报（announceForAccessibility）：失败静默，不影响交互。 */
  private announce(text: Resource): void {
    try {
      const ctx = this.getUIContext().getHostContext();
      if (ctx === undefined) {
        return;
      }
      const message: string = ctx.resourceManager.getStringSync(text.id);
      const info: accessibility.EventInfo = {
        type: 'announceForAccessibility',
        bundleName: ctx.applicationInfo.name,
        triggerAction: 'focus',
        textAnnouncedForAccessibility: message
      };
      accessibility.sendAccessibilityEvent(info).catch((): void => {
      });
    } catch (err) {
    }
  }

  /** 宿主可用宽 = 页宽 − 左右留白（布局公式按该宽计算）。 */
  private syncViewport(): void {
    const screen: number = this.breakpoint.viewportWidth > 0 ? this.breakpoint.viewportWidth : 360;
    this.vm.updateViewport(Math.max(240, screen - PAGE_GUTTER * 2));
  }

  private openWindowAction(index: number, code: string, action: DetailAction): void {
    if (action === 'watchlist') {
      showComingSoon(this.getUIContext(), ComingSoonText.ADD_WATCHLIST);
      return;
    }
    if (action === 'pk') {
      // 窗内「股票PK」= 再加一窗对比（与「+」等价）。
      this.vm.addWindow();
      return;
    }
    if (action === 'more') {
      showDetailActionMenu(this.getUIContext(), true, (picked: DetailAction): void => {
        this.openWindowAction(index, code, picked);
      });
      return;
    }
    // 紧凑版不提供去交易（FR-07.11 / AC-75）；窗内不做跨窗模态（FR-08 §4）。
  }

  /** 调试面板（仅 debug；长按工具栏触发）：降级链、订阅统计、恢复与清空持久化。 */
  private openDebugMenu(): void {
    if (!DEBUG) {
      return;
    }
    const color: string = '#E84026';
    const b0: promptAction.Button = { text: '订阅统计（日志）', color: color };
    const b1: promptAction.Button = { text: '降级：非焦点窗降频', color: color };
    const b2: promptAction.Button = { text: '降级：关闭非焦点窗', color: color };
    const b3: promptAction.Button = { text: '恢复上次对比', color: color };
    const b4: promptAction.Button = { text: '清空持久化', color: color };
    const b5: promptAction.Button = { text: '布局自检（日志）', color: color };
    const buttons: [promptAction.Button, promptAction.Button, promptAction.Button,
      promptAction.Button, promptAction.Button, promptAction.Button] = [b0, b1, b2, b3, b4, b5];
    this.getUIContext().getPromptAction().showActionMenu({
      title: '多窗调试（debug）',
      buttons: buttons
    }).then((res: promptAction.ActionMenuSuccessResponse): void => {
      this.onDebugAction(res.index);
    }).catch((): void => {
    });
  }

  private onDebugAction(index: number): void {
    if (index === 0) {
      this.getUIContext().getPromptAction().showToast({
        message: this.vm.stats(),
        duration: 2000
      });
    } else if (index === 1) {
      this.vm.degradeThrottle();
    } else if (index === 2) {
      this.vm.degradeToSingle();
    } else if (index === 3) {
      this.vm.restoreLast();
    } else if (index === 4) {
      this.vm.clearSaved();
    } else if (index === 5) {
      const slots: SlotLayout[] = this.vm.layout();
      let text: string = `n=${this.vm.windows.length} vp=${this.vm.viewport.toFixed(0)}`;
      for (let i = 0; i < slots.length; i++) {
        text += ` | ${i}:x=${slots[i].x.toFixed(0)},w=${slots[i].width.toFixed(0)}` +
          (slots[i].compact ? ',compact' : '');
      }
      this.getUIContext().getPromptAction().showToast({ message: text, duration: 3000 });
    }
  }

  @Builder
  emptyBlock() {
    Column() {
      Text($r('app.string.pk_empty_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textPrimary)
      Text($r('app.string.pk_empty_desc'))
        .fontSize(13)
        .fontColor(AppColor.textSecondary)
        .margin({ top: AppDim.gap8 })
        .textAlign(TextAlign.Center)

      Text($r('app.string.pk_choose'))
        .fontSize(15)
        .fontColor(AppColor.textOnAccent)
        .height(44)
        .width(180)
        .textAlign(TextAlign.Center)
        .backgroundColor(AppColor.accent)
        .borderRadius(AppDim.pillRadius)
        .margin({ top: AppDim.gap24 })
        .onClick(() => {
          this.vm.addWindow();
        })

      if (this.vm.hasSaved) {
        Text($r('app.string.pk_restore'))
          .fontSize(14)
          .fontColor(AppColor.textSecondary)
          .height(44)
          .width(180)
          .textAlign(TextAlign.Center)
          .margin({ top: AppDim.gap8 })
          .onClick(() => {
            this.vm.restoreLast();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  windowStack() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.vm.windows, (window: PkWindowVM, index: number) => {
        PkWindowFrame({
          window: window,
          index: index,
          count: this.vm.windows.length,
          viewport: this.vm.viewport,
          tier: this.vm.tierOf(index),
          onSelect: (target: number): void => {
            this.vm.focusWindow(target);
          },
          onSwap: (target: number): void => {
            this.vm.openPicker(target);
          },
          onClose: (target: number): void => {
            this.vm.closeWindow(target);
          },
          onAction: (target: number, code: string, action: DetailAction): void => {
            this.openWindowAction(target, code, action);
          },
          onPeriod: (id: number, period: string): void => {
            this.vm.onPeriodReported(id, period);
          }
        })
      }, (window: PkWindowVM) => `w${window.id}`)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: PAGE_GUTTER, right: PAGE_GUTTER })
    .clip(true)
  }

  build() {
    Stack() {
      Column() {
        GlobalBanner()

        PkToolbar({
          count: this.vm.windows.length,
          focus: this.vm.focus,
          deck: this.vm.kind() === 'deck',
          onSelect: (index: number): void => {
            this.vm.focusWindow(index);
          },
          onSync: (): void => {
            this.vm.syncPeriods();
          },
          onAdd: (): void => {
            this.vm.addWindow();
          },
          onLongPress: (): void => {
            this.openDebugMenu();
          }
        })

        if (this.vm.windows.length === 0) {
          this.emptyBlock()
        } else {
          this.windowStack()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: this.bottomInset })

      if (this.vm.pickerOpen) {
        PkStockPicker({
          candidates: this.vm.candidates,
          codes: this.windowCodes(),
          targetIndex: this.vm.pickerTarget,
          loading: this.vm.candidatesLoading,
          bottomInset: this.bottomInset,
          onPick: (code: string): void => {
            this.vm.pick(code);
          },
          onCancel: (): void => {
            this.vm.closePicker();
          }
        })
          .zIndex(10)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bgPage)
  }

  private windowCodes(): string[] {
    const codes: string[] = [];
    for (let i = 0; i < this.vm.windows.length; i++) {
      codes.push(this.vm.windows[i].code);
    }
    return codes;
  }
}
