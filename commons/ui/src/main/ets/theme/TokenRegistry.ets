/**
 * 主题 token 唯一入口。
 * 约定：组件内不出现颜色字面量，颜色一律取 AppColor；尺寸优先取 AppDim。
 * 颜色/尺寸的定义在 commons/ui 的 resources/base/element/*.json，深色模式只需追加 dark 限定词目录。
 */
export class AppColor {
  static readonly bgPage: Resource = $r('app.color.color_bg_page');
  static readonly bgSurface: Resource = $r('app.color.color_bg_surface');
  static readonly textPrimary: Resource = $r('app.color.color_text_primary');
  static readonly textSecondary: Resource = $r('app.color.color_text_secondary');
  static readonly textOnAccent: Resource = $r('app.color.color_text_on_accent');
  static readonly priceUp: Resource = $r('app.color.color_price_up');
  static readonly priceDown: Resource = $r('app.color.color_price_down');
  static readonly priceFlat: Resource = $r('app.color.color_price_flat');
  static readonly accent: Resource = $r('app.color.color_accent');
  static readonly divider: Resource = $r('app.color.color_divider');
  static readonly tagFin: Resource = $r('app.color.color_tag_fin');
  static readonly tagStar: Resource = $r('app.color.color_tag_star');
  static readonly disabledBg: Resource = $r('app.color.color_disabled_bg');
  static readonly disabledText: Resource = $r('app.color.color_disabled_text');
  static readonly bannerBg: Resource = $r('app.color.color_banner_bg');
  static readonly chartLine: Resource = $r('app.color.color_chart_line');
  static readonly chartAvg: Resource = $r('app.color.color_chart_avg');
  static readonly barShadow: Resource = $r('app.color.color_bar_shadow');
  static readonly newsBandBg: Resource = $r('app.color.color_news_band_bg');
  static readonly orderBookTitleBg: Resource = $r('app.color.color_orderbook_title_bg');
  static readonly orderBookTitleText: Resource = $r('app.color.color_orderbook_title_text');
  static readonly transparent: Resource = $r('app.color.color_transparent');
}

export class AppDim {
  static readonly rowHeightBase: Resource = $r('app.float.row_height_base');
  static readonly headerHeightBase: Resource = $r('app.float.header_height_base');
  static readonly touchMin: Resource = $r('app.float.touch_min');
  static readonly pillRadius: Resource = $r('app.float.pill_radius');
  static readonly fadeWidth: Resource = $r('app.float.fade_width');
  static readonly gap2: Resource = $r('app.float.gap_2');
  static readonly gap4: Resource = $r('app.float.gap_4');
  static readonly gap8: Resource = $r('app.float.gap_8');
  static readonly gap12: Resource = $r('app.float.gap_12');
  static readonly gap16: Resource = $r('app.float.gap_16');
  static readonly gap24: Resource = $r('app.float.gap_24');
  static readonly tabBarRadius: Resource = $r('app.float.tab_bar_radius');
  static readonly opacityOffline: Resource = $r('app.float.opacity_offline');
}
