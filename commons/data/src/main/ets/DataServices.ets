import { QuoteProvider } from './model/QuoteModels';
import { DetailProvider } from './model/DetailModels';
import { MockQuoteProvider } from './provider/MockQuoteProvider';
import { MockDetailProvider } from './provider/MockDetailProvider';
import { MockWatchlistProvider, WatchlistProvider } from './provider/WatchlistProvider';
import { MockTradeProvider } from './provider/MockTradeProvider';
import { TradeProvider } from './model/TradeModels';
import { QuoteBus } from './bus/QuoteBus';
import { DetailSubscriptionRegistry } from './bus/DetailSubscriptionRegistry';

/**
 * 数据装配点：全工程唯一允许 `new Mock*` / `new Real*` 的地方（R-05）。
 * 唯一一处 provider ↔ bus 的接线也在本文件，上层只拿接口。
 */
export class DataServices {
  private static quote: QuoteProvider | undefined = undefined;
  private static watch: WatchlistProvider | undefined = undefined;
  private static detail: DetailProvider | undefined = undefined;
  private static trade: TradeProvider | undefined = undefined;
  private static bus: QuoteBus | undefined = undefined;
  private static detailSubsRegistry: DetailSubscriptionRegistry | undefined = undefined;

  static quoteProvider(): QuoteProvider {
    if (DataServices.quote === undefined) {
      DataServices.quote = new MockQuoteProvider();
    }
    return DataServices.quote;
  }

  static watchlistProvider(): WatchlistProvider {
    if (DataServices.watch === undefined) {
      DataServices.watch = new MockWatchlistProvider();
    }
    return DataServices.watch;
  }

  /** 详情源与自选同源行情：共用同一个 quote provider 实例。 */
  static detailProvider(): DetailProvider {
    if (DataServices.detail === undefined) {
      DataServices.detail = new MockDetailProvider(DataServices.quoteProvider());
    }
    return DataServices.detail;
  }

  /** 交易网关与账户上下文：与行情同源（打开弹窗时按 code 读一次快照）。 */
  static tradeProvider(): TradeProvider {
    if (DataServices.trade === undefined) {
      DataServices.trade = new MockTradeProvider(DataServices.quoteProvider());
    }
    return DataServices.trade;
  }

  static quoteBus(): QuoteBus {
    if (DataServices.bus === undefined) {
      DataServices.bus = new QuoteBus(DataServices.quoteProvider());
    }
    return DataServices.bus;
  }

  /** 详情订阅登记表（M4）：同 code 多窗合并一路 + 非焦点降频，上层不直接订阅 provider。 */
  static detailSubs(): DetailSubscriptionRegistry {
    if (DataServices.detailSubsRegistry === undefined) {
      DataServices.detailSubsRegistry = new DetailSubscriptionRegistry(DataServices.detailProvider());
    }
    return DataServices.detailSubsRegistry;
  }
}
