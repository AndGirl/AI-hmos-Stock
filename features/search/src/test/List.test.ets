import searchRulesTest from './SearchRules.test';
import searchQueryTest from './SearchQuery.test';
import addRulesTest from './WatchlistRules.test';
import watchlistStoreTest from './WatchlistStore.test';

export default function testsuite(): void {
  searchRulesTest();
  searchQueryTest();
  addRulesTest();
  watchlistStoreTest();
}
