import cardMetricsTest from './CardMetrics.test';
import quoteMarkTest from './QuoteMark.test';
import detailLayoutTest from './DetailLayout.test';

export default function testsuite(): void {
  cardMetricsTest();
  quoteMarkTest();
  detailLayoutTest();
}
