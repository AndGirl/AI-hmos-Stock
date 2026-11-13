/**
 * 系统返回键分发（M8，关闭 M7 遗留 §9-28⑥）：
 * 自选页在 TabShell 的 TabContent 内，没有 NavDestination 的 `onBackPressed` 挂点，
 * 因此由 `UIAbility.onBackPressed` 统一转发到本分发器，页面自行注册「软浮层 / 编辑态」的退栈。
 *
 * 约定：
 * - 处理器返回 true 表示已消费（系统不再退出应用），false 表示继续向上/退出；
 * - 后注册的先执行（页面覆盖页面的语义）；
 * - 页面必须在 `aboutToDisappear` 注销，避免销毁后仍消费返回键。
 */
export type BackHandler = () => boolean;

export class BackDispatcher {
  private static handlers: BackHandler[] = [];

  static register(handler: BackHandler): void {
    if (BackDispatcher.handlers.indexOf(handler) >= 0) {
      return;
    }
    BackDispatcher.handlers.push(handler);
  }

  static unregister(handler: BackHandler): void {
    const index: number = BackDispatcher.handlers.indexOf(handler);
    if (index >= 0) {
      BackDispatcher.handlers.splice(index, 1);
    }
  }

  /** 返回 true 表示返回键已被某个页面消费。 */
  static handle(): boolean {
    for (let i = BackDispatcher.handlers.length - 1; i >= 0; i--) {
      if (BackDispatcher.handlers[i]()) {
        return true;
      }
    }
    return false;
  }

  /** 单测/热重载用：清空全部处理器。 */
  static reset(): void {
    BackDispatcher.handlers = [];
  }
}
