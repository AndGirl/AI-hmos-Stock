import { ComingSoonText } from 'commons_basic';
import { PlaceholderPage } from '../shell/PlaceholderPage';

/** 行情 Tab（占位，G1）。 */
@ComponentV2
export struct MarketPage {
  build() {
    PlaceholderPage({
      pageTitle: $r('app.string.placeholder_market_title'),
      pageDesc: ComingSoonText.MARKET
    })
  }
}
