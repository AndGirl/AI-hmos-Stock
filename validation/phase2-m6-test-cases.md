# 阶段二 · M6 搜索验收用例（AC-87~93）

> 版本：v1.0 · 编制：2026-11-13 · 对应：阶段二开发计划 §6.2 / §7.2
> 代码：`features/search`（新增 HAR）、`commons/data`（Search 契约 / 本地索引 / 存储）、`products/entry`（路由 / 深链 / 行情 Tab）
> 证据目录：截图 `shots/phase2/m6/`、单测 `features/search/src/test/`、性能 `docs/perf/phase2-m6.md`（待真机补）

---

## 0. 结论状态

| 手段 | 状态 | 说明 |
|---|---|---|
| 构建（9 模块） | ✅ | `devecocli build` 绿 |
| 静态门禁 | ✅ | `scripts/gate.ps1` 4 步全绿（版本 / 占位文案 / 架构 / lint） |
| 纯函数单测 | ✅ | `MatchRules` 18 例 + `SearchQuery` 8 例，**26/26** 通过 |
| 六态截图（真机） | ✅ | `shots/phase2/m6/01~07*.png`（Mate 60 Pro 真机，1260×2720） |
| 结果 / 就地加自选截图 | ✅ | `03-results.png` / `08-add-watchlist.png`（日志 `add_outcome added=1`） |
| 空词列表 + 分页 + 到底提示 | ✅ | 真机 `09-browse-list.png`（含 8vp 分隔块）/ `10-browse-all-loaded.png`（80/80 到底提示）/ `11-browse-refreshing.png`（下拉刷新中）/ `12-browse-sticky.png`（全部股票分组头吸顶） |
| 跨页同步（自选 ↔ 行情） | ✅ | 真机：搜索加自选后自选页计数 46→47 并出现新行 `13-watchlist-added-from-search.png`；「已添加」再点撤出后自选页 46→45、行消失 `16~18`；两页价格随 QuoteBus 实时变化 |
| lg/xl 分栏 | ✅（布局断言） | 阔折叠 2584×1828：结果列 0~982px = 38%，右栏 `DetailContent(pane)`；抓图受模拟器黑屏限制 |
| P90 ≤500ms | ✅（Mock） | 10 次冷查询：P90=124ms（`docs/perf/phase2-m6.md`） |
| UiTest（`@kit.TestKit` + hypium） | ✅ | `SearchUiTest` **8 例**，真机 8/8 通过（分页/到底提示以真机手动+截图为准，见 §5-9） |

### 0.1 证据文件

| 文件 | 内容 |
|---|---|
| `shots/phase2/m6/01-initial.png` | 初始态（热搜两列 × 5 行，前三名角标） |
| `shots/phase2/m6/02-searching.png` | 搜索中（顶部 2vp 进度条，不整页骨架） |
| `shots/phase2/m6/03-results.png` | 结果分段 + 命中高亮 + 价格/涨跌幅 |
| `shots/phase2/m6/04-empty.png` | 无结果 + 3 个建议词 |
| `shots/phase2/m6/05-error.png` | 失败 + 单一重试 |
| `shots/phase2/m6/06-offline.png` | 离线 banner（28vp）+ GlobalBanner + 本地结果 |
| `shots/phase2/m6/07-rate-limited.png` | 429 + 「1 秒后可重试」倒计时 |
| `shots/phase2/m6/08-add-watchlist.png` | 行尾「＋」加自选成功（行变「已添加」） |
| `shots/phase2/m6/09-browse-list.png` | 空词初始态：历史 + 热搜 + 全部股票（共 80 只，首屏 20 条） |
| `shots/phase2/m6/10-browse-all-loaded.png` | 上拉加载完 80 只：底部「股票已全部展示（80/80 只），没有更多数据」 |
| `shots/phase2/m6/11-browse-refreshing.png` | 下拉刷新进行中（顶部刷新指示器 + 列表保留） |
| `shots/phase2/m6/12-browse-sticky.png` | 「全部股票」分组头吸顶（历史/热搜滚走，股票行在其下滚动） |
| `shots/phase2/m6/13-watchlist-added-from-search.png` | 搜索页加自选后切到自选页：新行出现、分组计数 +1 |
| `shots/phase2/m6/14-multi-add-sync.png` | 连续添加 3 只后自选页计数 48，三行依次出现（验证监听不被首轮同步摘掉） |
| `shots/phase2/m6/15-toggle-add.png` | 「已添加」可点：行尾为可点「已添加」（撤出自选入口） |
| `shots/phase2/m6/16-watchlist-after-add.png` | 撤出前：自选页「全部 46」，新行茅台镇酒业滚动定位并高亮 |
| `shots/phase2/m6/17-toggle-removed.png` | 点「已添加」后行尾恢复「＋」，停留搜索页（不误入详情） |
| `shots/phase2/m6/18-watchlist-after-remove.png` | 撤出后：自选页「全部 45」，茅台镇酒业行消失、滚动位置保留 |
| `shots/phase2/m6/19-add-toast.jpeg` | 加自选 Toast「已加入自选」 |
| `shots/phase2/m6/20-remove-toast.jpeg` | 撤出 Toast「已从自选移除」+ 行尾恢复「＋」 |
| `docs/perf/phase2-m6.md` | P90、采样明细、分栏布局断言、复现命令 |

> Mock 数据口径：自选迁移 45 只（50 上限内留 5 个空位，用于 AC-91/96 的就地加自选与部分成功验证；`MAX_ITEMS=50` 逻辑不变）。首次安装或清除应用数据后生效。

---

## 1. AC 用例

### AC-87 三入口 + 防抖 + seq + 分栏

| # | 步骤 | 期望 | 手段 |
|---|---|---|---|
| 87-1 | 行情 Tab → 顶部搜索条输入「600519」 | 首字符即发起；300ms 内连输只发 1 次请求（埋点 `search_query` 计数 = 1） | 人工 + 日志 |
| 87-2 | 快速输入 A 再改成 B（B 先返回） | 旧响应被丢弃，界面只显示 B 的结果 | 单元（`seq` 用例）+ 人工 |
| 87-3 | 自选空态点「搜索添加」 | push 全屏搜索页（`mode='push'`），返回回到自选 | 人工 |
| 87-4 | `hdc shell aa start -U "zixuangu://search?q=600519"`（冷/热启动） | 进入全屏搜索页且已带 term；q 超 20 字被截断；q 缺省回初始态 | 人工 + 单测（解析口径见 `DeepLinkParser`） |
| 87-5 | sm/md 宽度 | 单列结果，无分栏 | 人工 |
| 87-6 | lg / xl（1440vp 平板） | 左结果 38% + 右 `DetailContent(pane)` 62%；点结果行只换右栏 code，不 push | 人工（AC-87 按 1440vp 全量形态核） |

### AC-88 六（七）级匹配

| # | 步骤 | 期望 | 手段 |
|---|---|---|---|
| 88-1 | 搜 `600519` | L0 命中且排第一 | 单测 `level_L0_code_exact` |
| 88-2 | 搜 `贵州` | L2（贵州茅台）整体排在 L3 之前 | 单测 `level_L2_before_L3_same_term` |
| 88-3 | 搜 `茅台镇` | `茅台镇酒业` 命中（L2 名称前缀）；L3「名称包含非前缀」由单测样本 `中华茅台镇酒业` 覆盖（Mock 主数据未放同名干扰项） | 单测（规则）+ 人工（Mock 数据） |
| 88-4 | 同层多条 | 按成交额降序，成交额相同按 code 升序 | 单测 `compare_level_then_amount_then_code` |
| 88-5 | 停牌/退市标的参与搜索 | 降权（层内靠后）但**不隐藏**；行置灰 55% + 标签 | 人工（Mock `600000` 浦发银行停牌） |
| 88-6 | 全角输入 `６００５１９` | 与 `600519` 结果一致 | 单测 `normalize_fullwidth_to_halfwidth` |
| 88-7 | 板块词 `白酒` | 板块段出现「白酒」，股票段不被「板块=白酒」灌满（L6 只对板块条生效） | 单测 `level_L6_sector_only_for_sector_entry` |

### AC-89 分段 / 高亮 / 复制 / 读屏

| # | 步骤 | 期望 | 手段 |
|---|---|---|---|
| 89-1 | 输入命中多个类型 | 股票 / 指数 / 板块三段；每段标题带计数；各段默认 20 条，超出出现「展开」 | 人工 |
| 89-2 | 长按命中名称复制 | 得到完整原文（`copyOption(LocalDevice)`），无高亮标记 | 人工 |
| 89-3 | 读屏聚焦结果行 | 朗读「名称、代码、最新价、涨跌幅、已添加/停牌/新股」，不念高亮标记 | 人工听测（T-08 顺带关闭） |
| 89-4 | 高亮区间越界/多出现 | 不越界，多次出现全部高亮 | 单测 `hit_ranges_code_and_name` / `hit_ranges_pinyin_and_bounds` |

### AC-90 历史与热搜

| # | 步骤 | 期望 | 手段 |
|---|---|---|---|
| 90-1 | 连续提交 12 个不同词 | 历史保留最近 10 条、MRU 去重 | 人工 + 存储断言 |
| 90-2 | 长按某条历史 | 单删 | 人工 |
| 90-3 | 点「清空」 | 弹二次确认；确认后清空，取消无变化 | 人工 |
| 90-4 | 杀进程重启 | 历史仍在（`search_history_v1`） | 人工 |
| 90-5 | 断网 + debug 菜单注入「热搜失败」 | 热搜整块消失，无错误提示、不占位 | 人工（debug 菜单） |

### AC-91 结果操作

| # | 步骤 | 期望 | 手段 |
|---|---|---|---|
| 91-1 | 点股票行（sm/md） | push 详情并带 `from=search&rank=n` | 人工 + 路由参数断言 |
| 91-2 | 点行尾「＋」 | 就地加入自选，行变「已添加」 | 人工 |
| 91-3 | 已在自选的标的 | 首次展示即「已添加」（读自选仓储，不单独缓存） | 人工（`600519` 等已在自选种子内） |
| 91-4 | 点指数行 | 无动作（不 push、无「＋」） | 人工 |
| 91-5 | 点板块行 | 以板块名二次搜索，无「＋」 | 人工 |
| 91-6 | 点「已添加」（**需求变更 2026-11-13**） | 直接撤出自选、无二次确认；Toast「已从自选移除」；行尾回「＋」且可再加回；不触发详情跳转 | 人工 + UiTest |

### AC-92 六态

| 状态 | 注入方式 | 期望 | 手段 |
|---|---|---|---|
| 初始 | 进入搜索页（空输入） | 历史 + 热搜 + **全部股票列表**（共 80 只，首屏 20 条，行含＋/已添加） | 人工 + UiTest |
| 搜索中 | 输入后立即观察 | 保留上一帧结果 + 顶部 2vp 进度条，不整页骨架 | 人工 |
| 无结果 | 搜 `zzzz` | 图标位 + 「没有找到相关股票」+ 3 个热搜建议词（点击即搜），无第二按钮 | 人工 |
| 失败 | 长按搜索条 → 调试 → 「失败（fail）」 | 「搜索失败，请重试」+ 单一重试 | 人工 |
| 离线 | 调试 → 「离线」 | 顶部 28vp「当前离线，仅显示本地结果」，结果照常展示不置灰 | 人工 |
| 429 | 调试 → 「429 限流」 | 「操作频繁，请稍后重试」+ 3s 倒计时，结束后可重试 | 人工 |

**空词列表（M6 追加：下拉刷新 / 上拉分页 / 到底提示）**

| # | 步骤 | 期望 | 手段 |
|---|---|---|---|
| 92-L1 | 清空输入框 | 展示「全部股票 / 共 80 只」，首屏 20 条，默认按成交额降序（同为成交额按 code 升序）；**历史/热搜/全部股票同一列表整体滚动**，热门搜索与「全部股票」之间为 **8vp 浅灰分隔块**；「全部股票」分组头滚动到顶后**吸顶** | 人工 + UiTest |
| 92-L2 | 下拉列表 | 顶部刷新指示器出现，刷新后保留已加载条数、价格/涨跌更新；失败静默保留旧数据 | 人工（`11-browse-refreshing.png`） |
| 92-L3 | 连续上拉到底 | 每次到底加载下一页 20 条（共 4 页），底部短暂「加载中…」 | 人工 |
| 92-L4 | 80 条全部加载完 | 底部常驻「股票已全部展示（80/80 只），没有更多数据」，14fp Medium、`textPrimary`、高 48vp | 人工（`10-browse-all-loaded.png`） |
| 92-L5 | 续页失败（debug 注入 fail） | 保留已加载行，底部「加载失败，点击重试」，点击可续页 | 人工 |
| 92-L6 | 行交互 | 与结果行一致：点进详情、＋加自选、已添加可点按撤出（2026-11-13 变更） | 人工 |

> 调试入口仅 `BuildProfile.DEBUG=true` 可达；release 包长按无菜单。
> 实现说明：`SearchVM.state` 在六态之外多一个内部值 `results`（正常有结果面），六态验收口径不受影响。
> 「搜索中」用调试菜单「慢请求（4s）」注入后截图（`02-searching.png`），正常网络下该态约 120ms。

### AC-93 性能与缓存

| # | 步骤 | 期望 | 手段 |
|---|---|---|---|
| 93-1 | 输入到结果 | P90 ≤500ms（本地索引构建 ≤120ms）；实测 Mock P90=124ms | `PerfMeter` + 埋点 `search_cost` |
| 93-2 | 同 term 5min 内重复搜 | 不发请求（命中 LRU） | 单测 `cache_hit_skips_second_request` |
| 93-3 | 全角/空格变体命中同一缓存 | 归一化 key 生效 | 单测 `cache_key_is_normalized` |

---

## 2. 跨页同步（自选 ↔ 行情，M6 追加）

> 背景：M6 先落 `WatchlistStore`（写）但自选页仍读 Mock Provider（读），导致「加了不出现 / 已添加不一致 / 价格不同步」。本轮统一为 Store 单一数据源 + QuoteBus 实时行情。

| # | 步骤 | 期望 | 结果 |
|---|---|---|---|
| S1 | 自选页首次进入 | 集合 = `watchlist_v1`（首次迁移 45 只），分组计数 45 | ✅ 真机 |
| S2 | 行情（搜索空词）点某只未添加股票「＋」→ 切「自选」 | 分组计数 +1（46→47），新行出现并滚动/高亮 | ✅ `13-watchlist-added-from-search.png` |
| S6 | 行情页**连续添加 3 只**（长江电力 / 海尔智家 / 中国中车）→ 切「自选」 | 分组计数 45→**48**，三行都在，无需手动 reload | ✅ `14-multi-add-sync.png` |
| S3 | 同一股票在两页观察 10s | 两页价格/涨跌幅随同一路 `QuoteBus` 更新（1s 合窗），不再一页实时一页快照 | ✅ 真机（长江电力 192.00→191.75 等） |
| S4 | 搜索页「已添加」态 | 与自选页同一 Store：已在自选显示「已添加」 | ✅ 真机 |
| S7 | 行情页对**已添加**行再点一次 → 切「自选」 | 行尾立刻回「＋」、Toast「已从自选移除」；自选页计数 -1、该行消失、滚动位置不被重置 | ✅ `15~18`（46→45） |
| S8 | 撤出后再点「＋」 | 可重新加回，自选页计数 +1（排在末尾） | ✅ 真机 |
| S5 | 断线/恢复 | QuoteBus 断线冻结、恢复继续刷新；两页一致 | 沿用阶段一 CC-7.6，未单独复测 |

> 验证方式：P0/P1 主链路已真机手动走查；跨页 UiTest 尝试过「加自选→切 Tab→断言行」，受 hypium 单用例 15s 上限与键盘遮挡 / 切 Tab 稳定性影响，未纳入自动化套件（8 例保持全绿），后续可拆成短用例再补。

---

## 3. 埋点事件（M6）

| 事件 | 触发 | 参数（只含枚举/序号/数值，不含明文输入） |
|---|---|---|
| `search_query` | 每次发起查询（防抖后/Enter） | `len`（词长）、`seq`、`offline` |
| `search_result` | 查询返回（含失败） | `count`、`cost`（ms）、`offline`；失败时 `state=reason` |
| `search_click` | 点股票行进详情 | `code`、`rank`、`kind` |
| `search_add_watchlist` | 行尾「＋」加自选成功 | `code`、`rank` |
| `search_remove_watchlist` | 点「已添加」撤出自选成功 | `code`、`rank` |

> 出口仍是 `AnalyticsHub → LogSink → hilog`（T-06：不接三方 SDK），可用 `hilog | grep Analytics` 查看。

---

## 4. 自动化 UI 测试（ohosTest）

| 项 | 内容 |
|---|---|
| 位置 | `products/entry/src/ohosTest/ets/test/Search.ui.test.ets`（`List.test.ets` 注册） |
| 框架 | `@ohos/hypium` + `@kit.TestKit`（Driver / ON / Component） |
| 套件名 | `SearchUiTest`（8 例） |
| 用例 | ① AC87 行情 Tab 入口；② AC87 后输词生效、旧结果不残留；③ AC92 无结果态；④ AC92 空词列表可见（全部股票 / 共 80 只）；⑤ AC90 热搜点击写历史；⑥ AC91 进详情并返回；⑦ AC91 行尾「＋」加自选；⑧ AC91 点「已添加」撤出自选（回到「＋」） |
| 前置 | 设备解锁且亮屏；`hdc -t <serial> shell param set persist.ace.testmode.enabled 1`；仅连接 1 台设备 |
| 命令 | `hvigorw onDeviceTest -p module=entry -p coverage=false -p scope=SearchUiTest` |
| 结果 | `products/entry/.test/default/intermediates/ohosTest/coverage_data/test_result.txt`：`Tests run: 8, Failure: 0, Error: 0, Pass: 8`（2026-11-13） |

> 实现要点：进入详情用「行内价格区坐标点击」（行点击挂在 Row 上，点文本中心不保证命中）；详情断言用内容「今开」而非 NavDestination 标题栏（标题栏不暴露为 Text 节点）。
> 分页/到底提示未放进 UiTest：滑动动画 + 逐页加载会把单条用例推到 15s 超时（hypium 仅 3 参数、无 per-case timeout），改由真机手动 + 截图覆盖（`10-browse-all-loaded.png`）。

---

## 5. 已知偏差与后续

1. **指数/板块行交互**：按确认口径「指数行不跳转、板块行二次搜索」，AC-91 只对股票行生效。
2. **分栏阈值**：G-1 要求 lg/xl 分栏，全局 `BreakpointService.isSplit` 只在 xl 生效；搜索页内用局部判定 `lg||xl`，未改全局（避免自选 xl 回归）。
3. **「自选设置」入口**：详情/搜索右栏动作栏的 `watchlist` 动作在 M7 前仍走 `ComingSoonText.ADD_WATCHLIST` 占位（仅剩这一处使用）。
4. **自选 Mock 迁移 45 只**：为 AC-91/96 留出 5 个空位；`watchlist_v1` 首次迁移生效（重装/清数据后可见），50 上限判定不变。
5. **分栏截图**：阔折叠模拟器帧缓冲抓图为全黑（`ui screenshot` 与 `snapshot_display` 均黑屏），改用 `ui layout` 坐标断言（982/2584 = 38%）；真机平板截图列为 M6 收口补齐项。
6. **UiTest**：已建 `products/entry/src/ohosTest`（`SearchUiTest` 8 例），真机 8/8；仍需设备解锁、`persist.ace.testmode.enabled=1`、且只连一台设备（hdc 多目标会报 `need connect-key`）。
7. **性能数据**：已归档 `docs/perf/phase2-m6.md`（Mock P90=124ms）；`PerfMeter` 帧率与真实通道性能留 M9/M13。
8. **调试注入**：新增「慢请求（4s）」仅 debug 可达，用于截取搜索中态；release 由 `BuildProfile.DEBUG=false` 关闭。
9. **空词「全部股票」列表（M6 计划外追加）**：初始态由「历史 + 热搜」扩为「历史 + 热搜 + 80 只股票分页列表」，三块作为**同一列表整体滚动**；热门搜索与「全部股票」之间为 **8vp 浅灰分隔块**（`color_disabled_bg`）；「全部股票」用 `ListItemGroup` + `List.sticky(StickyStyle.Header)` 实现**吸顶**。下拉刷新保留已加载条数、上拉每页 20、到底提示 `股票已全部展示（80/80 只），没有更多数据`（14fp Medium `textPrimary`）。契约加可选 `SearchProvider.browse`；`SearchRules.browseBounds` 有 4 例单测。UiTest 只覆盖「列表可见 + 共 80 只」，分页/刷新/吸顶以真机手动 + 截图为准（原因见 §4 注）。
10. **跨页同步（P0/P1，M6 计划外追加）**：自选集合改以 `WatchlistStore` 为唯一来源（`WatchlistRepository` 不再读 Mock Provider）；`WatchlistVM` 订阅 Store 变更，搜索页加自选后自选页**增量刷新 + 滚动定位 + 320ms 高亮**（M7-4 提前）；`SearchVM` 对「全部股票」与结果行统一订阅 `QuoteBus`（只股票，指数/板块不订阅），两页价格同源。首迁移仍 45 只（留 5 空位）。跨页 UiTest 未纳入（见 §2 注）。
    - 修复记录（2026-11-13）：连续添加多只时只有第一只同步。根因：`WatchlistVM.subscribe()` 复用了 `dispose()`，而 `dispose()` 会 `detachStore()` → 首次同步后 Store 监听被摘掉。修法：拆出 `disposeQuotes()`，`subscribe()` 只清行情订阅；`dispose()` 才解绑 Store；`resume()`（Tab 切回自选）补一次 Store 重读。S6 已验证 3 只连续添加全部同步。
11. **「已添加」可点撤出（需求变更 2026-11-13）**：原口径为「已添加后不可重复点」，现改为**再点一次撤出自选**（与「＋」互逆），为 M7 的自选删除提前打底。实现：`WatchlistStore` 新增 `remove(codes)`（幂等，`missing` 不报错），变更通知由 `string[]` 升为 `WatchlistChange{added, removed}`，自选页只对 `added` 做定位高亮、对 `removed` 只重建（不切分组、不重置滚动）；`SearchVM.toggleWatch` 统一入口，同一 code 在「结果页 / 全部股票」两处行对象一起翻转；`SearchRowView` 的「已添加」加 52×32vp 可点区与读屏文案「已添加，点按移除自选」。偏差：撤出后重新加回会排到自选末尾（Store 按加入顺序），不做原位恢复；无二次确认（可逆操作）。S7/S8 与 UiTest 第 8 例已覆盖。

