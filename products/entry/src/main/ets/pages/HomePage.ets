import { bundleManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ComingSoonText } from 'commons_basic';
import { AppColor, AppDim } from 'commons_ui';
import { AppServices } from '../di/AppServices';
import { PlaceholderPage } from '../shell/PlaceholderPage';
import { confirmRevokeConsent } from '../service/ConsentActions';

const DOMAIN: number = 0x0001;
const TAG: string = 'HomePage';

/**
 * 首页 Tab（占位，G1）：整页空态，只有标题与「首页下阶段开放」。
 * M13-1：底部加「隐私政策 / 撤回同意」与版本尾行——隐私政策必须**应用内可查**（AC-125），
 * 首页是唯一未承载业务、加一行不改变既有验收截图口径的落点（不新增底部 Tab）。
 */
@ComponentV2
export struct HomePage {
  @Local version: string = '';

  aboutToAppear(): void {
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.version = info.versionName;
    } catch (err) {
      this.version = '--';
      hilog.warn(DOMAIN, TAG, 'read_version_fail');
    }
  }

  @Builder
  footer() {
    Column() {
      Row() {
        Text($r('app.string.privacy_entry_policy'))
          .fontSize(12)
          .fontColor(AppColor.accent)
          .height(36)
          .padding({ right: AppDim.gap16 })
          .accessibilityGroup(true)
          .accessibilityText($r('app.string.privacy_entry_policy'))
          .onClick((): void => {
            AppServices.get().pushPrivacy();
          })

        Text($r('app.string.privacy_entry_revoke'))
          .fontSize(12)
          .fontColor(AppColor.textSecondary)
          .height(36)
          .accessibilityGroup(true)
          .accessibilityText($r('app.string.privacy_entry_revoke'))
          .onClick((): void => {
            confirmRevokeConsent(this.getUIContext(), 'home');
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Text($r('app.string.home_footer_version', this.version))
        .fontSize(11)
        .fontColor(AppColor.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: AppDim.gap2 })
    }
    .width('100%')
    .padding({ bottom: AppDim.gap8 })
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      PlaceholderPage({
        pageTitle: $r('app.string.placeholder_home_title'),
        pageDesc: ComingSoonText.HOME
      })
        .layoutWeight(1)

      this.footer()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bgPage)
  }
}
