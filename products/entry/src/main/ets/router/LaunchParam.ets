import { DeepLinkResult } from './DeepLinkParser';

/**
 * 冷启动深链暂存位（设计 §3.2：onCreate 解析 → 写入 LaunchParam）。
 * UI 就绪后由 DeepLinkHandler.markReady() 取走并只消费一次。
 */
export class LaunchParam {
  private static pending: DeepLinkResult | undefined = undefined;

  static set(result: DeepLinkResult): void {
    LaunchParam.pending = result;
  }

  static take(): DeepLinkResult | undefined {
    const result: DeepLinkResult | undefined = LaunchParam.pending;
    LaunchParam.pending = undefined;
    return result;
  }
}
