import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppServices } from '../di/AppServices';
import { DeepLinkParser, DeepLinkResult, DeepLinkStatus } from './DeepLinkParser';
import { LaunchParam } from './LaunchParam';

const DOMAIN = 0x0000;

/**
 * 深链分发：
 * - 冷启动（UI 未就绪）：解析结果写入 LaunchParam，等 Navigation.onAppear 后 flush；
 * - 热启动（onNewWant）：UI 已就绪，直接 push。
 * 缺参 / 非法 code → notFound，并记录 deeplink_invalid（M5 接 Analytics，当前用 hilog 占位）。
 */
export class DeepLinkHandler {
  private static uiReady: boolean = false;

  static handle(uri: string | undefined): void {
    if (uri === undefined || uri.length === 0) {
      return;
    }
    const result: DeepLinkResult = DeepLinkParser.parse(uri);
    if (!DeepLinkHandler.uiReady) {
      LaunchParam.set(result);
      return;
    }
    DeepLinkHandler.apply(result);
  }

  static markReady(): void {
    DeepLinkHandler.uiReady = true;
    // 让 Navigation 完成首帧挂载后再消费冷启动深链。
    setTimeout(() => {
      const pending: DeepLinkResult | undefined = LaunchParam.take();
      if (pending !== undefined) {
        DeepLinkHandler.apply(pending);
      }
    }, 0);
  }

  private static apply(result: DeepLinkResult): void {
    if (result.status === DeepLinkStatus.OK && result.search !== undefined) {
      hilog.info(DOMAIN, 'DeepLink',
        'event=deeplink_search q_len=%{public}d from=%{public}s',
        result.search.q !== undefined ? result.search.q.length : 0,
        result.search.from !== undefined ? result.search.from : 'deeplink');
      AppServices.get().pushSearch(result.search.q, 'deeplink');
      return;
    }
    if (result.status === DeepLinkStatus.OK && result.detail !== undefined) {
      const rank: number = result.detail.rank !== undefined ? result.detail.rank : -1;
      hilog.info(DOMAIN, 'DeepLink',
        'event=deeplink_open code=%{public}s from=%{public}s rank=%{public}d',
        result.detail.code, result.detail.from, rank);
      AppServices.get().pushDetail(result.detail.code, result.detail.from, result.detail.rank);
      return;
    }

    const code: string = result.code !== undefined ? result.code : '';
    hilog.warn(DOMAIN, 'DeepLink',
      'event=deeplink_invalid reason=%{public}s host=%{public}s code=%{public}s',
      result.reason, result.host, code);
    AppServices.get().pushNotFound(result.code);
  }
}
