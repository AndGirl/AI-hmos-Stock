# 阶段二 · 颜色 Token 清单（浅色 / 深色）

> 版本：v1.0（M12-2 / T0-4 部分） · 日期：2026-11-14
> 唯一事实来源：`commons/ui/src/main/resources/base/element/color.json`、`commons/ui/src/main/resources/dark/element/color.json`；
> 组件侧只允许通过 `commons/ui` 的 `AppColor` 取色，`.ets` 内不得出现颜色字面量。
> 门禁：[check-dark-tokens.mjs](../scripts/check-dark-tokens.mjs)（D-01~D-03）、[check-contrast.mjs](../scripts/check-contrast.mjs)（C-01~C-04）。

## 1. 口径

- 计划 §4.4-G7 给定 7 个深色基线：`bg_page #0F1115`、`bg_surface #1A1D23`、`text_primary #E8E8EA`、`text_secondary #9A9AA0`、`divider #2A2D33`、`price_up #FF5A4E`、`price_down #22C08A`；其余按同明度阶梯推导。
- 实际键数为 **30**（计划旧文写 26，已按现状更新）：base 的 29 个历史 token + 本次新增 `color_accent_fill`；另有 `products/entry` 的 `start_window_background` 深浅各 1 个。
- `color_accent` 用于文字/图标/边框/指示线；`color_accent_fill` 专用于「红底白字」实心按钮与勾选，保证白字对比度 ≥4.5:1（base/dark 同值 `#D92D24`）。
- 半透明色（`bar_shadow` / `scrim` / `transparent`）不参与对比度断言；`disabled_text` 属禁用态、`divider`/`divider_strong` 属装饰线，均按 WCAG 豁免。

## 2. 全量色值

| Token | 浅色 base | 深色 dark | 主要用途 | 深色对比度（对 `bg_page`） |
|---|---|---|---|---|
| `color_bg_page` | #FFFFFF | #0F1115 | 页面底、导航底、动作栏底 | — |
| `color_bg_surface` | #F7F8FA | #1A1D23 | 卡片、面板、表格分组底 | 1.12（表面层级） |
| `color_text_primary` | #1A1A1A | #E8E8EA | 主文本、名称、数值 | 15.44 |
| `color_text_secondary` | #8A8A8E | #9A9AA0 | 次要文本、标签、表头 | 6.75 |
| `color_text_on_accent` | #FFFFFF | #FFFFFF | 红底按钮/勾选上的白字 | 对 `accent_fill` 4.83 |
| `color_price_up` | #E8342A | #FF5A4E | 涨（红） | 6.14 |
| `color_price_down` | #00A870 | #22C08A | 跌（绿） | 8.08 |
| `color_price_flat` | #6B6B70 | #9A9AA0 | 平盘 | 6.75 |
| `color_accent` | #E8342A | #FF5A4E | 选中态文字/图标/边框、进度 | 6.14 |
| `color_accent_fill` | #D92D24 | #D92D24 | 红底白字按钮/勾选（新增） | 3.92（非文本）/白字 4.83 |
| `color_divider` | #EDEDED | #2A2D33 | 0.5vp 分隔线 | 1.37（装饰线豁免） |
| `color_divider_strong` | #DCDCDC | #3E434C | 底栏顶边等强分隔 | 1.90（装饰线豁免） |
| `color_tag_fin` | #7C4DFF | #A98BFF | 「融」标签 | 7.04 |
| `color_tag_star` | #FF7A00 | #FFA24D | 「创/科」标签 | 9.47 |
| `color_disabled_bg` | #F2F2F2 | #24272E | 禁用底、骨架 | 1.26 |
| `color_disabled_text` | #B0B0B5 | #6E6E76 | 禁用文字 | 3.74（禁用态豁免） |
| `color_banner_bg` | #FFF4E5 | #2A2418 | 弱网 banner 底 | 1.23 |
| `color_chart_line` | #E8342A | #FF5A4E | 分时线 | 6.14 |
| `color_chart_avg` | #F5A623 | #F5B84D | 均价线 | 10.66 |
| `color_bar_shadow` | #14000000 | #33FFFFFF | 阴影/抬升 | 半透明豁免 |
| `color_news_band_bg` | #F2F4F6 | #1F2229 | 资讯条底 | 1.19 |
| `color_orderbook_title_bg` | #FFF0EF | #2A1E1E | 盘口标题底 | 1.17 |
| `color_orderbook_title_text` | #E8645C | #FF8A80 | 盘口标题字 | 7.06（对标题底） |
| `color_transparent` | #00000000 | #00000000 | 透明 | 豁免 |
| `color_scrim` | #66000000 | #99000000 | 弹层遮罩 | 半透明豁免 |
| `color_error` | #E8342A | #FF6B5E | 错误/断线点 | 6.76 |
| `color_field_bg` | #F5F6F8 | #21242B | 输入框底 | 1.22 |
| `color_accent_soft` | #FFF0EF | #38221F | 选中行/多选底、离线 banner | 1.27（`accent` 在其上 4.82） |
| `color_recommend_card_bg` | #FFFAFA | #1C1F26 | 推荐卡底 | 1.15 |
| `color_debug` | #E84026 | #E84026 | 仅 debug 菜单按钮字 | 4.67（仅 debug） |
| `start_window_background`（entry） | #FFFFFF | #0F1115 | 启动窗口底（防白闪） | — |

## 3. 对比度预算

| 检查 | 阈值 | 结果 |
|---|---|---|
| 深色文本对（`check-contrast` C-01） | ≥4.5:1 | 全部通过（最低 `text_on_accent/accent_fill` 4.83） |
| 深色状态非文本对（C-02） | ≥3:1 | 全部通过（最低 `accent_fill/bg_page` 3.92） |
| 涨跌红绿可辨（C-03） | ΔE76 ≥20 且相对亮度差 ≥15% | base ΔE 121.3 / 32.2%；dark ΔE 116.5 / 27.0% |
| 浅色现状（C-04） | 只报告，不失败 | `text_secondary` 3.44、`price_up` 4.24、`price_down` 3.07、`tag_star` 2.61、`chart_avg` 2.03 等为阶段一既有基线；如需收紧设 `STRICT_LIGHT=1` 并同步重截阶段一证据 |

> 结论：AC-123「文本 ≥4.5:1、非文本 ≥3:1」按**深色**口径在本期达成；浅色阶段一基线未改（避免全量视觉回归）。红绿之外还有 `▲/▼`（`commons/basic/constants/QuoteMark.ets`）作为第二重区分。

## 4. 维护规则

1. 新增 token 必须同时改 base、dark、`TokenRegistry`、本文件，并跑 `node scripts/check-dark-tokens.mjs`。
2. 任何 `.ets` 出现 `#RRGGBB` / `Color.Red` 等业务颜色，`check-dark-tokens` D-03 直接失败。
3. 调整深色值后跑 `node scripts/check-contrast.mjs`；浅色调整需显式确认并附重截证据。
4. `accent` 与 `accent_fill` 不要混用：文字/边框用 `accent`，红底白字用 `accent_fill`。
