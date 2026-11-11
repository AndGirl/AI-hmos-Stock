import { UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LayoutConst } from 'commons_basic';

const DOMAIN = 0x0000;

/**
 * 占位入口的统一反馈：toast 1.8s，文案由调用方从 ComingSoonText 取。
 * 约束：文案必须是「{对象}下阶段开放」的完整字符串，不做运行时拼接（ADR-08）。
 */
export function showComingSoon(uiContext: UIContext, text: ResourceStr): void {
  try {
    uiContext.getPromptAction().showToast({
      message: text,
      duration: LayoutConst.TOAST_DURATION_MS
    });
  } catch (error) {
    // toast 失败不阻塞入口本身；占位入口仍保持可点。
    hilog.warn(DOMAIN, 'ComingSoon', 'showToast failed: %{public}s', JSON.stringify(error));
  }
}
