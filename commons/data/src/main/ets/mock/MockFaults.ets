/**
 * Mock 故障注入开关（设计 §4.5「Mock 能力开关」）。
 * 仅供 debug 调试面板使用；release 由构建 profile 裁剪（M5 接正式调试面板时统一）。
 */
export class MockFaults {
  /** 自选为空（验证空态）。 */
  static emptyWatchlist: boolean = false;
  /** 自选加载失败（验证失败态与重试）。 */
  static failWatchlist: boolean = false;

  static reset(): void {
    MockFaults.emptyWatchlist = false;
    MockFaults.failWatchlist = false;
  }
}
