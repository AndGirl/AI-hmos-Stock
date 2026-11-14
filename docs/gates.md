# 工程门禁（Gates）

> 对应设计 §3.1.10（分层校验 R-01~R-09）、§6.3（占位文案校验）、§6.6（工程红线与 CI 门禁）。
> 目标：让「分层被破坏 / 占位文案漂移 / 硬编码」在提交前失败，而不是靠评审记忆。

## 1. 八道门禁

| # | 门禁 | 脚本 | 运行位置 | 说明 |
|---|---|---|---|---|
| 1 | 版本一致性 | `scripts/check-version.mjs` | CI + 本地 | V-01~V-03，10 模块（含 M11 新增 `account`）与 `app.json5` 一致 |
| 2 | 占位文案静态单测 | `scripts/check-coming-soon.mjs` | CI + 本地 | 2 条 `coming_soon_*` 文案格式、禁用词、标点/emoji；代码禁止硬编码 |
| 3 | 分层架构红线 | `scripts/check-architecture.mjs` | CI + 本地 | R-01~R-09，静态扫描 import 与关键字 |
| 4 | 契约完整性 | `scripts/check-contracts.mjs` | CI + 本地 | K-01~K-04：Provider 接口有实现、必需方法齐备、装配点覆盖、M9 可选成员不得写成必需 |
| 5 | 深色 token 完整性 | `scripts/check-dark-tokens.mjs` | CI + 本地 | D-01~D-03：base/dark 键集合一致、`TokenRegistry` 全量、`.ets` 无颜色字面量 |
| 6 | 对比度与红绿可辨 | `scripts/check-contrast.mjs` | CI + 本地 | C-01~C-04：dark 文本 ≥4.5、非文本 ≥3、涨跌 ΔE ≥20 且亮度差 ≥15%；base 只报告 |
| 7 | 合规（M13） | `scripts/check-compliance.mjs` | CI + 本地 | X-01~X-05：SDK 清单双向一致 + 表格版本自洽、权限白名单与清单一致、调试入口 DEBUG 守卫、隐私文案齐备非空、策略版本与文档一致 |
| 8 | CodeLinter | `devecocli check lint` | 本地 `scripts/gate.ps1` | 依赖 HarmonyOS SDK，GitHub 托管 runner 无 SDK |

一键本地执行：

```powershell
cd D:\deepseek_harness_work\xiaoyang-stock
powershell -ExecutionPolicy Bypass -File scripts/gate.ps1
```

单独执行：

```powershell
node scripts/check-version.mjs
node scripts/check-coming-soon.mjs
node scripts/check-architecture.mjs
node scripts/check-contracts.mjs
node scripts/check-dark-tokens.mjs
node scripts/check-contrast.mjs
node scripts/check-compliance.mjs
devecocli check lint
```

退出码：`0` 通过；`1` 失败（并打印文件:行号）。

## 2. 占位文案门禁校验项

- 键集合必须恰好是：`coming_soon_home`、`coming_soon_news`；
- 每条值以「下阶段开放」结尾；
- 禁止变体：`敬请期待` / `即将上线` / `暂未开放` / `Coming` / `~` / `!` / `！`；
- 禁止版本号片段：`v1.x` / `一期` / `二期` / `阶段一~三`；
- 禁止末尾标点、emoji、首尾空白、换行；
- `ComingSoonText.ets` 必须引用全部 2 条资源；
- `.ets` 源码不得出现硬编码的「…下阶段开放」字符串（注释先剔除）。

> M6 起 `coming_soon_market` 已随行情 Tab 落地移除（CK-4）；M7 移除 `coming_soon_add_watchlist`（添加页落地）；**M8 移除 `coming_soon_card_view`**（卡片视图落地），门禁期望键收敛为 **2 条**（home/news）。

## 3. 分层架构红线（R-01~R-09）

| 规则 | 脚本判定 |
|---|---|
| R-01 | `products` → `products` 的跨模块 import 直接失败 |
| R-02 | `features` → `products` 失败 |
| R-03 | `commons` → `features` / `products` 失败 |
| R-04 | 仅允许 `watchlist->detail`、`detail->trade`、`pk->detail`、`search->detail`，其余 feature 横向依赖失败 |
| R-05 | 除 `commons/data/src/main/ets/DataServices.ets` 外出现 `new Mock*` / `new Real*` 失败 |
| R-06 | 跨模块必须用包名（桶导出）；`模块名/深路径`、跨模块相对路径、HAR 缺少根 `Index.ets` 或 `main != Index.ets` 均失败 |
| R-07 | feature 的 `view/` import `repository/` 或 `commons_data` 失败 |
| R-08 | feature 的 `viewmodel/` import `view/`，或出现 `promptAction` / `AlertDialog` / `bindSheet` 失败 |
| R-09 | 模块依赖图存在环失败 |

**新增 feature 横向依赖**：必须同时改三处，否则 R-04 会拦：

1. 设计文档 §3.1.2 依赖图；
2. 设计文档 §3.1.10 白名单；
3. `scripts/check-architecture.mjs` 的 `ALLOWED_FEATURE_EDGES`。

## 3.1 契约完整性门禁（K-01~K-04，M9 起）

| 规则 | 脚本判定 |
|---|---|
| K-01 | 每个 `*Provider` 接口至少有一个实现类 |
| K-02 | 每个实现类实现该接口的全部**必需**成员（带 `?` 的可选成员可缺省） |
| K-03 | 每个 `*Provider` 接口必须出现在装配点 `commons/data/src/main/ets/DataServices.ets` |
| K-04 | 契约 v1.1 的可选成员（`onError` / `capabilities` / `chartPage` / `seq` / `retryAfterMs` / `browse` / `listOrders` / `cancelOrder` / `openAccount` / `positionOf`）必须是 `?` 形式 |

背景：M9 起 Provider 走「只加不改」，最容易出的是「接口加了方法、某个实现忘了写」或「把可选成员写成必需」——这两类编译期都不一定报错，所以在提交前静态拦一次。扫描范围只到 `commons/data/src/main/ets`（**不含测试**，测试里的桩实现不受约束）。

负向探针（已验证，验证后还原）：

- 把 `SearchProvider.browse?` 的 `?` 去掉 → **K-04 FAIL**（`必须是可选成员`）；
- K-02 在脚本首次落地时曾真实失败 7 项（`async` 方法漏匹配），修复后 PASS——说明「实现缺方法」确实会被拦。

## 3.2 深色 token 门禁（D-01~D-03）

| 规则 | 脚本判定 |
|---|---|
| D-01 | `commons/ui` 与 `products/entry` 各自的 `base` / `dark` color 键集合完全一致（不允许多键/漏键） |
| D-02 | `TokenRegistry` 引用的每个 `app.color.*` 必须同时存在于 base 与 dark |
| D-03 | `.ets` 源码（剔除注释后）不得出现 `#RGB` / `#RRGGBB` / `#AARRGGBB` 颜色字面量，也不得用 `Color.White` 等系统色做业务语义 |

负向探针：dark 漏 `color_accent_soft`、或任一 `.ets` 写 `#FFFFFF`，脚本必须失败。

## 3.3 对比度门禁（C-01~C-04）

| 规则 | 脚本判定 |
|---|---|
| C-01 | dark 文本对 ≥4.5:1（`text_primary/secondary`、`price_*`、`accent`、`error`、`tag_*`、`chart_avg`、`orderbook_title_text`、`text_on_accent/accent_fill`、`accent/accent_soft`） |
| C-02 | dark 状态类非文本对 ≥3:1（`accent`、`accent_fill`、`price_up/down` 对 `bg_page/bg_surface`） |
| C-03 | base 与 dark 的涨跌红绿 ΔE76 ≥20 且相对亮度差 ≥15% |
| C-04 | base 浅色只输出「阶段一现状报告」，不失败；需要收紧时设 `STRICT_LIGHT=1` |

半透明色（`bar_shadow`/`scrim`/`transparent`）与 `disabled_text`、装饰性 `divider*` 不参与断言，详见 [phase2-tokens.md](phase2-tokens.md)。

## 3.4 合规门禁（X-01~X-05，M13 起）

| 规则 | 脚本判定 |
|---|---|
| X-01 | SDK 清单 [phase2-sdk-list.md](phase2-sdk-list.md) 的 `<!-- SDK-LIST -->` 块与所有 `oh-package.json5` 的**第三方运行期依赖**双向一致（名称 + 版本）；**表格里「名称内联版本」与「版本列」也必须自洽**。本地模块按 `LOCAL_MODULES` 名字白名单识别（新增本地 HAR 要登记，vendored 三方 HAR 不得借 `file:` 逃逸） |
| X-02 | 所有 `module.json5` 的 `requestPermissions` ⊆ 白名单（当前策略：**0 权限**），且与清单 `<!-- PERMISSIONS -->` 块双向一致 |
| X-03 | 引用 `BuildProfile.DEBUG` 的文件必须有 `if (!DEBUG)` / `if (DEBUG)` 守卫；出现 `showActionMenu` 且带调试语义（中文「调试」或英文 `debug`）但没引用 DEBUG = 漏守卫（release 会露出） |
| X-04 | 隐私政策/同意必需文案键齐备且**非空**（`privacy_title`、`privacy_consent_title`、`consent_agree/reject`、`privacy_revoke`、`privacy_section_1..8_title/body` 等） |
| X-05 | `PRIVACY_POLICY_VERSION` / `PRIVACY_POLICY_DATE`（`commons/basic` 常量）与 [privacy-policy.md](privacy-policy.md) 抬头的「版本 / 更新日期」一致（策略改版时两边同步） |

负向探针（2026-11-14 修复轮后重跑，验证后已还原）：

- 清单版本列写 `9.9.9`（名称内联仍 `3.0.31`）→ **X-01 FAIL**（表格版本不自洽）；
- 删掉清单里的 `@ohos/mpchart` 一行 → **X-01 FAIL**（实际依赖未登记）；
- 业务菜单文件加一行 `// debug action menu probe` → **X-03 FAIL**（调试语义无守卫）；
- 把 `WatchlistPage` 的 `if (!DEBUG)` 删掉 → **X-03 FAIL**；
- 删 `consent_agree` 文案键或把值置空 → **X-04 FAIL**；
- 把常量改成 `1.1`（文档仍 `1.0`）→ **X-05 FAIL**。

> 注：X-03 不把业务动作菜单（如详情「更多」`DetailActions.ets`）误判为调试入口——它没有 DEBUG 也不含调试语义；反之，纯英文 `debug` 标签的调试菜单会被拦住。

## 4. CI 现状与边界

- `.github/workflows/gate.yml` 在 push/PR 时只跑第 1~7 道（纯 Node，无 SDK）。
- 第 8 道 CodeLinter、构建、Hypium 需要 DevEco Studio / Command Line Tools，当前在本地 `scripts/gate.ps1` 执行；后续可接带 SDK 的自托管 runner。
- 目前没有 Hypium 单元测试工程；占位文案用静态脚本承担「防漂移」职责。M1 起如需纯函数单测（几何/排序/校验），再在 `features/*/src/test` 建 Hypium local test，并纳入 `gate.ps1`。
  - M6 已在 `features/search/src/test` 落地第一组纯函数单测（`MatchRules` / `SearchQuery`），当前通过 `devecocli local test` 手动执行，尚未并入 `gate.ps1`。
  - **M9 在 `commons/data/src/test` 增加行情通道单测**（涨跌停/帧序号/帧校验/限流降级/缓存规则/契约），运行：`hvigor test -p module=commons_data -p coverage=false`。

## 5. 自检记录

已用临时探针验证门禁可失败（验证后删除）：

- 在 `features/watchlist/.../view` 放 `import { PkPage } from 'pk'` → R-04 失败；
- 同文件 `import { AppServices } from 'entry'` → R-02 失败；
- 同文件 `new MockQuoteProvider()` → R-05 失败；
- 同文件 `import ... from 'commons_data'` → R-07 失败；
- 同文件 `import ... from 'commons_ui/theme/TokenRegistry'` → R-06 失败；
- `viewmodel` 出现 `promptAction` 与 `import '../view/...'` → R-08 失败；
- `commons/data` 反向 import `watchlist` → R-03 失败；
- 源码硬编码「添加自选下阶段开放」→ 文案门禁失败。
