import { QuoteProvider } from './model/QuoteModels';
import { MockQuoteProvider } from './provider/MockQuoteProvider';
import { MockWatchlistProvider, WatchlistProvider } from './provider/WatchlistProvider';
import { QuoteBus } from './bus/QuoteBus';

/**
 * 数据装配点：全工程唯一允许 `new Mock*` / `new Real*` 的地方（R-05）。
 * 唯一一处 provider ↔ bus 的接线也在本文件，上层只拿接口。
 */
export class DataServices {
  private static quote: QuoteProvider | undefined = undefined;
  private static watch: WatchlistProvider | undefined = undefined;
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

  static quoteBus(): QuoteBus {
    if (DataServices.bus === undefined) {
      DataServices.bus = new QuoteBus(DataServices.quoteProvider());
    }
    return DataServices.bus;
  }
}
