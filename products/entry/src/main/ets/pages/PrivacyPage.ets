import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { ComplianceHost, ComplianceService, SafeAreaHost, SafeAreaService } from 'commons_basic';
import { DataServices } from 'commons_data';
import { AppColor, AppDim, PrivacyDoc } from 'commons_ui';
import { AppServices } from '../di/AppServices';

const DOMAIN: number = 0x0001;
const TAG: string = 'PrivacyPage';

/** `2026-11-14 14:20`（本地时间，仅用于展示同意时间）。 */
function formatAgreedAt(at: number): string {
  if (at <= 0) {
    return '--';
  }
  const d: Date = new Date(at);
  const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
    `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/**
 * 隐私政策页（M13-1 / AC-125「隐私政策可查」「可撤回同意」）。
 *
 * 入口：首页 Tab 底部「隐私政策」（同意后常驻；首页仍是占位页，不新增底部 Tab）。
 * 撤回同意后回到首启同意页（`ComplianceService.consented` 翻转，`Index` 卸载 Navigation）。
 */
@ComponentV2
export struct PrivacyPage {
  @Local service: ComplianceService = ComplianceHost.getService();
  /** 路由页在 Navigation 内，但 Navigation 未做底部避让（Tab 壳自己吃底栏），这里补上。 */
  @Local safeArea: SafeAreaService = SafeAreaHost.getService();

  private revoke(): void {
    this.getUIContext().getPromptAction().showDialog({
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
        hilog.info(DOMAIN, TAG, 'revoke_done');
      }).catch((err: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'revoke_fail %{public}s', JSON.stringify(err));
      });
    }).catch((): void => {
    });
  }

  @Builder
  footer() {
    Column() {
      Row() {
        Text(this.service.consented
          ? $r('app.string.privacy_state_agreed', formatAgreedAt(this.service.agreedAt))
          : $r('app.string.privacy_state_pending'))
          .fontSize(12)
          .fontColor(AppColor.textSecondary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.service.consented) {
          Text($r('app.string.privacy_revoke'))
            .fontSize(13)
            .fontColor(AppColor.accent)
            .height(44)
            .padding({ left: AppDim.gap12 })
            .accessibilityGroup(true)
            .accessibilityText($r('app.string.privacy_revoke'))
            .onClick((): void => {
              this.revoke();
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 20, right: 20, bottom: this.safeArea.bottomInset })
      .border({ width: { top: 0.5 }, color: AppColor.divider })
    }
    .width('100%')
  }

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column() {
            PrivacyDoc()
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: AppDim.gap12, bottom: AppDim.gap16 })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Auto)

        this.footer()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColor.bgPage)
    }
    .title($r('app.string.privacy_title'))
    .backgroundColor(AppColor.bgPage)
    .onBackPressed((): boolean => {
      AppServices.get().pop();
      return true;
    })
  }
}
