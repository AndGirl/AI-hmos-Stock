import { NetState } from 'commons_basic';

/** 网络故障注入：none 正常 / weak 弱网 / offline 断线 / delayed 延迟（CC-7）。 */
export type NetFault = 'none' | NetState;

/**
 * Mock 故障注入开关（设计 §4.5「Mock 能力开关」）。
 * 仅供 debug 调试面板使用；release 由构建 profile 裁剪（M5 接正式调试面板时统一）。
 */
export class MockFaults {
  /** 自选为空（验证空态）。 */
  static emptyWatchlist: boolean = false;
  /** 自选加载失败（验证失败态与重试）。 */
  static failWatchlist: boolean = false;
  /** 详情首屏失败（验证首屏错误态与重试）。 */
  static failDetail: boolean = false;
  /** 图表失败（验证图表局部错误 + 重试，盘口/动作栏保留）。 */
  static failChart: boolean = false;
  /** 网络故障（M5-1）：驱动 ConnectionHub 的 weak / offline / delayed 三态。 */
  static netFault: NetFault = 'none';

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

  static reset(): void {
    MockFaults.emptyWatchlist = false;
    MockFaults.failWatchlist = false;
    MockFaults.failDetail = false;
    MockFaults.failChart = false;
    MockFaults.netFault = 'none';
    MockFaults.tradeNoAccount = false;
    MockFaults.tradeOffline = false;
    MockFaults.tradeClosed = false;
    MockFaults.tradeFundShort = false;
    MockFaults.tradeReject = false;
    MockFaults.tradeTimeout = false;
  }
}
