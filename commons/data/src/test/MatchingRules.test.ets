import { describe, expect, it } from '@ohos/hypium';
import {
  AccountDelta,
  applyFill,
  canCancel,
  CancelDecision,
  MATCH_LOT,
  MatchAccount,
  MatchOrder,
  MatchOutcome,
  matchOnce,
  MatchQuote,
  precheck
} from '../main/ets/rules/MatchingRules';
import { isCancelable } from '../main/ets/model/TradeModels';

/** 行情：最新价 10，涨跌停 11 / 9。 */
function quote(last: number | null): MatchQuote {
  return new MatchQuote('open', last, 11, 9);
}

/** 账户：已登录、已开户、可用 10000、可卖 1000。 */
function account(available: number, sellable: number): MatchAccount {
  return new MatchAccount(true, true, available, sellable);
}

/**
 * M10-2 / AC-113~116 撮合规则单测：
 * 成交/部成/挂单/拒单、可撤判定、成交对资金与持仓的影响。
 */
export default function matchingRulesTest(): void {
  describe('MatchingRules', () => {
    it('buy_cross_fills_single_lot', 0, () => {
      const order: MatchOrder = new MatchOrder('600519', 'buy', 10.5, MATCH_LOT, 0);
      const outcome: MatchOutcome = matchOnce(order, quote(10), account(10000, 0));
      expect(outcome.decision).assertEqual('fill');
      expect(outcome.state).assertEqual('filled');
      expect(outcome.fillQty).assertEqual(MATCH_LOT);
      expect(outcome.reasonCode).assertEqual('');
    });

    it('buy_first_fill_halves_then_fills_rest', 0, () => {
      const first: MatchOrder = new MatchOrder('600519', 'buy', 10.5, 1000, 0);
      const half: MatchOutcome = matchOnce(first, quote(10), account(20000, 0));
      expect(half.decision).assertEqual('partial');
      expect(half.state).assertEqual('partial');
      expect(half.fillQty).assertEqual(500);

      const second: MatchOrder = new MatchOrder('600519', 'buy', 10.5, 1000, 500);
      const rest: MatchOutcome = matchOnce(second, quote(10), account(20000, 0));
      expect(rest.decision).assertEqual('fill');
      expect(rest.fillQty).assertEqual(500);
    });

    it('buy_not_crossed_stays_pending', 0, () => {
      const order: MatchOrder = new MatchOrder('600519', 'buy', 9.8, 1000, 0);
      const outcome: MatchOutcome = matchOnce(order, quote(10), account(20000, 0));
      expect(outcome.decision).assertEqual('pending');
      expect(outcome.state).assertEqual('pending');
      expect(outcome.fillQty).assertEqual(0);
    });

    it('sell_cross_fills_and_halves_first', 0, () => {
      const order: MatchOrder = new MatchOrder('600519', 'sell', 9.5, 400, 0);
      const outcome: MatchOutcome = matchOnce(order, quote(10), account(0, 1000));
      expect(outcome.decision).assertEqual('partial');
      expect(outcome.fillQty).assertEqual(200);
    });

    it('sell_not_crossed_stays_pending', 0, () => {
      const order: MatchOrder = new MatchOrder('600519', 'sell', 10.5, 400, 0);
      const outcome: MatchOutcome = matchOnce(order, quote(10), account(0, 1000));
      expect(outcome.decision).assertEqual('pending');
    });

    it('reject_without_login_or_account', 0, () => {
      const order: MatchOrder = new MatchOrder('600519', 'buy', 10.5, 100, 0);
      expect(precheck(order, quote(10), new MatchAccount(false, true, 10000, 0))).assertEqual('no_permission');
      expect(precheck(order, quote(10), new MatchAccount(true, false, 10000, 0))).assertEqual('no_permission');
    });

    it('reject_suspended_delisted_closed', 0, () => {
      const order: MatchOrder = new MatchOrder('600519', 'buy', 10.5, 100, 0);
      expect(precheck(order, new MatchQuote('suspended', 10, 11, 9), account(10000, 0))).assertEqual('suspended');
      expect(precheck(order, new MatchQuote('delisted', 10, 11, 9), account(10000, 0))).assertEqual('delisted');
      expect(precheck(order, new MatchQuote('closed', 10, 11, 9), account(10000, 0))).assertEqual('closed');
      expect(precheck(order, new MatchQuote('lunch', 10, 11, 9), account(10000, 0))).assertEqual('closed');
    });

    it('reject_price_out_of_limit', 0, () => {
      const tooHigh: MatchOrder = new MatchOrder('600519', 'buy', 11.01, 100, 0);
      expect(precheck(tooHigh, quote(10), account(10000, 0))).assertEqual('price_limit');
      const tooLow: MatchOrder = new MatchOrder('600519', 'sell', 8.99, 100, 0);
      expect(precheck(tooLow, quote(10), account(0, 1000))).assertEqual('price_limit');
    });

    it('reject_fund_short_and_qty_short', 0, () => {
      const buy: MatchOrder = new MatchOrder('600519', 'buy', 10.5, 1000, 0);
      expect(precheck(buy, quote(10), account(1000, 0))).assertEqual('fund_short');
      const sell: MatchOrder = new MatchOrder('600519', 'sell', 9.5, 500, 0);
      expect(precheck(sell, quote(10), account(0, 100))).assertEqual('qty_short');
    });

    it('reject_odd_lot', 0, () => {
      const order: MatchOrder = new MatchOrder('600519', 'buy', 10.5, 150, 0);
      expect(precheck(order, quote(10), account(10000, 0))).assertEqual('risk');
    });

    it('pending_when_no_last_price', 0, () => {
      const order: MatchOrder = new MatchOrder('600519', 'buy', 10.5, 100, 0);
      const outcome: MatchOutcome = matchOnce(order, quote(null), account(10000, 0));
      expect(outcome.decision).assertEqual('pending');
    });

    it('buy_deducts_cash_sell_adds_cash', 0, () => {
      const buy: AccountDelta = applyFill('buy', 10.5, 200, new MatchAccount(true, true, 10000, 0));
      expect(buy.available).assertEqual(7900);
      expect(buy.sellable).assertEqual(200);
      const sell: AccountDelta = applyFill('sell', 10.5, 200, new MatchAccount(true, true, 7900, 500));
      expect(sell.available).assertEqual(10000);
      expect(sell.sellable).assertEqual(300);
    });

    it('cancel_rules', 0, () => {
      expect(canCancel('pending').ok).assertTrue();
      expect(canCancel('accepted').ok).assertTrue();
      expect(canCancel('partial').ok).assertTrue();
      const filled: CancelDecision = canCancel('filled');
      expect(filled.ok).assertFalse();
      expect(filled.reasonCode).assertEqual('filled');
      expect(canCancel('canceled').ok).assertFalse();
      expect(canCancel('rejected').ok).assertFalse();
    });

    it('state_helpers_consistent', 0, () => {
      expect(isCancelable('pending')).assertTrue();
      expect(isCancelable('partial')).assertTrue();
      expect(isCancelable('filled')).assertFalse();
      expect(isCancelable('unknown')).assertFalse();
    });
  });
}
