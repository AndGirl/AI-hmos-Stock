/**
 * 入口去重（FR-06.2）：同一 key 在 300ms 窗口内只放行一次。
 * 设计只在 detail 入口使用（key = detail:{code}），写在这里便于后续入口复用。
 */
export class NavigationGuard {
  static readonly WINDOW_MS: number = 300;

  private static lastKey: string = '';
  private static lastAt: number = 0;

  static tryNavigate(key: string): boolean {
    const now: number = Date.now();
    if (key === NavigationGuard.lastKey && now - NavigationGuard.lastAt < NavigationGuard.WINDOW_MS) {
      return false;
    }
    NavigationGuard.lastKey = key;
    NavigationGuard.lastAt = now;
    return true;
  }
}
