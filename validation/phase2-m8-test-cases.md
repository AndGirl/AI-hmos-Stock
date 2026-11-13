# 阶段二 · M8 卡片视图验收用例（AC-100~105）

> 版本：v1.0 · 日期：2026-11-13 · 状态：**代码完成，待入库（只改未提交）**
> 范围：M8-1~M8-7（计划 §7.4），规格依据 §4.4-G4 兜底（设计稿 G-4 未到）。
> 证据目录：[shots/phase2/m8](../../shots/phase2/m8)；性能数据见 [docs/perf/phase2-m8.md](../docs/perf/phase2-m8.md)。

---

## 0. 结论状态

| 维度 | 结果 |
|---|---|
| 构建 | `devecocli build` 绿（debug，9 模块） |
| 门禁 | `gate.ps1` 四步全绿：V-01~03 / 占位文案 **2 条**（`coming_soon_card_view` 已删）/ R-01~R-09 / lint 0 error 4 warning（阶段一既有） |
| Local Test | `features/watchlist` **10/10**（新增 `CardMetrics`：12 组布局断言 + 列数/指标/视图形态） |
| Local Test（回归） | `features/search` **48/48**（M6 26 + M7 22，未受影响） |
| UiTest | **M8 4/4**（`CardViewUiTest`：真机 Mate 60 Pro 跑通 + 代码定稿后在阔折叠模拟器复跑 4/4）；**全量 18/18**（M6 8 + M7 6 + M8 4，真机） |
| 真机截图 | **17 张**（列表基线、卡片 2 列、卡片底部单一入口、滚动中、排序 chip、列表/卡片顺序对照、清除排序、离线置灰、200 卡压测、lg 4 列、lg 1.45× 降 3 列、冷启首帧即卡片、卡片↔列表锚定对照 3 张） |
| 未取证 | 停牌/新股**卡片**特写（列表侧已有）、xl（≥1180vp，5 列）真机断言、50 卡滚动与 200 卡帧率（设备掉线中断）、读屏语音听测 |

### 0.1 证据文件

| 文件 | 内容 |
|---|---|
| `00-list-baseline.png` | 列表基线：分组栏右侧新增视图切换按钮（列表态显示「卡片」图标） |
| `01-card-sm.png` | 卡片视图（sm 388vp，2 列）：名称/代码/最新价+涨跌+涨跌幅 + sm 4 项指标（今开/最高/最低/成交额） |
| `02-card-scrolled.png` | 卡片滚动中：行高自适应、无横向滚动 |
| `02-card-bottom-single-entry.png` | 卡片滚到底：**只剩底部胶囊一个「添加自选」**（卡片尾部虚线卡已按 2026-11-14 决定退场） |
| `04-card-sort-chip-suspended-new.png` | 分组栏下方排序 chip「按涨跌幅↓ ×」（AC-102） |
| `05-list-sorted-asc.png` / `06-card-sorted-asc.png` | 同一次升序排序下，列表与卡片的行序逐一对照（前 8 只完全一致） |
| `07-card-sort-cleared.png` | 点 chip「×」后回到默认序、chip 消失 |
| `08-card-offline.png` | 断线：全局 banner + 卡片整体 55% 置灰（数据冻结） |
| `10-card-stress200.png` | 调试「卡片压测 200（不落盘）」：合成 200 卡用于帧率采样 |
| `11-card-lg-4col.png` | **lg（阔折叠 940vp）：4 列**，卡宽 215vp、gap 16、6 项指标 2 列 × 3 行（AC-100） |
| `12-card-lg-145-3col.png` | **lg + 1.45×：4 列 → 3 列**，指标仍 2 列，数值不截断（AC-100「只降列不截断」） |
| `13-coldstart-card.png` | **冷启首帧即卡片**：`aa force-stop` 后重新拉起，首个布局即为 `Grid#card_grid`（AC-103 持久化） |
| `14-anchor-list-top.png` | 锚定对照 ①：列表在**顶部**（切换前） |
| `15-anchor-card-mid.png` | 锚定对照 ②：切卡片后滚到 **示例科技15（602014）** 起头 |
| `16-anchor-back-to-list.png` | 锚定对照 ③：切回列表，首行正是 **示例科技15**（不是顶部）——P1 修复后实测 |
| `03-list-sorted-bottom.png` | 列表末尾：停牌（浦发银行，`--`+「停」）与新股（新锐科技，`--`+「新」）排在空值末尾 |

---

## 1. AC 用例

### AC-100 列数 / 间距 / 无横向滚动 / 字号只降列

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 1 | sm(388vp) 进卡片视图 | 2 列、gap 12、页内边距 16；卡宽 172vp | `01` + 布局树 `Stack [52,647,611,1219]`（卡宽 559px ≈ 172vp） |
| 2 | 4 断点 × 3 字号共 12 组几何 | 无横向滚动、列数 ∈ [2,5]、卡宽 ≥120vp | 单测 `case_no_horizontal_overflow_12_combos` |
| 3 | 1.0× 列数表 | sm2 / md3 / lg4 / xl5（D53） | 单测 `case_columns_table_at_base_font` |
| 4 | 1.45× 只降列 | md 3→2、lg 4→3、xl 保持 5、sm 保持 2（下限 2） | 单测 `case_columns_reduced_at_145` + **lg 真机模拟器**：4 列 → **3 列**、数值不截断（`12-card-lg-145-3col`） |
| 5 | 卡宽反算 | 卡宽取整后剩余不足一列，永不溢出 | 单测 `case_card_width_fills_viewport_without_overflow` |
| 6 | lg（阔折叠 940vp） | **4 列**、卡宽 215vp、gap 16、页内边距 16、无横向滚动（布局树 `Stack [44,551,635,1065]` 等 4 张/行） | `11-card-lg-4col` |

> 口径：几何只由「断点 + 容器宽 + 字号」决定（`CardMetrics` 纯函数），卡片视图在 xl 走整宽（右栏详情让位），否则 523vp 左栏放不下 5 列。

### AC-101 卡面字段与单卡刷新

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 1 | 卡片首行 | 名称 16sp + 标签（停/新/待同步）+ 代码 12sp | `01` |
| 2 | 价格区 | 最新价 20sp 粗体 + 涨跌 + 涨跌幅（涨/跌/平三色） | `01`/`06` |
| 3 | 指标 | 固定池 6 项（今开/最高/最低/成交额/换手率/量比）；**sm 卡 4 项**；卡宽 <200 时单列（标签左/值右），≥200 时 2 列×3 行 | `01`（sm 单列 4 项）+ 单测 `case_metric_count_by_breakpoint` / `case_metric_columns_switch_by_card_width` |
| 4 | 单卡刷新 | 行情 patch 只改该行对象 → 只重绘 1 张卡 + 320ms 高价闪烁 | 代码（`WatchRowVM` 全 `@Trace`，`CardCell` `@Monitor('row.quote.flashSeq')`） |
| 5 | 添加入口 | 卡片视图**只有一个**「添加自选」入口（底部胶囊），尾部虚线卡已退场，避免与胶囊重复；列表/卡片共用同一 `openAdd()`（当前分组作为目标分组默认值） | `02-card-bottom-single-entry`（布局树只有 1 个「添加自选」节点） |

### AC-102 排序 chip（共用 SortState）

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 1 | 列表态点「涨跌幅」列头 | 降序，列头显示 ↓ | `05-list-sorted-asc`（升序态 ↑，同机制） |
| 2 | 切到卡片视图 | 分组栏下方出现 chip「按涨跌幅↓」 | `04` |
| 3 | 列表与卡片顺序对照 | 前 8 只完全一致（示例科技01/10/20/11/21/招商银行/平安银行/贵州茅台） | `05` vs `06` |
| 4 | 点 chip 本体 | 复用列头循环（降→升→取消），不新增第三套排序态 | `06`（↑）→ 点本体后 `04` 为 ↓ |
| 5 | 点 chip「×」 | 回默认序、chip 隐藏、分组与选中不变 | `07` + UiTest `AC102_sort_chip_visible_and_clearable` |
| 6 | 无排序时 | chip 整条隐藏（不占位） | `01`/`02` |
| 7 | 排序生效时新增自选 | 不滚动、不高亮（沿用 `focusRow` 保护） | 代码（`focusRow` 在 `sortKey !== null` 时返回） |

> 注：排序是「快照序」——重排只发生在点列头/chip 时，之后行情继续跳动不会重排（M2 起既有口径，避免行跳动）；因此隔几分钟再截图，数值看起来不再严格单调，属预期。

### AC-103 切换 / 锚定 / 动画 / 持久化

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 1 | 点分组栏右侧切换 | 150ms 淡入、无白屏、不重建 VM（分组/排序/选中保留） | 代码（`animateTo(150ms)` + VM 单例）+ UiTest `AC100` |
| 2 | 快速连点 | 200ms 节流，只生效一次 | 代码（`VIEW_TOGGLE_THROTTLE_MS`） |
| 3 | 切换后位置 | 两个方向都锚定：有选中（右栏标的/多选/编辑首项）锚定该项，否则用该视图首行；切回列表按**下标**还原（不是旧像素偏移） | `14`→`15`→`16`（列表顶部 → 卡片滚到 602014 → 切回列表首行 602014）；代码 `FrozenTable.onAppear` 下标优先 + `CardGrid.onAppear` 用 `scrollToIndex` |
| 4 | 偏好落盘 | `view_pref_v1` 立即写；重启仍为卡片，且**首帧不出现列表** | UiTest `AC103_view_mode_kept_after_relaunch` + **真机模拟器冷启**：`aa force-stop` 后拉起，首个布局即 `card_grid`（`13-coldstart-card`） |
| 5 | 首帧无闪烁 | 页面出内容前 `await` 视图偏好，加载期只显示中性骨架 | 代码（`WatchlistVM.load` 先 `pref.load()` 再 `applyData`） |
| 6 | 调试「清除视图记忆」 | 删键并回列表（仅 debug） | 调试面板第 6 项 |

### AC-104 状态一致（停牌/新股/离线/空错态/字号）

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 1 | 停牌（浦发银行） | `--` + 「停」标签 + 55% 不透明度 | `03-list-sorted-bottom`（列表）+ 代码（卡片同口径 `opacity 0.55` + 标签） |
| 2 | 新股（新锐科技） | 涨跌/涨跌幅 `--` + 「新」标签 | `03` |
| 3 | 断线 | 全局 banner + 卡片整块 55% 置灰、数据冻结（不刷新） | `08-card-offline` |
| 4 | 空态 / 错误态 | 与列表完全一致（引导式空态、分组空态、失败重试） | 代码：状态分支在视图形态之外先行判断 |
| 5 | 字号三档 | 只降列、不截断；卡高按内容增长（min 132vp × 字号） | 单测 12 组 + 代码（`minCardH` 随字号放大、指标改单列） |

### AC-105 卡片无障碍

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 1 | 单卡可聚焦 | 卡根 `accessibilityGroup(true)` + `accessibilityText` | 代码（`CardCell`） |
| 2 | 朗读覆盖展示字段 | 名称/代码/标签/最新价/涨跌/涨跌幅 + 该断点展示的 4 或 6 项指标 | 代码（`WatchRowVM.cardAccessibilityLabel(metricCount)`） |
| 3 | 不朗读未展示列 | 卡片不出现「总量/现量/振幅/市盈率/市净率」 | 代码（指标池只取 4/6 项） |
| 4 | 语音听测 | **未做**（T-08 仍开）：无人工听测条件，只做代码级 + 文本覆盖 | — |

---

## 2. 跨模块影响

| 项 | 变更 | 验证 |
|---|---|---|
| `SymbolQuote` | 新增 `open/high/low/volumeRatio`（只随快照更新，`QuotePatch` 不含） | build + 卡面数值正常 |
| `ConfigService` | 新增 `viewMode` + `applyViewMode()`（首帧预热副本） | EntryAbility 日志 `viewMode=card` |
| `DataServices` | 新增 `viewPref()`（`view_pref_v1` 唯一入口） | 单测/真机 |
| `EntryAbility` | onCreate 预热视图偏好；新增 `onBackPressed()` 转发 `BackDispatcher` | 真机返回键：分组浮层/编辑态先退一层 |
| `GroupTabs` | 删除右侧两个 32vp 占位（卡片/排序） | `01`（只剩切换按钮） |
| `FrozenTable` | 根节点加 `id('list_table')`（UiTest 定位用） | UiTest AC100 |
| 占位文案 | 删 `coming_soon_card_view`（资源 + 常量 + 门禁期望键 + gates.md） | `gate.ps1` 2 条通过 |

---

## 3. 埋点事件（M8）

| 事件 | 参数 | 触发 |
|---|---|---|
| `card_view_switch` | `mode`（list/card） | 切换视图（节流通过后） |
| `card_sort_by` | `key` / `dir` | 卡片态点 chip 本体（复用列头循环） |
| `card_sort_clear` | — | 点 chip「×」清除排序 |

---

## 4. 自动化

### 4.1 Local Test（Hypium，`-p module=watchlist`）

```powershell
$env:DEVECO_SDK_HOME='D:\Huawei\DevEcoStudioRelease\DevEcoStudioTools\DevEco Studio\sdk'
& $node $hvigor test -p module=watchlist -p coverage=false
# 结果：features/watchlist/.test/default/intermediates/test/coverage_data/test_result.txt
# Tests run: 11, Failure: 0
```

覆盖：12 组几何断言、列数表、1.45× 降列、下限 2 列、列数上限 5、间距随列数（12/16）、卡宽反算不溢出、指标条数（sm4/其余6）、指标列数阈值、视图形态归一化与切换。

### 4.2 UiTest（ohosTest，真机）

前置：解锁亮屏；仅 1 台 hdc 目标；`param set persist.ace.testmode.enabled 1`。

```powershell
& $node $hvigor onDeviceTest -p module=entry -p coverage=false -p scope=CardViewUiTest
# 结果：products/entry/.test/default/intermediates/ohosTest/coverage_data/test_result.txt
```

| 用例 | 断言 |
|---|---|
| `AC100_switch_to_card_and_back` | 点 `id=view_switch` → 出现 `id=card_grid` → 再点 → 出现 `id=list_table` |
| `AC101_card_shows_name_price_and_metrics` | 卡片态出现「今开」指标与「贵州茅台」名称 |
| `AC102_sort_chip_visible_and_clearable` | 列表点「涨跌幅」列头 → 切卡片出现「按涨跌幅↓」→ 点 `id=card_sort_clear` → chip 消失 |
| `AC103_view_mode_kept_after_relaunch` | 切卡片 → 重新拉起（bringToFront）→ 仍是 `card_grid`；收尾回列表（冷启落盘另见 `13-coldstart-card` 手工取证） |

---

## 5. 已知偏差与后续

| # | 项 | 说明 |
|---|---|---|
| 1 | xl 卡片整宽 | 卡片视图在 xl 隐藏右栏详情、按 5 列整宽渲染（AC-100 需要 5 列，523vp 左栏放不下）；列表视图分栏口径不变 |
| 2 | 卡内指标排布 | G-4 写「2 列 × 3 行」；本实现按卡宽自适应：`cardW ≥ 200` 双列、`< 200` 单列（标签左/值右），避免 1.45× 挤压；条数仍按断点（sm 4 / 其余 6） |
| 3 | 排序 chip 位置与交互 | 放在分组栏下方、仅卡片态显示；点本体复用列头循环（降→升→取消），点「×」清除；不新增排序面板（CK-2） |
| 4 | 1.45× 验证口径 | 调试「字号…」只注入布局用的 `ConfigService.fontScale`（不改变真实字形，M2~M7 同口径），因此「4→3 列」是几何口径的证据，**不是**系统中文字号放大后的字形证据；真机字形放大仍待系统字号设置实测 |
| 5 | 卡片闪烁层 | 卡高自适应，闪烁层不能用 `height('100%')`（会被解析成整屏高、只出一行）；改为按卡身实测高度（`onAreaChange`）铺满 |
| 6 | 200 卡压测 | 自选上限 50，压测行由调试面板生成（200 条合成行，不落盘、不订阅行情、不参与列表）；仅卡片态可用 |
| 7 | xl 卡片截图 | lg（940vp，4 列）已取到真机模拟器截图；**xl（≥1180vp，5 列）仍无设备**，由单测 + lg 实测外推，待平板真机补 |
| 8 | 读屏听测 | 仅代码级 + 文本覆盖，人耳听测未做（T-08 保持打开） |
| 9 | `watch_entry_card` 资源 | 视图切换改为图标 + 新朗读文案后该键暂未引用（保留备用，未删）；`watch_entry_sort` 已随占位删除 |
| 10 | 评审修复（P1：卡片→列表不锚定） | `FrozenTable` 切回时是重建的，`@Monitor('scrollSeq')` 对初始值不触发，原先只按 `initialVOffset`（旧像素偏移）复位。现改为：`onAppear` 优先用 `scrollToIndex` 按下标还原，无有效下标才回落旧偏移；实测 `14→15→16` |
| 11 | 评审修复（P2：滚动期整页重渲染） | 原先把「卡片首个可见行」当 `@Param initialIndex` 传入，`cardIndex` 每次跨行变化都会让页面 + Grid 重跑 build（而该入参只在 `onAppear` 用一次）。现移除该入参，`CardGrid.onAppear` 复用 `scrollToIndex`；`listIndex/cardIndex` 去掉 `@Trace`，只在切换瞬间被读取 |

---

## 6. 执行记录（2026-11-13）

| # | 步骤 | 结果 |
|---|---|---|
| 1 | `devecocli build` | ✅ BUILD SUCCESSFUL |
| 2 | `node scripts/check-coming-soon.mjs` | ✅ 2 条通过 |
| 3 | `gate.ps1` | ✅ GATE PASS（0 error / 4 warning） |
| 4 | `hvigor test -p module=watchlist` | ✅ 11/11 |
| 5 | `hvigor test -p module=search` | ✅ 48/48（回归） |
| 6 | `hvigor onDeviceTest -p scope=CardViewUiTest` | ✅ 4/4 |
| 7 | `hvigor onDeviceTest`（全量） | ✅ 18/18 |
| 8 | 真机/模拟器截图 | ✅ 13 张（`shots/phase2/m8`；sm 用 Mate 60 Pro、lg 用阔折叠模拟器） |
| 9 | 50 卡静止帧率 | ✅ 60.4fps / jank 0（见 perf 文档） |
| 10 | 真机模拟器（阔折叠 940vp）补测 | ✅ lg 4 列 / 1.45× 3 列 / 冷启首帧即卡片；`CardViewUiTest` 4/4 |
| 11 | 评审 P1+P2 修复后复跑 | ✅ build / gate 绿、Local Test 11/11、`CardViewUiTest` 4/4；锚定对照 3 张（`14~16`） |
