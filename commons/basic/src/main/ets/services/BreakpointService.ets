import { AppStorageV2, UIContext, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

/** 产品自定义断点（ADR-02）：不用系统 WidthBreakpoint，xl 从 1180 起以覆盖平板 1180。 */
export type WidthBp = 'sm' | 'md' | 'lg' | 'xl';

export class Breakpoint {
  static readonly SM_MAX: number = 600;
  static readonly MD_MAX: number = 840;
  static readonly LG_MAX: number = 1180;
  static readonly LIST_COLUMNS: number = 11;
  static readonly DEBOUNCE_MS: number = 120;
  static readonly STORAGE_KEY: string = 'breakpoint_service_v1';
}

/**
 * 断点状态（AppStorageV2 单例，进程级）。
 * 规则：每个分支显式赋值全部派生状态，避免宽→窄切换时残留旧值（§6.1 规则 1）。
 */
@ObservedV2
export class BreakpointService {
  @Trace widthBp: WidthBp = 'sm';
  @Trace viewportWidth: number = 0;
  @Trace isSplit: boolean = false;
  @Trace listColumns: number = Breakpoint.LIST_COLUMNS;

  constructor() {
    this.widthBp = 'sm';
    this.viewportWidth = 0;
    this.isSplit = false;
    this.listColumns = Breakpoint.LIST_COLUMNS;
  }

  apply(widthVp: number): void {
    this.viewportWidth = widthVp;
    if (widthVp < Breakpoint.SM_MAX) {
      this.widthBp = 'sm';
      this.isSplit = false;
    } else if (widthVp < Breakpoint.MD_MAX) {
      this.widthBp = 'md';
      this.isSplit = false;
    } else if (widthVp < Breakpoint.LG_MAX) {
      this.widthBp = 'lg';
      this.isSplit = false;
    } else {
      this.widthBp = 'xl';
      this.isSplit = true;
    }
  }
}

/**
 * 断点服务的挂载点：在 EntryAbility.onWindowStageCreate 中 init，
 * 在 onWindowStageDestroy 中 detach。窗口尺寸事件 120ms 防抖，px→vp 走 UIContext 实例。
 */
export class BreakpointHost {
  private static service: BreakpointService | undefined = undefined;
  private static mainWindow: window.Window | undefined = undefined;
  private static sizeListener: ((size: window.Size) => void) | undefined = undefined;
  private static debounceTimer: number = -1;

  static getService(): BreakpointService {
    if (BreakpointHost.service === undefined) {
      const connected: BreakpointService | undefined = AppStorageV2.connect(
        BreakpointService,
        Breakpoint.STORAGE_KEY,
        () => new BreakpointService()
      );
      BreakpointHost.service = connected !== undefined ? connected : new BreakpointService();
    }
    return BreakpointHost.service;
  }

  static init(mainWindow: window.Window, uiContext: UIContext): void {
    const service: BreakpointService = BreakpointHost.getService();
    if (BreakpointHost.sizeListener !== undefined) {
      BreakpointHost.detach();
    }
    let widthPx: number = 0;
    try {
      widthPx = mainWindow.getWindowProperties().windowRect.width;
    } catch (error) {
      hilog.warn(DOMAIN, 'Breakpoint', 'read window rect failed: %{public}s', JSON.stringify(error));
    }
    service.apply(uiContext.px2vp(widthPx));

    const listener = (size: window.Size): void => {
      if (BreakpointHost.debounceTimer !== -1) {
        clearTimeout(BreakpointHost.debounceTimer);
      }
      BreakpointHost.debounceTimer = setTimeout(() => {
        service.apply(uiContext.px2vp(size.width));
        BreakpointHost.debounceTimer = -1;
      }, Breakpoint.DEBOUNCE_MS);
    };

    mainWindow.on('windowSizeChange', listener);
    BreakpointHost.mainWindow = mainWindow;
    BreakpointHost.sizeListener = listener;
  }

  static detach(): void {
    if (BreakpointHost.debounceTimer !== -1) {
      clearTimeout(BreakpointHost.debounceTimer);
      BreakpointHost.debounceTimer = -1;
    }
    if (BreakpointHost.mainWindow !== undefined && BreakpointHost.sizeListener !== undefined) {
      BreakpointHost.mainWindow.off('windowSizeChange', BreakpointHost.sizeListener);
    }
    BreakpointHost.mainWindow = undefined;
    BreakpointHost.sizeListener = undefined;
  }
}
