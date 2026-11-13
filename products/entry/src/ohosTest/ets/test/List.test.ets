import searchUiTest from './Search.ui.test';
import addWatchlistUiTest from './AddWatchlist.ui.test';
import cardViewUiTest from './CardView.ui.test';
import m12UiTest from './M12.ui.test';

export default function testsuite(): void {
  searchUiTest();
  addWatchlistUiTest();
  cardViewUiTest();
  m12UiTest();
}
