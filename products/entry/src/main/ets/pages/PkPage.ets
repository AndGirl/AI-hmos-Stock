import { AppColor } from 'commons_ui';
import { SafeAreaHost, SafeAreaService } from 'commons_basic';
import { PkEntrySource, PkHost } from 'pk';
import { PkParam } from '../router/AppRoutes';
import { AppServices } from '../di/AppServices';

/**
 * 多窗比价壳（M0 建壳 / M4 接 PkHost）：路由、返回、沉浸式归壳层，
 * 窗编排、订阅、换股、同步与持久化全部在 features/pk（INV-W5）。
 */
@ComponentV2
export struct PkPage {
  @Local pkCodes: string[] = [];
  @Local focusIndex: number = 0;
  @Local source: PkEntrySource = 'detail';
  @Local safeArea: SafeAreaService = SafeAreaHost.getService();

  build() {
    NavDestination() {
      PkHost({
        codes: this.pkCodes,
        focus: this.focusIndex,
        source: this.source,
        bottomInset: this.safeArea.bottomInset,
        onExit: (): void => {
          AppServices.get().pop();
        },
        onOpenAddWatchlist: (code: string): void => {
          AppServices.get().pushAddWatchlist(code, '', 'detail');
        }
      })
    }
    .title($r('app.string.route_pk_title'))
    .backgroundColor(AppColor.bgPage)
    .onReady((context: NavDestinationContext) => {
      if (context.pathInfo.param !== undefined) {
        const param: PkParam = context.pathInfo.param as PkParam;
        this.pkCodes = param.codes !== undefined ? param.codes : [];
        this.focusIndex = param.focus !== undefined ? param.focus : 0;
        this.source = toSource(param.from);
      }
    })
  }
}

function toSource(from: string | undefined): PkEntrySource {
  if (from === 'icon') {
    return 'icon';
  }
  if (from === 'watchlist') {
    return 'watchlist';
  }
  return 'detail';
}
