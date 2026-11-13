# 工程门禁（Gates）

> 对应设计 §3.1.10（分层校验 R-01~R-09）、§6.3（占位文案校验）、§6.6（工程红线与 CI 门禁）。
> 目标：让「分层被破坏 / 占位文案漂移 / 硬编码」在提交前失败，而不是靠评审记忆。

## 1. 三道门禁

| # | 门禁 | 脚本 | 运行位置 | 说明 |
|---|---|---|---|---|
| 1 | 占位文案静态单测 | `scripts/check-coming-soon.mjs` | CI + 本地 | 5 条 `coming_soon_*` 文案格式、禁用词、版本号、标点/emoji；代码禁止硬编码 |
| 2 | 分层架构红线 | `scripts/check-architecture.mjs` | CI + 本地 | R-01~R-09，静态扫描 import 与关键字 |
| 3 | CodeLinter | `devecocli check lint` | 本地 `scripts/gate.ps1` | 依赖 HarmonyOS SDK，GitHub 托管 runner 无 SDK |

一键本地执行：

```powershell
cd D:\deepseek_harness_work\xiaoyang-stock
powershell -ExecutionPolicy Bypass -File scripts/gate.ps1
```

单独执行：

```powershell
node scripts/check-coming-soon.mjs
node scripts/check-architecture.mjs
devecocli check lint
```

退出码：`0` 通过；`1` 失败（并打印文件:行号）。

## 2. 占位文案门禁校验项

- 键集合必须恰好是：`coming_soon_add_watchlist`、`coming_soon_card_view`、`coming_soon_home`、`coming_soon_news`；
- 每条值以「下阶段开放」结尾；
- 禁止变体：`敬请期待` / `即将上线` / `暂未开放` / `Coming` / `~` / `!` / `！`；
- 禁止版本号片段：`v1.x` / `一期` / `二期` / `阶段一~三`；
- 禁止末尾标点、emoji、首尾空白、换行；
- `ComingSoonText.ets` 必须引用全部 4 条资源；
- `.ets` 源码不得出现硬编码的「…下阶段开放」字符串（注释先剔除）。

> M6 起 `coming_soon_market` 已随行情 Tab 落地移除（CK-4）；`add_watchlist` / `card_view` 分别随 M7、M8 移除。

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

## 4. CI 现状与边界

- `.github/workflows/gate.yml` 在 push/PR 时只跑第 1、2 道（纯 Node，无 SDK）。
- 第 3 道 CodeLinter、构建、Hypium 需要 DevEco Studio / Command Line Tools，当前在本地 `scripts/gate.ps1` 执行；后续可接带 SDK 的自托管 runner。
- 目前没有 Hypium 单元测试工程；占位文案用静态脚本承担「防漂移」职责。M1 起如需纯函数单测（几何/排序/校验），再在 `features/*/src/test` 建 Hypium local test，并纳入 `gate.ps1`。
  - M6 已在 `features/search/src/test` 落地第一组纯函数单测（`MatchRules` / `SearchQuery`），当前通过 `devecocli local test` 手动执行，尚未并入 `gate.ps1`。

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
