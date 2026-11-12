import { QuoteProvider, QuoteSnapshot, TradeStatus } from '../model/QuoteModels';
import {
  AccountInfo,
  OrderDraft,
  OrderResult,
  TradeContext,
  TradeError,
  TradeProvider,
  TradeSource,
  Tradable
} from '../model/TradeModels';
import { buildAccounts, buildNoAccounts, TradeAuth } from '../mock/TradeSeeds';
import { MockFaults } from '../mock/MockFaults';

const CONTEXT_LATENCY_MS: number = 80;
const SUBMIT_LATENCY_MS: number = 600;
const SUBMIT_TIMEOUT_LATENCY_MS: number = 2600;
const QUERY_LATENCY_MS: number = 200;
const LOGIN_LATENCY_MS: number = 300;
/** 主板 ±10%；创业板/科创板幅度差异本期不实装（DEC-07-03）。 */
const LIMIT_RATIO: number = 0.1;

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: (value: void) => void): void => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

/**
 * Mock 交易网关（与真实同形，DEC-07-01）。
 * - 账户与可用资金来自账户中心种子；可买由调用方按委托价推导（FR-07.5）。
 * - 幂等：同一 clientOrderId 只成功受理一次，重复提交返回同一委托号（INV-T1）。
 * - 超时不在这里判定：submit 只负责回执，2s 计时在 TradeVM（FR-07.8）。
 */
export class MockTradeProvider implements TradeProvider {
  private quotes: QuoteProvider;
  private accepted: Map<string, OrderResult> = new Map<string, OrderResult>();
  private inflight: Map<string, Promise<OrderResult>> = new Map<string, Promise<OrderResult>>();
  private orderSeq: number = 0;

  constructor(quotes: QuoteProvider) {
    this.quotes = quotes;
  }

  async loadContext(code: string, source: TradeSource): Promise<TradeContext> {
    await delay(CONTEXT_LATENCY_MS);
    const list: QuoteSnapshot[] = await this.quotes.getSnapshots([code]);
    if (list.length === 0) {
      throw new TradeError('not_found', 'unknown code ' + code);
    }
    const quote: QuoteSnapshot = list[0];
    const prevClose: number | null = quote.prevClose;
    const limitUp: number = prevClose === null ? 0 : round2(prevClose * (1 + LIMIT_RATIO));
    const limitDown: number = prevClose === null ? 0 : round2(prevClose * (1 - LIMIT_RATIO));
    // 故障注入的「非交易时段」只覆盖时间因素（不改标的停牌/退市状态）。
    const status: TradeStatus = MockFaults.tradeClosed ? 'closed' : quote.status;
    const tradable: Tradable = new Tradable(quote.code, quote.name, quote.market, status,
      quote.last, prevClose, limitUp, limitDown, quote.snapshotTime);
    const accounts: AccountInfo[] = this.accountsWithFaults();
    return new TradeContext(tradable, accounts, TradeAuth.loggedIn, !MockFaults.tradeOffline, source);
  }

  async login(): Promise<void> {
    await delay(LOGIN_LATENCY_MS);
    TradeAuth.loggedIn = true;
  }

  submit(draft: OrderDraft): Promise<OrderResult> {
    const existing: OrderResult | undefined = this.accepted.get(draft.clientOrderId);
    if (existing !== undefined) {
      return Promise.resolve(existing);
    }
    const running: Promise<OrderResult> | undefined = this.inflight.get(draft.clientOrderId);
    if (running !== undefined) {
      return running;
    }
    const task: Promise<OrderResult> = this.doSubmit(draft);
    this.inflight.set(draft.clientOrderId, task);
    return task;
  }

  async query(clientOrderId: string): Promise<OrderResult> {
    await delay(QUERY_LATENCY_MS);
    const existing: OrderResult | undefined = this.accepted.get(clientOrderId);
    if (existing !== undefined) {
      return existing;
    }
    return new OrderResult(clientOrderId, '', 'unknown', 'not_found', Date.now());
  }

  private async doSubmit(draft: OrderDraft): Promise<OrderResult> {
    const latency: number = MockFaults.tradeTimeout ? SUBMIT_TIMEOUT_LATENCY_MS : SUBMIT_LATENCY_MS;
    await delay(latency);
    this.inflight.delete(draft.clientOrderId);
    if (MockFaults.tradeReject) {
      return new OrderResult(draft.clientOrderId, '', 'rejected', 'risk', Date.now());
    }
    if (MockFaults.tradeClosed) {
      return new OrderResult(draft.clientOrderId, '', 'rejected', 'closed', Date.now());
    }
    this.orderSeq++;
    const orderId: string = 'D' + Date.now().toString() + this.orderSeq;
    const result: OrderResult = new OrderResult(draft.clientOrderId, orderId, 'accepted', 'accepted',
      Date.now());
    this.accepted.set(draft.clientOrderId, result);
    return result;
  }

  private accountsWithFaults(): AccountInfo[] {
    if (MockFaults.tradeNoAccount) {
      return buildNoAccounts();
    }
    const accounts: AccountInfo[] = buildAccounts();
    if (MockFaults.tradeFundShort) {
      for (let i = 0; i < accounts.length; i++) {
        accounts[i].available = 0;
      }
    }
    return accounts;
  }
}
