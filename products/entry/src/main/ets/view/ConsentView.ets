import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { ComplianceHost, ComplianceService, SafeAreaHost, SafeAreaService } from 'commons_basic';
import { DataServices } from 'commons_data';
import { AppColor, AppDim, PrivacyDoc } from 'commons_ui';
import { AppServices } from '../di/AppServices';

const DOMAIN: number = 0x0001;
const TAG: string = 'Consent';

/**
 * 首启隐私同意（M13-1 / AC-125）：全屏一级面，未同意时**不渲染 TabShell**。
 *
 * 口径（本轮确认）：
 * - 同意：立即写盘 `privacy_consent_v1`，内存状态回灌 `ComplianceService`，本页自动卸载；
 * - 不同意：二次确认后**退出应用**（本应用无联网/无采集，不存在可保留的「受限模式」）；
 * - 查看政策：页内切换（不依赖路由，避免未同意时 Navigation 挂载）；
 * - 拒绝后仍可在下次启动重新看到本页（不写任何「已拒绝」状态）。
 */
@ComponentV2
export struct ConsentView {
  @Local service: ComplianceService = ComplianceHost.getService();
  /** 本页在 Navigation 之外，需自己做安全区避让（全屏布局下 Index 的 padding 不覆盖这层）。 */
  @Local safeArea: SafeAreaService = SafeAreaHost.getService();
  @Local showPolicy: boolean = false;
  @Local agreeing: boolean = false;
  aboutToAppear(): void {
    // 评审修复：同意门禁卸载 Navigation 时清掉残留路由，
    // 否则「撤回 → 重新同意」会回放旧页面（例如停在隐私政策页而不是四 Tab）。
    AppServices.get().backToTabs();
  }

  /** 同意：写盘（同步回灌 UI 状态，`Index` 据此切到 TabShell）。 */
  private agree(): void {
    if (this.agreeing) {
      return;
    }
    this.agreeing = true;
    DataServices.privacyConsent().agree().then((): void => {
      this.agreeing = false;
      hilog.info(DOMAIN, TAG, 'consent_page_agree');
    }).catch((err: BusinessError): void => {
      this.agreeing = false;
      hilog.warn(DOMAIN, TAG, 'consent_page_agree_fail %{public}s', JSON.stringify(err));
    });
  }

  /** 不同意：二次确认后退出（AC-125「拒绝可退出」）。 */
  private reject(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: $r('app.string.consent_reject_confirm_title'),
      message: $r('app.string.consent_reject_confirm_msg'),
      buttons: [
        { text: $r('app.string.consent_reject_cancel'), color: AppColor.textSecondary },
        { text: $r('app.string.consent_reject_exit'), color: AppColor.accent }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index !== 1) {
        return;
      }
      hilog.info(DOMAIN, TAG, 'consent_page_reject_exit');
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      context.terminateSelf().catch((err: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'terminate_fail %{public}s', JSON.stringify(err));
      });
    }).catch((): void => {
    });
  }

  @Builder
  primaryButton() {
    Text($r('app.string.consent_agree'))
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppColor.textOnAccent)
      .textAlign(TextAlign.Center)
      .width('100%')
      .height(48)
      .borderRadius(24)
      .backgroundColor(AppColor.accentFill)
      .opacity(this.agreeing ? 0.6 : 1)
      .accessibilityGroup(true)
      .accessibilityText($r('app.string.consent_agree'))
      .enabled(!this.agreeing)
      .onClick((): void => {
        this.agree();
      })
  }

  @Builder
  secondaryButton() {
    Text($r('app.string.consent_reject'))
      .fontSize(14)
      .fontColor(AppColor.textSecondary)
      .textAlign(TextAlign.Center)
      .width('100%')
      .height(44)
      .accessibilityGroup(true)
      .accessibilityText($r('app.string.consent_reject'))
      .onClick((): void => {
        this.reject();
      })
  }

  /** 首启主面：图标 + 标题 + 说明 + 政策链接 + 同意/不同意。 */
  @Builder
  consentBody() {
    Column() {
      Image($r('app.media.startIcon'))
        .width(72)
        .height(72)
        .borderRadius(18)
        .margin({ bottom: AppDim.gap24 })

      Text($r('app.string.privacy_consent_title'))
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textPrimary)
        .textAlign(TextAlign.Center)
        .width('100%')

      Text($r('app.string.privacy_consent_intro'))
        .fontSize(13)
        .fontColor(AppColor.textSecondary)
        .lineHeight(21)
        .textAlign(TextAlign.Center)
        .margin({ top: AppDim.gap12 })
        .width('100%')

      Text($r('app.string.consent_policy_link'))
        .fontSize(13)
        .fontColor(AppColor.accent)
        .textAlign(TextAlign.Center)
        .height(40)
        .margin({ top: AppDim.gap8 })
        .accessibilityGroup(true)
        .accessibilityText($r('app.string.consent_policy_link'))
        .onClick((): void => {
          this.showPolicy = true;
        })
    }
    .width('100%')
    .constraintSize({ maxWidth: 420 })
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)

    Column() {
      this.primaryButton()
      this.secondaryButton()
    }
    .width('100%')
    .constraintSize({ maxWidth: 420 })
  }

  /** 页内隐私政策（不依赖 Navigation 路由）。 */
  @Builder
  policyBody() {
    Row() {
      Text($r('app.string.common_back'))
        .fontSize(14)
        .fontColor(AppColor.accent)
        .height(44)
        .padding({ right: AppDim.gap12 })
        .onClick((): void => {
          this.showPolicy = false;
        })
      Text($r('app.string.privacy_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .height(44)
    .alignItems(VerticalAlign.Center)

    Scroll() {
      Column() {
        PrivacyDoc()
      }
      .width('100%')
      .padding({ top: AppDim.gap8, bottom: AppDim.gap16 })
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Auto)

    Column() {
      this.primaryButton()
      this.secondaryButton()
    }
    .width('100%')
  }

  build() {
    Column() {
      if (this.showPolicy) {
        this.policyBody()
      } else {
        this.consentBody()
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      left: 24 + this.safeArea.leftInset,
      right: 24 + this.safeArea.rightInset,
      top: this.safeArea.topInset + 16,
      bottom: this.safeArea.bottomInset + 16
    })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(AppColor.bgPage)
  }
}
