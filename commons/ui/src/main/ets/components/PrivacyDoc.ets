import { PRIVACY_POLICY_DATE, PRIVACY_POLICY_VERSION } from 'commons_basic';
import { AppColor, AppDim } from '../theme/TokenRegistry';

/**
 * 隐私政策正文（M13-1）：首启同意页内嵌 + 隐私政策页共用同一份渲染。
 * 文案全部走资源（`app.string.privacy_*`），组件内零中文、零颜色字面量（D-03）。
 * 章节数由 `PRIVACY_SECTION_COUNT` 约定（当前 8 节，逐节显式列出，ArkTS 的 `$r` 不支持拼接键名）。
 */
@ComponentV2
export struct PrivacyDoc {
  /** 是否显示版本/更新日期与在线地址（首启内嵌也显示，保证「可查」）。 */
  @Param showMeta: boolean = true;

  @Builder
  section(title: Resource, body: Resource) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textPrimary)
        .width('100%')
      Text(body)
        .fontSize(13)
        .fontColor(AppColor.textSecondary)
        .lineHeight(20)
        .margin({ top: AppDim.gap4 })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: AppDim.gap16 })
  }

  @Builder
  meta() {
    Column() {
      Text($r('app.string.privacy_version', PRIVACY_POLICY_VERSION, PRIVACY_POLICY_DATE))
        .fontSize(12)
        .fontColor(AppColor.textSecondary)
        .width('100%')
      Row() {
        Text($r('app.string.privacy_url_label'))
          .fontSize(12)
          .fontColor(AppColor.textSecondary)
        Text($r('app.string.privacy_url_value'))
          .fontSize(12)
          .fontColor(AppColor.textSecondary)
          .margin({ left: AppDim.gap4 })
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: AppDim.gap4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ bottom: AppDim.gap16 })
  }

  build() {
    Column() {
      if (this.showMeta) {
        this.meta()
      }
      this.section($r('app.string.privacy_section_1_title'), $r('app.string.privacy_section_1_body'))
      this.section($r('app.string.privacy_section_2_title'), $r('app.string.privacy_section_2_body'))
      this.section($r('app.string.privacy_section_3_title'), $r('app.string.privacy_section_3_body'))
      this.section($r('app.string.privacy_section_4_title'), $r('app.string.privacy_section_4_body'))
      this.section($r('app.string.privacy_section_5_title'), $r('app.string.privacy_section_5_body'))
      this.section($r('app.string.privacy_section_6_title'), $r('app.string.privacy_section_6_body'))
      this.section($r('app.string.privacy_section_7_title'), $r('app.string.privacy_section_7_body'))
      this.section($r('app.string.privacy_section_8_title'), $r('app.string.privacy_section_8_body'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
