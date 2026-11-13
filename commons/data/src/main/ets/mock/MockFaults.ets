import { NetState } from 'commons_basic';

/** 网络故障注入：none 正常 / weak 弱网 / offline 断线 / delayed 延迟（CC-7）。 */
export type NetFault = 'none' | NetState;

/**
 * Mock 故障注入开关（设计 §4.5「Mock 能力开关」）。
 * 仅供 debug 调试面板使用；release 由构建 profile 裁剪（M5 接正式调试面板时统一）。
 */
export class MockFaults {
  /** 自选加载失败（验证失败态与重试）。 */
  static failWatchlist: boolean = false;
  /** 详情首屏失败（验证首屏错误态与重试）。 */
  static failDetail: boolean = false;
  /** 图表失败（验证图表局部错误 + 重试，盘口/动作栏保留）。 */
  static failChart: boolean = false;
  /** 网络故障（M5-1）：驱动 ConnectionHub 的 weak / offline / delayed 三态。 */
  static netFault: NetFault = 'none';

  /** 搜索请求失败（M6：六态之「失败」，验证重试）。 */
  static failSearch: boolean = false;
  /** 搜索限流（M6：六态之 429，3s 冷却后可重试）。 */
  static searchRateLimited: boolean = false;
  /** 热搜失败（M6：整块隐藏，不占位不报错）。 */
  static failHot: boolean = false;
  /** 慢请求（M6：把 Mock 时延拉到 1.5s，用于截取「搜索中」态）。 */
  static searchSlow: boolean = false;

  /** 行情限流（M9-4：通道持续下发 429，用于验收降频/轮询/恢复）。 */
  static quoteRateLimited: boolean = false;
  /** 429 建议等待毫秒（缺省 0 表示按 5s 下限）。 */
  static quoteRetryAfterMs: number = 0;
  /** 鉴权失败（M9-2：刷新一次票据仍失败 → unauthorized）。 */
  static quoteUnauthorized: boolean = false;
  /** 异常帧注入（M9-5：按序注入 时间回退 / 价格越界 / 超涨跌停 / 空帧）。 */
  static quoteBadFrames: boolean = false;

  /** 未开户 / 无权限：入口禁用并 toast「请先开通交易账户」（FR-07.10）。 */
  static tradeNoAccount: boolean = false;
  /** 断线：弹窗内提示条 + 主按钮禁用（CC-7.6）。 */
  static tradeOffline: boolean = false;
  /** 非交易时段：弹窗可编辑、不可提交（DEC-07-04）。 */
  static tradeClosed: boolean = false;
  /** 资金不足：可买 < 100，弹窗内提示条 + 主按钮禁用。 */
  static tradeFundShort: boolean = false;
  /** 网关拒单：失败留在确认层可改可重试（FR-07.8）。 */
  static tradeReject: boolean = false;
  /** 网关超时：2s 进入「结果未知」，禁止自动重发（FR-07.8）。 */
  static tradeTimeout: boolean = false;

  /** 持仓加载失败（M11-2：验证持仓页失败态与重试，AC-119）。 */
  static failPositions: boolean = false;

  static reset(): void {
    MockFaults.failWatchlist = false;
    MockFaults.failDetail = false;
    MockFaults.failChart = false;
    MockFaults.netFault = 'none';
    MockFaults.failSearch = false;
    MockFaults.searchRateLimited = false;
    MockFaults.failHot = false;
    MockFaults.searchSlow = false;
    MockFaults.quoteRateLimited = false;
    MockFaults.quoteRetryAfterMs = 0;
    MockFaults.quoteUnauthorized = false;
    MockFaults.quoteBadFrames = false;
    MockFaults.tradeNoAccount = false;
    MockFaults.tradeOffline = false;
    MockFaults.tradeClosed = false;
    MockFaults.tradeFundShort = false;
    MockFaults.tradeReject = false;
    MockFaults.tradeTimeout = false;
    MockFaults.failPositions = false;
  }
}
