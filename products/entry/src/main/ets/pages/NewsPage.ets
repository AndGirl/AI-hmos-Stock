import { ComingSoonText } from 'commons_basic';
import { PlaceholderPage } from '../shell/PlaceholderPage';

/** 最新资讯 Tab（占位，G1）。 */
@ComponentV2
export struct NewsPage {
  build() {
    PlaceholderPage({
      pageTitle: $r('app.string.placeholder_news_title'),
      pageDesc: ComingSoonText.NEWS
    })
  }
}
