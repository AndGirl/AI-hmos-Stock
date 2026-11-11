import { QuoteProvider } from './model/QuoteModels';
import { DetailProvider } from './model/DetailModels';
import { MockQuoteProvider } from './provider/MockQuoteProvider';
import { MockDetailProvider } from './provider/MockDetailProvider';
import { MockWatchlistProvider, WatchlistProvider } from './provider/WatchlistProvider';
import { QuoteBus } from './bus/QuoteBus';

/**
 * 数据装配点：全工程唯一允许 `new Mock*` / `new Real*` 的地方（R-05）。
 * 唯一一处 provider ↔ bus 的接线也在本文件，上层只拿接口。
 */
export class DataServices {
  private static quote: QuoteProvider | undefined = undefined;
  private static watch: WatchlistProvider | undefined = undefined;
  private static detail: DetailProvider | undefined = undefined;
  private static bus: QuoteBus | undefined = undefined;

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

  static quoteBus(): QuoteBus {
    if (DataServices.bus === undefined) {
      DataServices.bus = new QuoteBus(DataServices.quoteProvider());
    }
    return DataServices.bus;
  }
}
