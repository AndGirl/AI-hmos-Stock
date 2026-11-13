import searchUiTest from './Search.ui.test';
import addWatchlistUiTest from './AddWatchlist.ui.test';
import cardViewUiTest from './CardView.ui.test';

export default function testsuite(): void {
  searchUiTest();
  addWatchlistUiTest();
  cardViewUiTest();
}
