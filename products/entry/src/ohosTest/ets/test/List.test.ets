import searchUiTest from './Search.ui.test';
import addWatchlistUiTest from './AddWatchlist.ui.test';
import cardViewUiTest from './CardView.ui.test';
import m12UiTest from './M12.ui.test';
import positionsUiTest from './Positions.ui.test';

export default function testsuite(): void {
  // M12 放在最前：详情页入口依赖干净的自选页状态（编辑/浮层残留会让行点击变成勾选）。
  m12UiTest();
  searchUiTest();
  addWatchlistUiTest();
  cardViewUiTest();
  // M11 持仓放在最后：需要从自选页干净态进入委托/持仓，且本身会切到详情页再返回。
  positionsUiTest();
}
