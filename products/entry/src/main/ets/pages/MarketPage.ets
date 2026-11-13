import { SearchPage } from 'search';
import { AppServices } from '../di/AppServices';

/**
 * 行情 Tab（M6-6 / CK-4）：占位页改为搜索页内嵌（mode='tab'）。
 * 路由与开窗仍由壳层装配：本页只转发回调（INV-D1）。
 */
@ComponentV2
export struct MarketPage {
  @Param onOpenTrade: (code: string) => void = (code: string): void => {
  };

  build() {
    SearchPage({
      mode: 'tab',
      onOpenDetail: (code: string, rank: number): void => {
        AppServices.get().pushDetail(code, 'search', rank);
      },
      onOpenTrade: (code: string): void => {
        this.onOpenTrade(code);
      },
      onOpenAddWatchlist: (code: string): void => {
        // M7-7：右栏「自选设置」→ 添加页（带 code 预置）。
        AppServices.get().pushAddWatchlist(code, '', 'search');
      },
      onOpenPk: (codes: string[]): void => {
        AppServices.get().pushPk(codes, 0, 'search');
      }
    })
  }
}
