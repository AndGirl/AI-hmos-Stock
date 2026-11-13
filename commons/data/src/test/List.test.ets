import authClientTest from './AuthClient.test';
import contractTest from './ContractTest.test';
import frameValidatorTest from './FrameValidator.test';
import limitRulesTest from './LimitRules.test';
import quoteCacheRulesTest from './QuoteCacheRules.test';
import quoteChannelTest from './QuoteChannel.test';
import quoteMergeRulesTest from './QuoteMergeRules.test';
import rateLimitRulesTest from './RateLimitRules.test';
import seededRandomTest from './SeededRandom.test';
import tradingSessionTest from './TradingSession.test';

/**
 * M9 真实行情 → 模拟行情通道 单测入口（Hypium Local Test）。
 * 运行：`hvigor test -p module=commons_data -p coverage=false`
 */
export default function testsuite(): void {
  limitRulesTest();
  quoteMergeRulesTest();
  frameValidatorTest();
  rateLimitRulesTest();
  quoteCacheRulesTest();
  contractTest();
  authClientTest();
  quoteChannelTest();
  tradingSessionTest();
  seededRandomTest();
}
