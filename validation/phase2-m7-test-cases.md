# 阶段二 · M7 添加自选与分组验收用例（AC-94~99）

> 版本：v1.0 · 日期：2026-11-13 · 状态：**已入库（5 提交，未推送）**
> 范围：M7-1~M7-7（计划 §7.3）。AC 口径以《阶段二开发计划》§6.2 与 PRD FR-04 为准。
> 证据目录：[shots/phase2/m7](../../shots/phase2/m7)。

---

## 0. 结论状态

| 维度 | 结果 |
|---|---|
| 构建 | `devecocli build` 绿（debug，9 模块） |
| 门禁 | `gate.ps1` 四步全绿：V-01~V-03 / 占位文案 **3 条** / R-01~R-09（129 文件）/ lint 0 error 4 warning（阶段一既有） |
| Local Test | `features/search` **48/48**（M6 26 + M7 新增 22：规则 14 + Store 8） |
| UiTest | **14/14**（M6 `SearchUiTest` 8 + M7 `AddWatchlistUiTest` 6，真机 Mate 60 Pro）；评审修复后（2 P1 + 9 P3）全量复跑仍 **14/14** |
| 真机截图 | **23 张**（添加页 4 形态、多选、上限、离线待同步、编辑/撤销、分组管理、空态、目标分组预置、撤销保序复验） |
| 未取证 | lg/xl 居中模态（无平板真机）、卡片虚线卡入口（属 M8）、Toast 逐条截帧（部分只有页内提示） |

### 0.1 证据文件

| 文件 | 内容 |
|---|---|
| `00-baseline.png` | 自选页基线（管理/编辑入口、底部「添加自选」胶囊、分组 Tab） |
| `01-add-open.png` | 添加页首帧：45/50、搜索框自动聚焦、目标分组 chips、历史/热搜/全部股票 |
| `02-add-results.png` | 搜 `600519`：已添加行置灰 +「已添加」、勾选框禁用（AC-96） |
| `03-add-multi.png` | 多选 2 只：勾选态 + 底部「加入自选（2）」（AC-95） |
| `05-after-add.png` | 提交后回列表：全部 45→47、融资融券 15→17、滚动到新增行并高亮（AC-97 前半） |
| `06-edit-mode.png` | 编辑模式：已选 3 只、行前勾选、底部「全选/取消/移出（3）」（AC-98） |
| `07-remove-confirm.png` | 移出二次确认框（AC-98） |
| `08-undo-bar.png` | 撤销条：已移出 3 只自选 / 3s / 撤销；列表 47→44（AC-97 后半） |
| `09-undo-restored.png` | 点「撤销」后数量与行恢复（44→42→44 往返） |
| `10-group-sheet.png` | 分组管理浮层：全部（虚拟）/系统组「默认」/用户组可改名删除（AC-99） |
| `14-group-tabs.png` | 分组 Tab 名称完整显示（不截断），超出横向滑动 |
| `15-group-create.png` | 新建用户组「swing」出现在列表（AC-99） |
| `16-group-rename.png` | 重命名 swing→hold 生效（AC-99） |
| `17-group-delete-confirm.png` | 删除「我的关注」二次确认，标题显示组名（AC-99） |
| `18-group-deleted.png` | 删除后：全部仍 45（只删归属）、融资融券 15→43、分组消失（AC-99/INV-1） |
| `19-offline-add.png` | 断线态：全局 banner + 页内离线提示，加入后行标「待同步」（AC-96） |
| `20-pending-synced.png` | 恢复在线：「待同步」标记消失（AC-96） |
| `21-limit.png` | 50/50 + 「最多添加 50 只，已达上限」页内提示，提交不生效（AC-96） |
| `22-preset-detail.png` | 详情「自选设置」入口：添加页预置 code，显示「已在自选 · 已属 2 个分组」（AC-94 E4） |
| `23-empty-state.png` | 自选空态主按钮改为「添加自选」（E2） |
| `24-target-group.png` | 从「创业板」Tab 进入：目标分组 chips 默认选中创业板（AC-95） |
| `25-undo-order-before.png` | 编辑态勾选第 2~4 行（平安银行/宁德时代/中芯国际），移出前顺序 |
| `26-undo-order-after.png` | 撤销后三行原位恢复，顺序与移出前完全一致（P1 顺序修复真机复验） |

---

## 1. AC 用例

### AC-94 四入口 + 容器形态 + 进入即聚焦

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 1 | 自选页点底部胶囊「添加自选」 | 进添加页，页头「添加自选」+ N/50，输入框自动聚焦（键盘自动弹出） | `01` |
| 2 | 自选空态点主按钮「添加自选」 | 同上；空态不再出现「去行情加自选」 | `23` |
| 3 | 详情页动作栏「自选设置」 | 打开添加页并预置该 code，展示「已在自选 · 已属 N 个分组」+「加入分组」按钮 | `22` |
| 4 | 自选页右栏（xl）「自选设置」/ 行情右栏「自选设置」 | 同上（代码同走 `AppServices.pushAddWatchlist(code)`） | — |
| 5 | 卡片尾部虚线卡（E3） | **M8 落地**（卡片本体属 M8-2），M7 不在范围内 | — |
| 6 | sm/md 形态 | 全屏页（Mate 60 Pro 388vp 实测） | `01` |
| 7 | lg/xl 形态 | 居中模态 560vp、高 82%（代码路径 `AddWatchlistPage.isWide()`）；**无真机平板，未截图取证** | — |

> 入口实现：胶囊/空态 → `onOpenAdd(groupId)`；详情/右栏/搜索页 → `onOpenAddWatchlist(code)`；统一 `AppServices.pushAddWatchlist(code?, group?, from?)`。

### AC-95 批量多选 + 计数 + 目标分组

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 1 | 添加页勾选 2 只未添加股票 | 勾选框变实心 ✓，底部实时变「加入自选（2）」 | `03` |
| 2 | 再点一次同一行 | 取消勾选，计数减 1 | 手动 |
| 3 | 未选任何组进入（从「全部」Tab） | 显示「未选则按板块自动」 | `01` |
| 4 | 从「创业板」Tab 进入 | 目标分组 chips 默认选中「创业板」，提示隐藏 | `24` |
| 5 | 叠加多个组 | chips 可多选，提交按并集 + 派生系统组写库 | 手动（`resolveGroupMembership` 单测） |

### AC-96 已添加不重复 / 50 上限 / 部分成功 / 离线待同步

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 1 | 搜索已在自选的 `600519` | 行尾「已添加」、勾选框禁用；点行不计数 | `02` + UiTest `AC96_added_row_not_selectable` |
| 2 | 调试「场景…→填满至 50」后再加 1 只 | 页头 50/50 +「最多添加 50 只，已达上限」；提交被拒、勾选保留 | `21` |
| 3 | 批量中部分超限 | 成功项生效并摘勾、超限项保留；提示「已加入 N 只，M 只超限：名称…」（**2026-11-14 起带名称**，最多 3 个、超出接「等」） | 单测 `case_limit_name_summary` / `case_limit_name_summary_truncates`；真机 Toast 需构造 48/50 场景，未截图 |
| 4 | 断线态加入 | 页内「当前离线，加入后将标记待同步」；提交后行标「待同步」 | `19` |
| 5 | 恢复在线 | 同步服务清零标记 + Toast「已同步 1 只自选」，行标记消失 | `20` |
| 6 | 50 只上限在 Store 判定 | `WATCHLIST_MAX_ITEMS=50`，UI 与 Store 双保险 | 单测 `case_count_user_groups` |

### AC-97 插入位置 / 滚动高亮 / 5s 撤销

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 1 | 无排序时加入 2 只 | 列表末尾追加并滚动到末行 + 320ms 高亮，全部 45→47 | `05` |
| 2 | 有排序时加入 | 按序落位、**不滚动不高亮**（`focusRow` 在 `sortKey!==null` 时直接返回） | 代码 + `06`（此时列表按涨跌排序，编辑态无跳动） |
| 3 | 编辑态移出 3 只 | 行即时消失、计数 47→44，出现撤销条「已移出 3 只自选 / 5s」 | `08` |
| 4 | 5s 内点撤销 | 按快照 `index+groups+addedAt+pending` 原位恢复 | `09` |
| 5 | 超过 5s | 撤销条消失、不可恢复 | 手动（`08` 的 3s 到 0 后消失） |

### AC-98 编辑模式

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 1 | 标题行点「编辑」 | 头部变「已选 N 只 + 完成」，行前出现勾选圈，底部操作条出现 | `06` |
| 2 | 编辑态点行 | 勾选/取消勾选，不跳详情 | `06`（点 3 行后 已选 3 只） |
| 3 | 全选 / 取消选择 | 全选当前分组全部行；再点变取消 | 手动 |
| 4 | 点「移出（3）」 | 二次确认「移出所选自选？/移出后 5 秒内可撤销」 | `07` |
| 5 | 确认/取消 | 确认后移出并出现撤销条；取消回编辑态 | `07`→`08` |
| 6 | 点「完成」或「取消」 | 退出编辑、清空勾选、恢复常规头部 | UiTest `AC98_edit_mode_enter_select_and_exit` |

### AC-99 分组管理

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 1 | 标题行「管理」或长按分组 Tab | 打开分组管理浮层：全部（虚拟）/系统组带「默认」/用户组带重命名删除 | `10` |
| 2 | 新建分组（≤8 字） | 立即出现在列表与 Tab，重名/空名/超长/emoji 被拒并提示原因 | `15` + 14 例单测 |
| 3 | 重命名用户组 | 生效并刷新 Tab；系统组只读（无按钮） | `16` |
| 4 | 删除用户组 | 二次确认显示组名；删除后**股票不丢**：全部仍 45、失去唯一分组的股票并入派生系统组 | `17`→`18` |
| 5 | 删除当前分组 | 自动回落到「全部」 | 代码 `applyData` 的 `selectionFound` 兜底 |
| 6 | 用户组 ≤7 | 第 8 个被拒并提示「自定义分组最多 7 个」 | 单测 `case_count_user_groups` |
| 7 | 分组 Tab > 5 | 名称完整显示、横向滑动查看其余（不再压到 1/5 宽度截断） | `14` |

---

## 2. 跨模块影响

| 项 | 变更 | 验证 |
|---|---|---|
| `WatchlistProvider` | 退化为仅 `indexSet()`（自选集合唯一来源是 `WatchlistStore`） | `pk` 编译 + 候选池改成 Store |
| `PkRepository` | 候选项改读 `DataServices.watchlistStore().codes()`（与自选同源） | build 绿；Pk 页正常换股 |
| `ConnectionHub` | 新增 `subscribe/unsubscribe`（非 UI 观察者），供待同步服务用 | 离线/恢复实测 |
| M6 P3（评审遗留） | ①撤出后清理多选/编辑残留 code；②热搜读屏文案走资源；③搜索历史 `clear()` 与首次读盘竞争用写代次解决 | build + 单测 + 真机 |
| 占位文案 | 删除 `coming_soon_add_watchlist`（常量/资源/门禁期望键同步），5 处调用点全部换成真实路由 | `gate.ps1` 3 条通过 |

---

## 3. 埋点事件（M7）

| 事件 | 参数 | 触发 |
|---|---|---|
| `watch_add_batch` | added/existed/limit/pending/groups | 添加页提交 |
| `watch_remove_batch` | count | 编辑态移出 |
| `watch_group_create` / `watch_group_rename` / `watch_group_delete` | 删除带 reassigned 数 | 分组管理 |

---

## 4. 自动化

### 4.1 Local Test（Hypium，`-p module=search`）

```powershell
$env:DEVECO_SDK_HOME='D:\Huawei\DevEcoStudioRelease\DevEcoStudioTools\DevEco Studio\sdk'
& $node $hvigor test -p module=search -p coverage=false
# 结果：Tests run: 40, Failure: 0
```

覆盖：
- `WatchlistRules`（14 例）：派生系统组（30/68/其它）、归属叠加去重、组名空/超长/emoji/重名/重命名自身、归一化、码点计数、用户组计数、容量常量；
- `WatchlistStore`（8 例，`StorageAdapter` 无 context 时退化为内存，可直接 new）：**撤销保持原顺序**、**撤销不突破 50 上限**、批量部分超限、已存在跳过并派生系统组、分组 CRUD/上限/系统组只读/组名校验、删组不丢股且无无组股票、pending 标记与清零、更新归属解析。

### 4.2 UiTest（ohosTest，真机）

前置：解锁亮屏；仅 1 台 hdc 目标（本次需先停模拟器）；`param set persist.ace.testmode.enabled 1`。

```powershell
& $node $hvigor onDeviceTest -p module=entry -p coverage=false -p scope=AddWatchlistUiTest
# 结果：products/entry/.test/default/intermediates/ohosTest/coverage_data/test_result.txt
```

| 用例 | 断言 |
|---|---|
| `AC94_add_page_from_watchlist_capsule` | 胶囊进入添加页；输入框、提交按钮齐全（先取证据再断言，失败也会关页） |
| `AC95_multi_select_updates_count` | 搜 601988（中国银行）选中后底部变「加入自选（1）」 |
| `AC96_added_row_not_selectable` | 搜 600519 显示「已添加」，点行后不出现「加入自选（1）」 |
| `AC98_edit_mode_enter_select_and_exit` | 编辑→勾选→「移出（1）」→取消→回常规态 |
| `AC99_group_manage_sheet_open_and_close` | 管理→分组管理/新建分组可见→关闭 |
| `AC96_pending_tag_absent_when_online` | 在线态无「待同步」标 |

> 两个套件可同一进程顺序执行：Driver 统一由 [TestDriver.ets](../products/entry/src/ohosTest/ets/test/TestDriver.ets) 的 `sharedDriver()` 提供（各自 `Driver.create()` 会触发 `uitest-api dose not allow calling concurrently`）。用例已改为与执行顺序无关（M6 会新增 601398，M7 因此改用 601988；不再断言具体 45/50）。

---

## 5. 已知偏差与后续

| # | 项 | 说明 |
|---|---|---|
| 1 | lg/xl 居中模态未截图 | 本机无平板/阔折叠真机；代码按 `lg||xl` 渲染 560vp 居中卡片，待设备补齐 |
| 2 | E3 卡片虚线卡 | 属 M8-2 卡片本体，M7 只做 E1/E2/E4 + 搜索/右栏入口 |
| 3 | Toast 逐条截帧 | 部分 Toast（加入成功/部分成功/上限）未在 1.8s 内抓到，页内提示与状态已截图；行为由代码路径 + UiTest 覆盖 |
| 4 | 「部分成功」文案 | 全量超限时提示「最多添加 50 只，已达上限」；真部分成功提示「已加入 N 只，M 只超限：名称…」，**已补逐条名单（2026-11-14）**：`limitNameSummary` 最多列 3 个名称，超出接「等」 |
| 5 | 预置标的改分组 | 详情入口只提供「加入分组」（并集叠加），不提供从添加页移出；移出走自选页编辑模式 |
| 6 | 分组 Tab 展示数量 | 名称保持完整，388vp 下可见 4 个 + 横滑（原实现压到 1/5 宽度会把「融资融券」截成「融…」） |
| 7 | 数据初态 | 每次 `onDeviceTest`/重装可能保留磁盘数据；用例按 45 只种子初态设计，手工验证前建议调试「重置」 |
| 8 | 浮层返回键 | 分组管理浮层与编辑态未接管系统返回（页面在 `TabContent` 内，没有 NavDestination 的 `onBackPressed` 挂点；全局拦截会误伤详情/搜索返回）。当前用「关闭/取消」显式退出，返回键行为留 M8 统一处理 |
| 9 | 遗留 `user` 组无存储名 | 种子里的「我的关注」组 `name` 为空（显示名走 i18n），因此用户可以再建一个同名「我的关注」组，两个 Tab 文案相同。属 CC-2.4 命名解耦的既有建模限制，M7 不修（修需给系统保留组加"显示名占位"或让 i18n 进数据层） |

---

## 6. 复核补充（2026-11-13 收尾自检）

| # | 检查 | 结论 |
|---|---|---|
| 1 | 添加页切换关键词后勾选态是否回填 | ✅ 实测：选 601398 → 换词选 600888 → 回到 601398，行内 ✓ 与「加入自选（2）」都在（`@Monitor('vm.search.resultVersion')` + `reapplyPicks` 生效） |
| 2 | 添加页打开期间断网/恢复 | ✅ 补 `@Monitor('hub.state')` → `AddWatchlistVM.refresh()`，页内离线提示与容量实时跟随 |
| 3 | 自选页 Store 变更重入 | ✅ 补 `pendingSync` 标志：同步进行中再收到变更（如建组）会在本轮结束后补一次，避免分组不出现 |
| 4 | 遗留扫描 | ✅ 无 `WatchlistRaw` / `watchlistProvider().load()` / `coming_soon_add_watchlist` / `ADD_WATCHLIST` 占位残留；无 `TODO/FIXME/console.log` |
| 5 | 全量 UiTest（M6+M7 同跑） | ✅ 14/14（M6 8 + M7 6） |
| 6 | 分组持久化（杀进程冷启） | ✅ 新建 `ptest` → `aa force-stop` → 冷启 → 分组管理里仍有 `ptest`；设备磁盘 `xiaoyang_stock_v1` 的 groups 含该组、items 带 `pending` 字段（验证后已删除该测试组） |
| 7 | 提交「全部已存在」的兜底 | ✅ 新增 `add_all_existed`：竞态导致只返回 existed 时提示「所选股票已在自选中」并关页，不再出现「已加入 0 只」 |
| 8 | 独立评审 2 个 P1 | ✅ ①撤销多只顺序：`restore` 改为按移除逆序插回；②撤销 50 上限：`restore` 逐条判上限并丢弃超额项。两条均已由 `WatchlistStore` 单测直接覆盖（`restore_keeps_original_order` / `restore_does_not_exceed_limit`），无需真机复验 |
| 9 | 撤销顺序真机复验 | ✅ 45 只无排序 → 编辑态勾第 2~4 行（平安银行/宁德时代/中芯国际）→ 移出 → 撤销 → 三行顺序与移出前一致（`25` 移出前 / `26` 撤销后；修复前会倒序） |



