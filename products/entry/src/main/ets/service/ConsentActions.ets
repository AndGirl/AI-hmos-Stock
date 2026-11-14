import { promptAction, UIContext } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DataServices } from 'commons_data';
import { AppColor } from 'commons_ui';

const DOMAIN: number = 0x0001;
const TAG: string = 'Consent';

/**
 * 撤回同意（M13-1 / AC-125）：二次确认 → 删除 `privacy_consent_v1` → 回到首启同意页。
 *
 * 首页与隐私政策页共用同一实现（评审修复：原先两处各自维护一份，容易改一处漏一处）。
 * 只删同意记录，**不删**自选/持仓/委托等业务数据；撤回后 `ComplianceService.consented`
 * 翻转，`Index` 卸载 Navigation 并由同意页接管。
 *
 * @param ui 调用方 UIContext（组件内传 `this.getUIContext()`）
 * @param source 入口标记（`home` / `privacy`），只进日志便于取证
 */
export function confirmRevokeConsent(ui: UIContext, source: string): void {
  ui.getPromptAction().showDialog({
    title: $r('app.string.privacy_revoke_confirm_title'),
    message: $r('app.string.privacy_revoke_confirm_msg'),
    buttons: [
      { text: $r('app.string.privacy_revoke_cancel'), color: AppColor.textSecondary },
      { text: $r('app.string.privacy_revoke_ok'), color: AppColor.accent }
    ]
  }).then((result: promptAction.ShowDialogSuccessResponse): void => {
    if (result.index !== 1) {
      return;
    }
    DataServices.privacyConsent().revoke().then((): void => {
      hilog.info(DOMAIN, TAG, 'consent_revoke source=%{public}s', source);
    }).catch((err: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'consent_revoke_fail %{public}s', JSON.stringify(err));
    });
  }).catch((): void => {
  });
}
