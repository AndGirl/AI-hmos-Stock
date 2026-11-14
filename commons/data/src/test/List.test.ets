import authClientTest from './AuthClient.test';
import complianceStoreTest from './ComplianceStore.test';
import contractTest from './ContractTest.test';
import frameValidatorTest from './FrameValidator.test';
import limitRulesTest from './LimitRules.test';
import localPositionProviderTest from './LocalPositionProvider.test';
import localTradeProviderTest from './LocalTradeProvider.test';
import matchingRulesTest from './MatchingRules.test';
import orderJournalStoreTest from './OrderJournalStore.test';
import positionRulesTest from './PositionRules.test';
import quoteCacheRulesTest from './QuoteCacheRules.test';
import quoteChannelTest from './QuoteChannel.test';
import quoteMergeRulesTest from './QuoteMergeRules.test';
import rateLimitRulesTest from './RateLimitRules.test';
import seededRandomTest from './SeededRandom.test';
import tradeStoresTest from './TradeStores.test';
import tradingSessionTest from './TradingSession.test';

/**
 * M9 行情通道 + M10 模拟交易 + M11 持仓 单测入口（Hypium Local Test）。
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
  matchingRulesTest();
  orderJournalStoreTest();
  tradeStoresTest();
  localTradeProviderTest();
  positionRulesTest();
  localPositionProviderTest();
  complianceStoreTest();
}
