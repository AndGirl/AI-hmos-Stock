import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'Orientation';

/**
 * 屏幕方向挂载点（M12-1）：
 * 应用不全局锁方向；只在详情页可见时允许系统旋转（AUTO_ROTATION_RESTRICTED），
 * 离开详情页恢复 UNSPECIFIED，保持「仅详情页横屏」的验收口径（CK-8）。
 * 其它页仍跟随系统；若真机实测自动旋转开启时其它页也会转，再补手机专用锁（见验收文档缺口）。
 */
export class OrientationHost {
  private static mainWindow: window.Window | undefined = undefined;
  private static current: window.Orientation = window.Orientation.UNSPECIFIED;

  static init(mainWindow: window.Window): void {
    OrientationHost.mainWindow = mainWindow;
    OrientationHost.current = window.Orientation.UNSPECIFIED;
  }

  static detach(): void {
    OrientationHost.mainWindow = undefined;
    OrientationHost.current = window.Orientation.UNSPECIFIED;
  }

  /** 详情页可见：允许系统按传感器旋转（受系统旋转锁约束）。 */
  static allowAutoRotation(): void {
    OrientationHost.apply(window.Orientation.AUTO_ROTATION_RESTRICTED);
  }

  /** 详情页隐藏/退出：恢复系统默认方向策略。 */
  static restore(): void {
    OrientationHost.apply(window.Orientation.UNSPECIFIED);
  }

  private static apply(orientation: window.Orientation): void {
    const mainWindow: window.Window | undefined = OrientationHost.mainWindow;
    if (mainWindow === undefined || OrientationHost.current === orientation) {
      return;
    }
    OrientationHost.current = orientation;
    mainWindow.setPreferredOrientation(orientation).then((): void => {
      hilog.info(DOMAIN, TAG, 'orientation=%{public}d', orientation);
    }).catch((error: Error): void => {
      OrientationHost.current = window.Orientation.UNSPECIFIED;
      hilog.warn(DOMAIN, TAG, 'setPreferredOrientation failed: %{public}s', JSON.stringify(error));
    });
  }
}
