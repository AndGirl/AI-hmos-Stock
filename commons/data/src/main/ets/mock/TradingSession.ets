import { TradeStatus } from '../model/QuoteModels';

/**
 * 交易时段模拟（M9，假数据口径）。
 *
 * 为什么需要：本项目**没有真实行情源**，交易时段若写死在种子里，盘前/集合竞价/午休/收盘
 * 四类流程演示不出来（原实现只有 `open` + 1 只停牌，非交易时段只能靠 MockFaults 硬注入，
 * 且与行情状态不同源，交易弹窗的时段限制会对不上）。
 *
 * 口径：
 * - 默认 `demo-open`：任何时候都按「连续竞价」跑，保证演示时行情有跳动；
 * - `auto`：按系统时间推导（9:15 竞价、9:30-11:30 / 13:00-15:00 交易、11:30-13:00 午休、其余收盘、周末收盘）；
 * - 其余为显式档位，供调试面板逐态取证。
 *
 * 只影响「非停牌/非新股」标的的状态；种子里标记为停牌/退市的标的不受时段影响。
 */
export type SessionMode = 'demo-open' | 'auto' | 'pre' | 'auction' | 'lunch' | 'closed' | 'all-suspended';

export const SESSION_MODES: SessionMode[] =
  ['auto', 'demo-open', 'pre', 'auction', 'lunch', 'closed', 'all-suspended'];

export class TradingSession {
  private static mode: SessionMode = 'demo-open';

  static current(): SessionMode {
    return TradingSession.mode;
  }

  static setMode(mode: SessionMode): void {
    TradingSession.mode = mode;
  }

  /** 当前生效的市场状态（供行情/交易同源读取）。 */
  static resolve(now: Date): TradeStatus {
    return TradingSession.statusOf(TradingSession.mode, now);
  }

  /** 纯函数：模式 + 时间 → 市场状态。 */
  static statusOf(mode: SessionMode, now: Date): TradeStatus {
    if (mode === 'demo-open') {
      return 'open';
    }
    if (mode === 'all-suspended') {
      return 'suspended';
    }
    if (mode !== 'auto') {
      return mode;
    }
    const day: number = now.getDay();
    if (day === 0 || day === 6) {
      return 'closed';
    }
    const minutes: number = now.getHours() * 60 + now.getMinutes();
    if (minutes < 9 * 60 + 15) {
      return 'pre';
    }
    if (minutes < 9 * 60 + 25) {
      return 'auction';
    }
    if (minutes < 9 * 60 + 30) {
      return 'pre';
    }
    if (minutes < 11 * 60 + 30) {
      return 'open';
    }
    if (minutes < 13 * 60) {
      return 'lunch';
    }
    if (minutes < 15 * 60) {
      return 'open';
    }
    return 'closed';
  }
}
