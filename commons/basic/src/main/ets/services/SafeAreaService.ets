import { AppStorageV2, UIContext, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

/**
 * 安全区状态（AppStorageV2 单例，进程级；单位 vp）。
 * 数据来源：window.getWindowAvoidArea + on('avoidAreaChange')，覆盖折叠/分屏/旋转变化。
 */
@ObservedV2
export class SafeAreaService {
  @Trace topInset: number = 0;
  @Trace bottomInset: number = 0;
  @Trace leftInset: number = 0;
  @Trace rightInset: number = 0;

  constructor() {
    this.topInset = 0;
    this.bottomInset = 0;
    this.leftInset = 0;
    this.rightInset = 0;
  }

  apply(top: number, bottom: number, left: number, right: number): void {
    this.topInset = top;
    this.bottomInset = bottom;
    this.leftInset = left;
    this.rightInset = right;
  }
}

/**
 * 安全区服务挂载点：EntryAbility.onWindowStageCreate 中 init，
 * onWindowStageDestroy 中 detach。px→vp 走 UIContext 实例。
 */
export class SafeAreaHost {
  static readonly STORAGE_KEY: string = 'safe_area_service_v1';

  private static service: SafeAreaService | undefined = undefined;
  private static mainWindow: window.Window | undefined = undefined;
  private static uiContext: UIContext | undefined = undefined;
  private static listener: ((data: window.AvoidAreaOptions) => void) | undefined = undefined;

  static getService(): SafeAreaService {
    if (SafeAreaHost.service === undefined) {
      const connected: SafeAreaService | undefined = AppStorageV2.connect(
        SafeAreaService,
        SafeAreaHost.STORAGE_KEY,
        () => new SafeAreaService()
      );
      SafeAreaHost.service = connected !== undefined ? connected : new SafeAreaService();
    }
    return SafeAreaHost.service;
  }

  static init(mainWindow: window.Window): void {
    const service: SafeAreaService = SafeAreaHost.getService();
    if (SafeAreaHost.listener !== undefined) {
      SafeAreaHost.detach();
    }
    SafeAreaHost.mainWindow = mainWindow;
    try {
      SafeAreaHost.uiContext = mainWindow.getUIContext();
    } catch (error) {
      SafeAreaHost.uiContext = undefined;
      hilog.warn(DOMAIN, 'SafeArea', 'get UIContext failed: %{public}s', JSON.stringify(error));
    }
    SafeAreaHost.refresh(service);

    const listener = (data: window.AvoidAreaOptions): void => {
      SafeAreaHost.refresh(service);
    };
    mainWindow.on('avoidAreaChange', listener);
    SafeAreaHost.listener = listener;
  }

  static detach(): void {
    if (SafeAreaHost.mainWindow !== undefined && SafeAreaHost.listener !== undefined) {
      SafeAreaHost.mainWindow.off('avoidAreaChange', SafeAreaHost.listener);
    }
    SafeAreaHost.mainWindow = undefined;
    SafeAreaHost.uiContext = undefined;
    SafeAreaHost.listener = undefined;
  }

  private static refresh(service: SafeAreaService): void {
    if (SafeAreaHost.mainWindow === undefined || SafeAreaHost.uiContext === undefined) {
      return;
    }
    try {
      const systemArea: window.AvoidArea =
        SafeAreaHost.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const indicatorArea: window.AvoidArea =
        SafeAreaHost.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const ui: UIContext = SafeAreaHost.uiContext;
      const bottomPx: number = Math.max(systemArea.bottomRect.height, indicatorArea.bottomRect.height);
      service.apply(
        ui.px2vp(systemArea.topRect.height),
        ui.px2vp(bottomPx),
        ui.px2vp(systemArea.leftRect.width),
        ui.px2vp(systemArea.rightRect.width)
      );
      hilog.debug(DOMAIN, 'SafeArea', 'insets vp: top=%{public}d bottom=%{public}d left=%{public}d right=%{public}d',
        Math.round(service.topInset), Math.round(service.bottomInset),
        Math.round(service.leftInset), Math.round(service.rightInset));
    } catch (error) {
      hilog.warn(DOMAIN, 'SafeArea', 'read avoid area failed: %{public}s', JSON.stringify(error));
    }
  }
}
