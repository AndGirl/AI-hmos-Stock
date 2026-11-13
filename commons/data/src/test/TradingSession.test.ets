import { describe, expect, it } from '@ohos/hypium';
import { SESSION_MODES, SessionMode, TradingSession } from '../main/ets/mock/TradingSession';
import { TradeStatus } from '../main/ets/model/QuoteModels';

/** 构造某日某时刻的本地时间（月份从 0 起）。 */
function at(day: number, hour: number, minute: number): Date {
  return new Date(2026, 0, day, hour, minute, 0);
}

/**
 * M9 交易时段驱动器单测：
 * 演示档恒定开盘、自动档按时间/周末推导、显式档直出、模式可切换。
 */
export default function tradingSessionTest(): void {
  describe('TradingSession', () => {
    it('demo_open_always_open', 0, () => {
      expect(TradingSession.statusOf('demo-open', at(5, 3, 0))).assertEqual('open');
      expect(TradingSession.statusOf('demo-open', at(5, 12, 0))).assertEqual('open');
      expect(TradingSession.statusOf('demo-open', at(10, 23, 0))).assertEqual('open');
    });

    it('auto_before_915_is_pre', 0, () => {
      // 2026-01-05 是周一
      expect(TradingSession.statusOf('auto', at(5, 9, 0))).assertEqual('pre');
      expect(TradingSession.statusOf('auto', at(5, 3, 0))).assertEqual('pre');
    });

    it('auto_auction_window', 0, () => {
      expect(TradingSession.statusOf('auto', at(5, 9, 15))).assertEqual('auction');
      expect(TradingSession.statusOf('auto', at(5, 9, 24))).assertEqual('auction');
      expect(TradingSession.statusOf('auto', at(5, 9, 25))).assertEqual('pre');
      expect(TradingSession.statusOf('auto', at(5, 9, 29))).assertEqual('pre');
    });

    it('auto_trading_windows', 0, () => {
      expect(TradingSession.statusOf('auto', at(5, 9, 30))).assertEqual('open');
      expect(TradingSession.statusOf('auto', at(5, 11, 29))).assertEqual('open');
      expect(TradingSession.statusOf('auto', at(5, 13, 0))).assertEqual('open');
      expect(TradingSession.statusOf('auto', at(5, 14, 59))).assertEqual('open');
    });

    it('auto_lunch_and_close', 0, () => {
      expect(TradingSession.statusOf('auto', at(5, 11, 30))).assertEqual('lunch');
      expect(TradingSession.statusOf('auto', at(5, 12, 59))).assertEqual('lunch');
      expect(TradingSession.statusOf('auto', at(5, 15, 0))).assertEqual('closed');
      expect(TradingSession.statusOf('auto', at(5, 23, 0))).assertEqual('closed');
    });

    it('auto_weekend_closed', 0, () => {
      // 2026-01-03 周六、01-04 周日
      expect(TradingSession.statusOf('auto', at(3, 10, 0))).assertEqual('closed');
      expect(TradingSession.statusOf('auto', at(4, 10, 0))).assertEqual('closed');
    });

    it('explicit_modes_are_passthrough', 0, () => {
      const modes: SessionMode[] = ['pre', 'auction', 'lunch', 'closed', 'all-suspended'];
      const expected: TradeStatus[] = ['pre', 'auction', 'lunch', 'closed', 'suspended'];
      for (let i = 0; i < modes.length; i++) {
        expect(TradingSession.statusOf(modes[i], at(5, 10, 0))).assertEqual(expected[i]);
      }
    });

    it('mode_can_be_switched', 0, () => {
      const original: SessionMode = TradingSession.current();
      TradingSession.setMode('closed');
      expect(TradingSession.current()).assertEqual('closed');
      expect(TradingSession.resolve(at(5, 10, 0))).assertEqual('closed');
      TradingSession.setMode(original);
      expect(TradingSession.current()).assertEqual(original);
    });

    it('mode_list_covers_all', 0, () => {
      expect(SESSION_MODES.length).assertEqual(7);
      expect(SESSION_MODES.indexOf('auto') >= 0).assertTrue();
      expect(SESSION_MODES.indexOf('demo-open') >= 0).assertTrue();
    });
  });
}
