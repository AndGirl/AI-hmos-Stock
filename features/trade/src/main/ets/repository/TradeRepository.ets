import { DataServices, OrderDraft, OrderResult, TradeContext, TradeProvider, TradeSource } from
  'commons_data';

/**
 * 交易仓储（L2）：provider 组合与参数透传，不产出中文文案。
 * 幂等键、超时计时、状态机在 TradeVM（FR-07.8）。
 */
export class TradeRepository {
  private provider(): TradeProvider {
    return DataServices.tradeProvider();
  }

  loadContext(code: string, source: TradeSource): Promise<TradeContext> {
    return this.provider().loadContext(code, source);
  }

  login(): Promise<void> {
    return this.provider().login();
  }

  submit(draft: OrderDraft): Promise<OrderResult> {
    return this.provider().submit(draft);
  }

  query(clientOrderId: string): Promise<OrderResult> {
    return this.provider().query(clientOrderId);
  }
}
