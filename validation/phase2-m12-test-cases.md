# 阶段二 · M12 横屏与深色验收用例（AC-122~124）

> 版本：v1.0（代码完成，待入库） · 日期：2026-11-14
> 范围：M12-1 横屏详情、M12-2 深色色板与接线、M12-3 对比度与红绿可辨、M12-4 全站扫色与图表重着色、M12-5 切换不丢状态与证据。
> 规格依据：计划 §4.4-G7 兜底（设计稿 G-6/G-7 未到）；色值见 [docs/phase2-tokens.md](../docs/phase2-tokens.md)。
> 证据目录：[shots/phase2/m12](../../shots/phase2/m12)；性能/设备记录见 [docs/perf/phase2-m12.md](../docs/perf/phase2-m12.md)。

---

## 0. 结论状态

| 维度 | 结果 |
|---|---|
| 构建 | `devecocli build` 绿（debug，9 模块） |
| 门禁 | `gate.ps1` **6 步全绿**：版本 V-01~03 / 占位文案 **2 条** / R-01~R-09（**150 文件**）/ 深色 token D-01~D-03 / 对比度 C-01~C-04 / lint 0 error 4 warning（阶段一既有） |
| Local Test | `features/watchlist` **21/21**（CardMetrics 10 + QuoteMark 5 + DetailLayout 6）；`features/search` **48/48**（M6 26 + M7 22 回归） |
| UiTest | **19/19**（M6 8 + M7 6 + M8 4 + **M12 1**，真机/模拟器） |
| 截图 | **25 张**（见 §0.1） |
| 深色覆盖率 | 列表 / 卡片 / 详情（分时 + 日 K）/ 搜索 / 添加页 / 分组管理 / 交易弹窗 / 离线 / 错误态 / 热切 |
| 横屏覆盖率 | 460vp 竖屏详情、940vp 横屏详情（62/38 + 指标 6×2 + 底部读数条）、折叠↔展开切换 |
| 未取证 | 系统深色**冷启**（模拟器无法脚本化切系统深色）、4 形态 × 3 主界面矩阵（仅阔折叠模拟器）、切换 ≤300ms 逐帧、图表 pinch 缩放保留、读屏听测 |

### 0.1 证据文件

| 文件 | 内容 |
|---|---|
| `01-light-card.png` | 浅色卡片：▲/▼ 与颜色并存 |
| `02-light-list.png` | 浅色列表：涨跌/涨跌幅两列加 ▲/▼，16fp 列宽不截断 |
| `03-light-detail.png` | 浅色详情（竖屏/分时）：报价头涨跌 + ▲/▼，图表浅色 |
| `04-dark-card.png` | 深色卡片：`bg_page #0F1115` / 卡片 `bg_surface #1A1D23`，红绿可读 |
| `05-dark-list.png` | 深色列表：表头/分隔线/置灰层级正常，无浅色残留 |
| `06-dark-detail.png` | 深色详情（分时）：图表线/均价/网格/读数条全部深色 |
| `07-dark-search.png` | 深色搜索：搜索栏、热门搜索、全部股票、右栏空态 |
| `08-dark-add.png` | 深色添加页：scrim、搜索栏、分组 chips、禁用提交 |
| `09-dark-group-manage.png` | 深色分组管理：分组行、默认标签、禁用「新建分组」 |
| `10-dark-offline.png` | 深色离线：banner `accent_soft` + 卡片 55% 置灰 |
| `11-dark-error.png` | 深色错误态：StateView 图标/说明/描边按钮 |
| `12-dark-trade.png` | 深色交易弹窗：价格/数量输入、涨跌停色、买入按钮 |
| `13-light-search.png` / `14-light-add.png` | 浅色同界面对照（无回归） |
| `15-hotswitch-dark-to-light-detail.png` | **热切**：深→浅后详情与图表同帧变浅，无白闪（目视） |
| `16-light-list-scrolled.png` / `17-dark-list-scrolled.png` | **滚动位置保持**：切换前/后首行均为「示例科技11」，坐标一致 |
| `18-dark-detail-dayk.png` / `19-light-detail-dayk.png` | **图表周期保持**：切换前后均为「日 K」选中，K 线配色随主题变 |
| `20-landscape-detail.png` | **横屏 940vp**：左 62%（报价头+周期+图表+指标 6×2）/ 右 38%（盘口+明细）/ 动作栏固定底部 |
| `21-portrait-detail.png` | **竖屏 460vp**：原详情布局（非横屏分支），动作栏固定底部 |
| `22-landscape-unfold.png` | **折叠→展开**：竖屏详情切到横屏布局，无崩溃/黑屏 |
| `23-portrait-dark-detail.png` | 深色竖屏详情；**旋转后十字光标已取消**（对比 `25` 的竖线/读数） |
| `24-landscape-dark-detail.png` | 深色横屏详情：左右分栏、图表、盘口、动作栏均深色 |
| `25-landscape-readout.png` | 横屏长按十字光标：读数条在**动作栏上方 22vp 通栏**，不遮挡 K 线 |

---

## 1. AC 用例

### AC-122 横屏详情

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 1 | 460vp 竖屏（折叠态）进详情 | 走原详情布局（`detail_layout`），不出现左右分栏 | `21` + `ui layout` `Column#detail_layout` |
| 2 | 展开到 940vp（宽>高） | 切横屏布局（`detail_landscape`）：左 62% / 右 38% | `20`/`22` + `ui layout` `Column#detail_landscape [0,261,2584,1828]` |
| 3 | 横屏左列 | 报价头 + 周期 + 图表 + 指标 6 列 × 2 行；图表不截断 | `20` |
| 4 | 横屏右列 | 五档 + 比例条 + 成交明细，纵向铺满，与左列底对齐 | `20` |
| 5 | 动作栏 | 固定底部，不随左列滚动；「去交易」红底白字 | `20`/`24` |
| 6 | 读数条 | 横屏长按十字光标：22vp 通栏在动作栏上方，不遮挡 K 线 | `25` |
| 7 | 旋转后十字光标 | 十字光标与读数条取消 | `25` → `23`（竖线/读数消失） |
| 8 | 折叠↔展开 | 布局分支切换，无崩溃/黑屏 | `21`→`22`→`23` 连续操作 |
| 9 | 其它页 | 只有详情页允许横屏；自选/搜索/添加页保持竖屏 | 代码：`DetailPage.onShown/onHidden` 只对详情页调 `OrientationHost`；**手机真机未实测** |
| 10 | 3 形态横屏截图 | 直板/折叠/平板 | **缺口**：仅阔折叠 940vp；手机横屏与平板未取证 |
| 11 | UiTest | 详情按窗口宽高进入对应布局分支 | `M12UiTest.AC122_detail_landscape_branch_by_display` **1/1 PASS** |

> 60 秒速记：横屏只对 `DetailContent(mode:'page')` 生效；`pane`/`window` 不重排，避免 M6~M8 分栏与多窗回归。

### AC-123 深色全站生效 + 对比度 + 红绿可辨

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 1 | 自选列表/卡片切深色 | 页面/卡片/表头/分隔线/底栏全部深色；无浅色残留 | `04`/`05`/`06` |
| 2 | 搜索、添加页、分组管理、交易弹窗 | 输入框、chips、遮罩、弹窗底与文字全部深色 | `07`/`08`/`09`/`12` |
| 3 | 离线 / 错误态 | banner 用 `accent_soft`；StateView 图标灰阶、文字可读 | `10`/`11` |
| 4 | 文本对比度 | dark 文本对 ≥4.5:1 | `node scripts/check-contrast.mjs`：**23/23 PASS** |
| 5 | 非文本对比度 | dark 状态色 ≥3:1 | 同上：**5/5 PASS** |
| 6 | 涨跌红绿可辨 | ΔE76 ≥20 且亮度差 ≥15% | base ΔE 121.3 / 32.2%；dark ΔE 116.5 / 27.0% |
| 7 | 涨跌除颜色外有 ▲/▼ | 自选表格涨跌/涨跌幅、卡片、详情报价头、盘口、成交明细、指数条、搜索结果 | `02`/`01`/`03`/`06`/`07`；单测 `QuoteMark` 5/5 |
| 8 | 平盘/停牌/新股/空值 | 不加符号；停牌 `--` 不加 | 列表 `03-list-sorted-bottom`（M8）+ 代码 |
| 9 | 热切深浅 | 立即重着色、无白闪、不重建页面；横屏下同样生效 | `15`（竖屏）、`24`（横屏深色） |
| 10 | 系统深色冷启 | 首帧即深色（启动窗口不白闪） | **未取证**：模拟器无脚本化系统深色；建议真机补 |
| 11 | 4 形态 × 3 主界面 | 直板/折叠/阔折叠/平板各 3 屏 | **仅阔折叠模拟器**；sm/平板缺口 |

> 浅色基线说明：阶段一浅色有 9 组文本对低于 4.5:1（`text_secondary` 3.44、`price_up` 4.24、`price_down` 3.07 等），属已验收视觉基线；本期 `check-contrast` 对 base **只报告不失败**，需要收紧时设 `STRICT_LIGHT=1` 并同步重截阶段一证据。

### AC-124 深浅/横竖切换保持状态

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 1 | 列表滚动到「示例科技11」后浅→深 | 滚动位置不变（首行/坐标一致） | `16`/`17` + `ui layout` 首行均为 `[55,639] 示例科技11` |
| 2 | 当前分组「融资融券」切深色 | 分组不变、股票集合不变 | 实机操作 + 深色截图可见「融资融券」仍选中 |
| 3 | 详情选「日 K」后浅↔深 | 周期保持日 K，K 线配色随主题变 | `18`/`19` |
| 4 | 切主题期间 | 不触发 `load()`；`onConfigurationUpdate` 只更新 `fontScale/colorMode` | 代码 + hilog `onConfigurationUpdate ... colorMode=dark` |
| 5 | 竖屏↔横屏（折叠/展开） | 布局分支切换、周期/分组/选中不丢；十字光标取消 | `21`→`22`；`25`→`23` |
| 6 | 排序态 | 排序键与方向保持 | 代码（`SortState` 不随主题/尺寸重建）；未单独截图 |
| 7 | 弹窗输入 | 交易弹窗价格/数量输入保持 | 代码（弹窗组件不重建）；未单独截图 |
| 8 | 图表缩放 | 旋转后保留缩放（只重排，不重置） | 代码 `captureViewport/restoreViewport`；**pinch 未实测** |

---

## 2. 跨模块影响

| 项 | 变更 | 验证 |
|---|---|---|
| `commons/ui` 色板 | 新增 `dark/element/color.json`（30 键）、`color_accent_fill` | build + `check-dark-tokens` 键集合一致 |
| `products/entry` | `dark/element/color.json`（启动窗口底）、去掉强制浅色 | 深色首帧背景正确（热切可见） |
| `ConfigService` | 新增 `colorMode` + `applyColorMode/updateColorMode` | 图表重着色、日志 |
| `ChartEngine` | `setStyle` 复用 `lastSeries` 重建 DataSet；新增 `captureViewport/restoreViewport/clearSelection` | 热切实测 `15`/`18`/`19`；旋转 `21`→`22` |
| `BreakpointService` | 新增 `viewportHeight` / `isLandscape`，`apply(width,height)` | `22` 横屏分支、`21` 竖屏分支 |
| `OrientationHost` | 新增窗口方向挂载点；详情页 `onShown/onHidden` 切换 | `21`↔`22` 折叠/展开 |
| `AppColor.accentFill` | 红底白字按钮/勾选改用 `#D92D24` | 白字对比 4.83；浅色截图无异常 |
| `QuoteMark` | 新增纯函数 `arrowOfDir/arrowOfTone/arrowOfValue` | 单测 5/5 |
| 自选表格/卡片/详情/盘口/搜索/指数条 | 涨跌数值前加 9~11fp 符号 | 浅/深截图 + 1.45× 回归待补 |
| `DetailLayout` | 新增横屏 62/38、图表高度、指标列数纯函数 | `DetailLayoutLandscape` 6/6 |
| `MetricPanel` | 横屏 12 项 6×2（标签上/数值下），1.3× 降 4×3 | `20`/`24` |
| `ReadoutBar` | 抽成独立组件；横屏由 `DetailContent` 放到动作栏上方 | `25` |
| `FrozenTable` 延迟角标 | 白字底改为 `textPrimary` 底 / `bgPage` 字（深浅都 ≥15:1） | `02`/`05` 截图无异常 |
| 调试入口 | 自选「外观…」；详情「切换深浅色（M12 验收）」 | 取证通道，release 不可见 |

---

## 3. 待补与风险

1. **系统深色冷启**：模拟器无 `settings`/color mode 命令，`DarkModeExtensionSettingsAbility` 无权限直接拉起；需真机切系统深色后 `aa force-stop` + 拉起，验证启动窗口与首帧。
2. **4 形态矩阵**：当前仅阔折叠模拟器（940vp 展开/460vp 折叠）；手机 sm（388vp）横屏/深色、平板 xl 未取证。
3. **切换耗时**：目视即时（<300ms 预算），未逐帧录屏量化。
4. **图表缩放保留**：已实现 `captureViewport/restoreViewport`，但 pinch 手势未自动化/未实测；需真机手动验证。
5. **读屏听测**：▲/▼ 的朗读语义（读「涨/跌」而非符号）未人耳听测，归 T-08。
6. **1.45× 字号**：符号用 Span 小字号，388vp / 1.45× 下固定列宽未逐列断言；横屏 1.3× 降 4 列仅单测，未真机截图。
7. **其它页锁竖屏**：按已确认方案 A 只对详情页允许旋转，其它页未强制 PORTRAIT；需真机确认系统自动旋转开启时其它页不会转，否则再补手机专用锁。
