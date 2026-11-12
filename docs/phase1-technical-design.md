# 自选股 · 阶段一技术设计说明书

> 版本：v1.2 · 编制：2026-11-11 · 状态：**评审稿（可进入 V0）**
> 适用工程：HarmonyOS 新工程「自选股」阶段一（M0–M5）
> 依据：[阶段一需求基线](../requirements/00-phase1-baseline.md)（下称「基线」）、[横切规范](../requirements/fr-common-spec.md)（下称「CC 规范」）、[FR-02](../requirements/fr02-subreq.md)、[FR-06](../requirements/fr06-subreq.md)、[FR-07](../requirements/fr07-subreq.md)、[FR-08](../requirements/fr08-subreq.md)、[华为《分层架构设计》](https://developer.huawei.com/consumer/cn/doc/doccenter-architecture/bpta-layered-architecture-design)、`design/` 16 张设计稿
> 效力：**本文是实现层设计，不新增、不修改需求**。与基线冲突时以基线为准；本文 §11 登记了 10 项需回写基线的差异，未回写前按本文默认值实现并标注。
> 读者：客户端开发、测试、设计对接人、项目管理

---

## 摘要

- **工程形态**：按华为官方**三层架构**落地——`products/entry`（Entry HAP）+ `features/*`（4 个 HAR）+ `commons/*`（3 个 HAR），单向依赖 products → features → commons；feature 内部再按 MVVM 分 view / viewmodel / repository。状态管理 V2，三个 Provider 全 Mock 但契约与真实同形（§3.1）。
- **最难的 11 列冻结表**：采用「横向 `Scroll` 内含竖向 `List` + 名称列 `translate` 跟随」，每帧只 1 次状态更新，虚拟化保留在 `List`；V0 必须先验证帧率与对齐（R2）。
- **详情**：壳 / 内容分离（`DetailPage` / `DetailContent`），图表经 `ChartEngine` 适配层，三方库不可用时退 Canvas，业务零改动。
- **交易**：单容器两层单渲染、门禁优先级固定、`clientOrderId` 幂等、2s 超时进入「结果未知」且不自动重发。
- **多窗**：`WindowHost` 抽象先落应用内 `PaneHost`；订阅按 code 合并、焦点 1s / 非焦点 5s；降级链固定为「关非焦点窗 → 降频 → 单窗」。
- **计划**：60 人日（50 + 20% 缓冲），关键路径 V0 → M2 → M4；10 项需求侧差异已登记（§11），**Q1 / Q3 / Q9 建议评审会拍板**。

---

## 0. 文档说明

### 0.1 目的

把「基线 + 6 份 FR + 16 张设计稿」翻译成**可开工、可分工、可验收**的工程方案，回答四个问题：

1. 工程长什么样（分层、目录、依赖、路由、状态）；
2. 每个模块怎么实现（关键结构、算法、时序、边界）；
3. 每个数字怎么保证（性能预算、验收映射、测试手段）；
4. 哪里会翻车（风险、待确认、V0 必须先验的 4 件事）。

### 0.2 依据与效力

| 层级 | 文件 | 与本文的关系 |
|---|---|---|
| 需求基线 | [00-phase1-baseline.md](../requirements/00-phase1-baseline.md) | 范围、决策、裁决、验收口径的**唯一来源** |
| 横切规范 | [fr-common-spec.md](../requirements/fr-common-spec.md) | CC-1~CC-7 直接约束实现，优先级最高 |
| 子需求 | [fr02](../requirements/fr02-subreq.md)、[fr06](../requirements/fr06-subreq.md)、[fr07](../requirements/fr07-subreq.md)、[fr08](../requirements/fr08-subreq.md) | 逐条落地的输入 |
| 设计稿 | `design/*.png` | 视觉与信息架构参考；**稿内数值一律视为占位**（FR-06 Q2、FR-07 Q2、FR-08 Q7） |
| 架构基线 | [分层架构设计（华为开发者文档）](https://developer.huawei.com/consumer/cn/doc/doccenter-architecture/bpta-layered-architecture-design) | products / features / commons 三层划分、产物类型与依赖规则（§3.1） |
| 本文 | 本文件 | 实现方案；与基线冲突以基线为准 |

### 0.3 术语

| 术语 | 含义 |
|---|---|
| 壳 / 内容 | 详情页的两种承载：`DetailPage`（路由、返回、沉浸式）与 `DetailContent`（纯内容组件） |
| 冻结表 | 11 列表格：表头竖向冻结 + 名称列横向冻结 + 数据区横滑 |
| 窗格（pane） | 应用内并排的详情实例；本期多窗宿主先落窗格 |
| 行情帧 | 一次 1s 合并后的一批 `QuotePatch` |
| 门禁（Gate） | 交易入口/提交的前置判定链 |
| 档位 | `fontScale` 的 1.0 / 1.3 / 1.45 三档 |

### 0.4 与需求文档的关系

- 本文**不重新定义 AC**，只把 AC 映射到实现点与验证手段（§8.2）。
- 基线 §12.1 的 4 项开工前核验，本文在 §2.4 给出可执行判据。
- 本文提出的 10 处需求侧不一致，统一登记在 §11，**开发按默认值推进，不阻塞**。

### 0.5 阅读指引

| 角色 | 先读 |
|---|---|
| 开发 | §2 → §3.1（分层）→ §3 → §4 → §5（按分工读 M0–M5） |
| 测试 | §1.3 → §8 → §5 各模块的「状态机 / 矩阵」小节 |
| 产品 / 设计 | §1 → §11，再看 §5.2.9、§5.3.2、§5.4.1 的形态表 |

全文骨架：§1 范围 · §2 技术基线 · §3 架构 · §4 数据层 · §5 模块方案 · §6 横切 · §7 性能 · §8 验收 · §9 计划 · §10 风险 · §11 差异登记 · §12 附录。

---

## 1. 范围与目标

### 1.1 交付范围

| 模块 | 需求内容（基线 §1.1） | 技术落点 | 主要技术风险 |
|---|---|---|---|
| M0 应用外壳 | 四 Tab、路由栈、深链、沉浸式、主题 token | 单 `Navigation` + `TabShell`、`BreakpointService`、`TokenRegistry`、`ComingSoon` | 折叠/展开与 Tab 状态保持 |
| M1 自选列表 | 11 列 + 名称列冻结横滑、指数条、分组 Tab、列头排序、4 形态 | `FrozenTable`（本文 §5.2）、`QuoteBus` 单行刷新、`SortStore` | **R2：ArkUI 最难的交互** |
| M2 个股详情 | 报价头、指标、资讯条、8 周期、图表、盘口与明细、内容 Tab、动作栏、紧凑版 | `DetailContent` 壳内容分离、`ChartEngine` 适配层、`CompactSwitcher` | R3/R4：图表库与三窗性能 |
| M3 买入委托 | 入口、编辑层、确认层、校验、三态结果、关闭矩阵 | `TradeVM` 状态机、`bindSheet`/居中模态、`clientOrderId` 幂等 | 超时「结果未知」的语义正确 |
| M4 多窗比价 | 2/3 窗、换股、同步周期、降频、降级、恢复 | `WindowHost`/`PaneHost`、`SubscriptionRegistry`、`PkSessionVM` | 三窗帧率与内存 |
| M5 全局质量 | 断线状态机、字号、无障碍、埋点、性能 | `ConnectionHub`、`FontScaleService`、`Analytics`、`PerfProbe` | 跨页一致性（唯一 banner / 统一置灰） |

**人日口径**（基线 §9）：V0 3 + M0 4.5 + M1 11 + M2 13 + M3 6 + M4 8 + M5 6 = 51.5，加 8.5 缓冲 **合计 60 人日**（M0 的 1.5 人日为三层模块创建与依赖配置，从原缓冲中支出，总人日不变），双人 6–7 周。

### 1.2 明确不做（技术视角）

| 不做 | 技术含义 |
|---|---|
| 真实行情 / 真实交易网关 | 三个 Provider 全部 Mock，但**接口与真实契约同形**（DEC-09-03、DEC-07-01），二期只换实现 |
| 搜索 / 添加自选 / 卡片视图 | 只保留入口占位（DEC-09-01）；**不建**搜索服务、不做匹配与防抖 |
| 开户、KYC、委托列表、持仓 | 交易只到「单笔委托回执」，不做列表与撤单 |
| 深色模式、横屏重排、多账户 | 颜色全走 token、字段预留 `accountId`，但不出色板、不做横屏布局 |
| 资讯/社区/研报内容 | 只做容器与占位 |

### 1.3 质量目标（可度量）

| 维度 | 目标 | 验收出处 |
|---|---|---|
| 首屏 | 骨架 ≤300ms，内容 ≤1s | CC-1.2 / AC-01 |
| 列表滚动 | 50 行 ≥55fps，无白块，单行刷新 | CC-1.2 / AC-02 |
| 详情 | 头部 ≤500ms（P90）、图表首帧 ≤800ms、切周期 ≤300ms（有缓存） | FR-06.14 / AC-65 |
| 交易 | 弹窗打开 ≤200ms、层切换 ≤150ms、提交 2s 内必有反馈 | FR-07.14 / AC-76 |
| 多窗 | 3 窗 ≥50fps、切窗 ≤300ms、冷启恢复 ≤800ms | FR-08.12 / AC-86 |
| 端到端可用 | 断线 5s 内恢复、唯一 banner、置灰 55% | CC-7.6 / AC-52 |
| 可测性 | 每条 AC 可落到 UiTest 断言或人工 checklist | 基线 §8.2 |

### 1.4 技术约束（来自决策，不可协商）

| 决策 | 技术含义 |
|---|---|
| DEC-10-01 | `compileSdkVersion` / `targetSdkVersion` = **20** |
| DEC-10-03 | `compatibleSdkVersion` = **20**，不保留 5.x 兼容分支、不写 `canIUse` 降级 |
| 基线 §12 | ArkTS 严格模式、状态管理 **V2**、ohpm、hvigor |
| DEC-09-02 | 平板**坚持 11 列横滑**，不按宽度减列 |
| DEC-09-03 | 行情/账户/交易全部 Mock，契约按真实定义 |
| DEC-10-02 | 占位文案单一模板「{对象}下阶段开放」，集中管理、禁止变体 |

---

## 2. 技术基线

### 2.1 SDK 与工具链

| 项 | 取值 | 说明 |
|---|---|---|
| `compileSdkVersion` / `targetSdkVersion` | 20 | 与基线一致 |
| `compatibleSdkVersion` | 20 | 只覆盖 HarmonyOS 6.x |
| `runtimeOS` | HarmonyOS | — |
| 语言 | ArkTS（严格模式） | 禁 `any`/`unknown`、禁解构、显式类型参数 |
| 状态管理 | ArkUI **V2** | `@ComponentV2`/`@ObservedV2` 体系，不保留 V1 备选 |
| 构建 | DevEco Studio（匹配 SDK 20）+ hvigor | 具体版本以本地安装为准，V0 记录到 `docs/toolchain.md` |
| 包管理 | ohpm | 三方依赖锁版本，写入 `oh-package.json5` |

**工程形态**

| 项 | 取值 |
|---|---|
| 包形态 | 三层模块：`products/entry`（Entry HAP）+ `features/watchlist·detail·trade·pk`（HAR）+ `commons/ui·basic·data`（HAR）；单产品定制（手机/平板自适应），不做多 Entry（ADR-01） |
| 设备形态 | `deviceTypes: ["phone", "tablet"]`；2in1 随二期横屏一并评估 |
| **分层架构设计** | 官方三层 **products → features → commons** 单向依赖（[华为《分层架构设计》](https://developer.huawei.com/consumer/cn/doc/doccenter-architecture/bpta-layered-architecture-design)）；feature 内再分 view / viewmodel / repository；模块划分、依赖白名单、装配点与校验见 **§3.1** |
| 状态管理 | 仅 V2：`@ComponentV2` / `@ObservedV2`，V1 装饰器不进入工程（§2.2） |

> 「分层」与「MVVM」的对应关系：官方三层的 **features = MVVM 的载体**，其中 **Model = Repository（feature 内）+ Provider（commons/data）**，**ViewModel = viewmodel/**，**View = view/**；products 与两个装配点不属于 MVVM 三元，但必须显式约束（否则装配逻辑会长进页面里）。

### 2.2 状态管理 V2 使用规约

V2 只解决一个问题：**让「哪块数据变了」精确到组件**。为了 50 行列表的单行刷新与三窗独立实例，必须把观测粒度压到最小。

| 场景 | 用 | 不用 | 原因 |
|---|---|---|---|
| 组件内 UI 状态（展开、选中、偏移） | `@Local` | `@State` | V1 装饰器在 `@ComponentV2` 内编译报错 |
| 父 → 子只读数据 | `@Param` | `@Prop` | `@Param` 只读，避免子组件改父数据 |
| 子 → 父事件 | `@Event` | 回调属性裸传 | 与 `@Param` 配套，语义清晰 |
| 跨层级注入 | `@Provider` / `@Consumer` | 层层透传 | 详情内容组件在页/窗格/窗口三种壳内复用 |
| 派生值（能否提交、表格宽度） | `@Computed` | `get` + 手动同步 | `get` 不参与观测（断点派生状态会失效） |
| 跨页共享单例 | `AppStorageV2.connect(Class, key, factory)` | 自建全局变量 | 同 key 共享同一实例 |
| 需跨进程存活（PK 组合） | `PersistenceV2.connect(...)` | `preferences` 手工序列化 | 只存最后 1 组（DEC-08-05） |
| 高频行情字段 | `@ObservedV2` + `@Trace` 的**逐标的**对象 | 整个列表一个大对象 | 单行刷新；整对象替换会全表重绘 |

**硬性红线**（评审直接打回）：

1. 同一文件内禁止 V1/V2 混用；`@Component` 与 `@ComponentV2` 不跨层传状态变量。
2. `@Param` 禁止赋值；`@Local` 禁止由外部初始化。
3. 行情对象禁止整体替换（`this.quote = new Quote()`），只改 `@Trace` 字段。
4. 页面/组件内禁止自建重连/轮询定时器（CC-7.5），统一走 `ConnectionHub` 与 `QuoteBus`。
5. `@ObservedV2` 类的构造函数内只做字段初始化，启动逻辑放 `init()`（构造期尚未完成代理）。

### 2.3 三方依赖准入

| 依赖 | 用途 | 准入条件 | 失败退路 |
|---|---|---|---|
| `@ohos/mpchart` | K 线、分时、十字光标、缩放 | **V0 必验**：API 20 可编译、8 周期可渲染、长按十字光标可用、三窗同时存在不崩、包体增量可接受 | `ChartEngine` 换 Canvas 自绘（+3~5 人日，FR-06 D35） |

依赖策略：**只允许经过适配层**（`ChartEngine`、`StorageAdapter`）。业务代码不得直接 import 三方库符号，保证二期可换。

### 2.4 开工前 4 项核验（可执行化）

| # | 核验 | 判据（可执行） | 不通过处理 |
|---|---|---|---|
| 1 | SDK 20 工具链一致 | `hvigorw --version`、DevEco 关于页、`$OHOS_SDK` 的 API 版本三处均为 20；空工程 `assembleHap` 成功 | 升级工具链后再开工 |
| 2 | 折叠真机 API ≥ 20 | `hdc shell param get const.ohos.apiversion` ≥ 20；安装空包成功 | 换设备/升级（基线已确认完成） |
| 3 | 图表库在 API 20 可用 | 独立 Demo：8 周期 × 3 实例同屏，首帧 ≤800ms、长按十字光标、双指缩放均正常 | 换库或 Canvas 自绘 |
| 4 | V2 + Navigation 行为符合预期 | 最小样例：`@ComponentV2` 页面 push/pop 后 `@Local` 保持、`@Param` 更新、返回栈正确 | 调整状态边界后再开工 |

> 4 项全部通过才进入 M0；核验结论写入 `docs/v0-spike-report.md`（含设备型号、系统版本、帧率截图）。

### 2.5 API 使用与兼容规则

- min = 20：20 以内能力直接用，不写 `canIUse`。
- 未来提高 compileSdk 而不提 min 时，新增能力必须 `canIUse` 判断（基线 §12.2）。
- 三方库若最高只验证到较低 API，需在 V0 报告登记「已验证最高 API」，每次升 SDK 小版本回归**11 列横滑、多窗、图表**三项。
- 废弃接口（如全局 `px2vp`、全局 `router`）一律不用：窗口尺寸用 `UIContext.px2vp`，路由用 `Navigation`。

### 2.6 工程初始化步骤（开工第一天）

1. DevEco 新建 Stage 工程（API 20，ArkTS），保留 `products/entry` 作为唯一 Entry HAP。
2. 新建 4 个 Feature HAR（`watchlist` / `detail` / `trade` / `pk`）与 3 个 Common HAR（`ui` / `basic` / `data`），类型选 Static Library。
3. 配置 `build-profile.json5`（SDK 20）与各模块 `oh-package.json5` 依赖（§3.1.3）；验证「未声明依赖即编译失败」。
4. 配置 `module.json5`：`deviceTypes`、`abilities` 的 `exported`、深链 `skills`（`scheme: zixuangu`）。
5. 落地 `products/entry` 的 pages / shell / router / di 骨架，以及 `commons/ui` 的 token 与通用组件。
6. 接入 `@ohos/mpchart`（ohpm），在 `commons/data/chart` 写 `ChartEngine` 空实现与 Demo，供 V0 验证。
7. 建立三条 CI 门禁：`lint`、`ut`（单元测试）、`redline`（§6.6 / 附录 C 红线 + 模块依赖规则 R-01~R-09）。

---

## 3. 总体架构

### 3.1 分层架构设计（工程形态）

> **设计依据**：华为开发者文档《分层架构设计》——[bpta-layered-architecture-design](https://developer.huawei.com/consumer/cn/doc/doccenter-architecture/bpta-layered-architecture-design)。官方模型把应用分为 **产品定制层（products）/ 基础特性层（features）/ 公共能力层（commons）**，以 Entry HAP、Feature HAP、HAR/HSP 三类产物落地，核心约束是**单向依赖**。本节先落官方三层，再落到「模块内 MVVM」。

#### 3.1.1 官方三层模型

| 层 | 职责（官方口径） | 编译产物 | 依赖约束 |
|---|---|---|---|
| 产品定制层 **products** | 面向不同设备形态做功能与特性集成，是应用主入口 | 每个子目录编译为一个 **Entry HAP** | 可依赖 features / commons；**产品之间不可横向调用** |
| 基础特性层 **features** | 相对独立的功能 UI 与业务逻辑，高内聚、低耦合、可定制 | **HAR / HSP**；需单独部署的编 **Feature HAP** | 可横向调用其他 feature 与 commons；**不可反向依赖 products** |
| 公共能力层 **commons** | 公共基础能力：公共 UI 组件、数据管理、外部交互、工具库 | **HAR / HSP**（一个或多个） | **只被上层依赖，不可反向依赖** |

四条硬规则（本文全部落地并进 CI）：

1. **单向依赖**：products → features → commons，箭头不可逆。
2. **products 之间禁止横向调用**：各自独立编译、独立入口。
3. **features 之间允许横向**，但本期只放行白名单（§3.1.2 依赖图）。
4. **commons 之间可同层依赖**（ui → basic、data → basic），不得回指上层。

#### 3.1.2 本项目模块划分

| 模块 | 类型 | 内容 | 依赖 |
|---|---|---|---|
| `products/entry` | Entry HAP | 四 Tab 壳、详情/比价页壳、路由注册、深链、页面装配 `AppServices`、设备形态适配 | `features/*`、`commons/ui`、`commons/basic`、`commons/data` |
| `features/watchlist` | HAR | 11 列冻结表、指数条、分组 Tab、排序 | `features/detail`、`commons/*` |
| `features/detail` | HAR | `DetailContent`（页 / 右栏 / 紧凑）、图表区、盘口、内容 Tab | `features/trade`、`commons/*` |
| `features/trade` | HAR | 买入弹窗两层、校验、提交与结果 | `commons/*` |
| `features/pk` | HAR | 多窗宿主、叠放布局、焦点与换股、订阅编排 | `features/detail`、`commons/*` |
| `commons/ui` | HAR | 设计系统组件：Skeleton、StateView、TagChip、Banner、通用卡片 | `commons/basic` |
| `commons/basic` | HAR | i18n、常量、格式化、Guard、日志、埋点接口、`RouteService` 接口 | — |
| `commons/data` | HAR | 三 Provider 契约与 Mock、`QuoteBus`/`QuoteCache`/`SubscriptionRegistry`、`ConnectionHub`、`SortStore`、图表适配、实体（共享内核） | `commons/basic` |

**特性依赖图**（features 横向白名单）：

```
watchlist ──► detail ──► trade
                 ▲
                 └──── pk
```

允许这三条的理由：watchlist 在 xl 分栏直接复用 `DetailContent`；detail 的动作栏要打开买入弹窗；pk 的每个窗就是一实例 `DetailContent`。**新增横向依赖必须同时修改本节与 §3.1.10 的白名单**，否则 CI 拦下。

#### 3.1.3 模块产物与依赖声明

- `products/entry`：`module.json5` 提供 `deviceTypes`、`pages`、`abilities`；HAP 只做装配与设备适配，不含业务。
- `features/*`、`commons/*`：依赖写在各自 `oh-package.json5`，未声明的 import 直接编译失败。
- 模块名与目录对应：`commons_data` ↔ `commons/data`、`commons_ui` ↔ `commons/ui`、`commons_basic` ↔ `commons/basic`（HAR 模块名不允许路径分隔符）。

```json
// features/watchlist/oh-package.json5
{
  "name": "watchlist",
  "version": "1.0.0",
  "dependencies": {
    "detail": "file:../detail",
    "commons_data": "file:../../commons/data",
    "commons_ui": "file:../../commons/ui",
    "commons_basic": "file:../../commons/basic"
  }
}
```

```json
// products/entry/oh-package.json5
{
  "dependencies": {
    "watchlist": "file:../../features/watchlist",
    "detail": "file:../../features/detail",
    "trade": "file:../../features/trade",
    "pk": "file:../../features/pk",
    "commons_ui": "file:../../commons/ui",
    "commons_basic": "file:../../commons/basic",
    "commons_data": "file:../../commons/data"
  }
}
```

> 官方三层比"目录约定"强的地方就在这里：**边界由构建系统保证**，不靠自觉。代价是模块创建与依赖声明的一次性成本（M0 +1.5 人日，从缓冲支出，总人日仍 60）。

#### 3.1.4 模块内分层（MVVM 纵向切片）

三层解决"模块边界"，模块内部还要解决"代码边界"。features 内每个特性按 MVVM 再分三层，其下是 commons 提供的数据与基建：

```
features/<name>/view        L4 视图层：只读 VM，@Event 上行
features/<name>/viewmodel   L3 视图模型：@ObservedV2 + @Trace
features/<name>/repository  L2 仓储：组合 commons/data，输出实体
commons/data                L1 数据/服务：契约、Mock、订阅、缓存、图表适配
commons/{ui,basic}          L0 基建：token/组件/i18n/常量/格式化
products/entry             页面装配：路由注册与工厂，只见装配不见业务
```

**两条读法**：

- 纵向是**编译期依赖**（import 方向），只允许向下，下层不得反向 `import` 上层；
- 横向是**运行期数据流**（推送下行、意图上行），只经相邻层，不跨层直达。

#### 3.1.5 各层职责与出入口

| 层 | 目录（模块内） | 职责 | 对外形态 | 明确禁止 |
|---|---|---|---|---|
| L4 视图 | `products/entry/pages`、`features/*/view` | 页面壳（路由、生命周期、沉浸式、安全区）、组件渲染、手势、动画、无障碍、toast/弹窗等 UI 副作用 | `@ComponentV2` + `@Param` 入 / `@Event` 出 | 发请求、`import commons/data`、写业务规则、`new Provider()`、起业务定时器 |
| L3 视图模型 | `features/*/viewmodel` | UI 状态（`@ObservedV2` + `@Trace`）、命令、派生值、错误码 → 文案映射、UI 侧节流 | 类实例：`@Trace` 字段 + 方法 | `import` 组件或 UI 副作用 API（弹窗/toast/路由）、直接读写 `preferences`、持有 Provider；`ResourceStr`（i18n 文案）允许 |
| L2 领域/仓储 | `features/*/repository`（实体在 `commons/data/entities`） | 仓储组合、领域不变量（INV-1~5）、纯算法（排序比较器、表格几何、校验规则）、缓存策略 | 纯函数 / 类方法，出入参均为实体或值 | `import` VM/UI、路由、弹窗、读写 `@Trace` |
| L1 数据/服务 | `commons/data/{provider,store,chart}` | 契约实现（Mock / Real）、订阅推送与合并、降频、连接状态机、持久化适配、三方图表适配 | `interface` + `Promise` / 回调 | `import` 仓储、VM、视图；持有 UI 状态（宽度、选中） |
| L0 基建 | `commons/ui`、`commons/basic` | 颜色/尺寸 token、i18n、常量、格式化、无业务通用组件（Skeleton、TagChip）、Guard | 常量 / 纯函数 / 无状态组件 | 业务判断、网络、任何上层 import |
| 数据装配 | `commons/data/DataServices.ets` | 组装三个 Provider 与 Store（Mock / Real 单点切换） | 单例 | 业务规则、渲染、UI 状态 |
| 页面装配 | `products/entry/di/AppServices.ets` | 路由注册、页面与 VM 工厂 | 单例 | 业务规则、数据访问、渲染 |

> 判据：**「这段代码放哪层」**先问「它知道 UI 吗」——知道但只是状态，放 L3；知道且要画出来，放 L4；不知道 UI 但知道业务，放 L2；连业务都不知道、只对接通道，放 L1。再问「它属于哪个特性」——能独立成一块业务的，进 `features/<name>`；跨特性的稳定能力，才进 `commons`。

#### 3.1.6 允许依赖矩阵

| 依赖方 ↓ / 被依赖 → | L0 `commons` | `entities` | L2 仓储 | L1 Provider | L3 VM | L4 视图 |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| L0 `commons/{ui,basic}` | — | ✗ | ✗ | ✗ | ✗ | ✗ |
| `commons/data/entities` | ✓ | — | ✗ | ✗ | ✗ | ✗ |
| L1 Provider / Store | ✓ | ✓ | ✗ | — | ✗ | ✗ |
| L2 Repository（各 feature） | ✓ | ✓ | — | ✓（接口） | ✗ | ✗ |
| L3 ViewModel（各 feature） | ✓ | ✓ | ✓ | ✗ | — | ✗ |
| L4 View（各 feature） | ✓ | ✗ | ✗ | ✗ | ✓ | — |
| 数据装配 `DataServices` | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ |
| 页面装配 `AppServices` | ✓ | ✓ | ✓（工厂） | ✓ | ✓（工厂） | ✓（注册页面） |

> 本矩阵约束「模块内 + 模块间」的**类型级**依赖；模块级白名单（哪两个 feature 可以互相引用）另见 §3.1.2 与 §3.1.10。

**仅有的两处例外**（评审时必须能说清理由）：

1. `commons/data/entities` 作为**共享内核**被 L1 与各 feature 的 L2 同时引用：只放纯数据类型（`QuoteSnapshot`、`OrderDraft` 等），**不含方法、不含逻辑**；一旦给它加行为，就退化为反向依赖。
2. 两个装配点允许看见比业务代码更多的层：`DataServices` 可见 L1 全部；`AppServices` 可见 features 与 commons。它们只做 `new` 与注册，**不允许**出现 if 判断业务、不允许渲染。

#### 3.1.7 数据流

```
报价推送（下行）
Provider.onPatch ──► QuoteBus.flush（1s 合窗）──► QuoteCache.apply（改 @Trace）
                                                        │
                                                        ▼
                        ViewModel 读 @Trace ──► View 局部重绘（只该行/该块）

用户操作（上行）
Button.onClick ──► @Event ──► VM.command() ──► Repository ──► Provider
                                                   │
                                    OrderResult ───┘
                                        │
                                   VM 写 @Trace ──► View 更新按钮三态/结果
```

| 约束 | 说明 |
|---|---|
| 下行只带数据 | 回调里不出现组件引用、不出现 `animateTo` |
| 上行只带意图 | `@Event` 只传业务参数（code、step、字段值），不传 UI 上下文 |
| 不跨层调用 | L4 不得直接调 L1；L2 不得反向通知 L3，用返回值/监听接口 |
| 异步不出层 | Provider 的 `Promise` 由 Repository 归一化为实体，VM 只面对已归一化的结果 |
| 错误逐层翻译 | L1 `QuoteError` → L2 失败结果 → L3 UI 态（`DetailUiState`）→ L4 文案与重试按钮 |

#### 3.1.8 状态归属

| 状态 | 归属层 | 示例 | 理由 |
|---|---|---|---|
| 服务端数据与缓存 | L1 / L2 | `QuoteCache`、快照、图表序列 LRU | 生命周期长于页面，多页共享 |
| 领域不变量 | L2 | 分组派生、空值恒末尾的比较器、表格几何 | 可单测，与渲染无关 |
| UI 状态 | L3 | 展开态、`step`、loading、选中行、横滑偏移 | 跨组件共享，需跟随页面存活 |
| 瞬时视图状态 | L4 `@Local` | 手势进度、动画值、焦点态 | 只影响单个组件，不需跨页 |
| 全局只读环境 | L0 单例 | 断点、安全区、字号档位 | 进程级、只读消费 |
| 全局会话 | L1 单例 | `ConnectionHub`、`SortStore`、`PkSession` | 跨页共享且带业务含义 |

> 反例：把 `scrollOffset` 塞进 `AppStorageV2`（全局可观测 → 每帧全表重算）；把 `canSubmit` 存成字段（应由 `@Computed` 派生）。

#### 3.1.9 契约与两个装配点

- 契约（`QuoteProvider` / `AccountService` / `TradeGateway`）定义在 `commons/data`，**实现也在 `commons/data`**；feature 的仓储只依赖接口，Mock / Real 切换只发生在 `commons/data/provider/index.ets` 一处。
- 装配拆成两点，原因就是依赖方向：
  - **数据装配** `commons/data/DataServices.ets`：feature 都能依赖 commons，因此数据装配必须放在这一层；
  - **页面装配** `products/entry/di/AppServices.ets`：路由注册与页面工厂只能放在产品定制层（features 不可依赖 products）。
- feature 内**禁止** `new Mock*`，也禁止自己持有 Provider；仓储从 `DataServices` 取依赖（或由 AppServices 构造时注入）。
- 跨 feature 跳转走 `commons/basic/router/RouteService` 接口：接口与注册表在 commons/basic，实现在 `products/entry/router`；feature 只调接口，不 import 对方页面。

```ts
// commons/data/DataServices.ets —— 数据装配点（唯一 new Provider 的地方）
export class DataServices {
  private static instance: DataServices | null = null;

  readonly quote: QuoteProvider;
  readonly account: AccountService;
  readonly gateway: TradeGateway;
  readonly quotes: QuoteCache;
  readonly subs: SubscriptionRegistry;
  readonly connection: ConnectionHub;

  private constructor() {
    this.quote = new MockQuoteProvider();
    this.account = new MockAccountService();
    this.gateway = new MockTradeGateway();
    this.quotes = new QuoteCache(this.quote);
    this.subs = new SubscriptionRegistry(this.quote);
    this.connection = new ConnectionHub(this.quote);
  }

  static get(): DataServices {
    if (DataServices.instance === null) {
      DataServices.instance = new DataServices();
    }
    return DataServices.instance;
  }
}
```

```ts
// products/entry/di/AppServices.ets —— 页面装配点（路由与页面工厂）
export class AppServices {
  private static instance: AppServices | null = null;
  private readonly stack: NavPathStack = new NavPathStack();

  static get(): AppServices {
    if (AppServices.instance === null) {
      AppServices.instance = new AppServices();
    }
    return AppServices.instance;
  }

  pathStack(): NavPathStack { return this.stack; }

  // 注册 detail / pk / notFound 的 NavDestination 构建器（引用各 feature 导出的页面组件）
  registerBuilders(): void { /* ... */ }
}
```

> 用「私有构造 + `get()`」而不是静态字段互相引用：ArkTS 的静态初始化顺序不保证，静态字段互引会拿到 `undefined`。

#### 3.1.10 分层校验

**CI 红线**（与 §6.6 合并执行）：

| 检查 | 规则 |
|---|---|
| R-01 | `products/entry` 下若出现多个产品子目录，彼此不得 import（本期只有一个，防未来） |
| R-02 | `features/*` 不得 import `products/*` |
| R-03 | `commons/*` 不得 import `features/*`、`products/*` |
| R-04 | `features/*` 之间的 import 只允许白名单：watchlist→detail、detail→trade、pk→detail |
| R-05 | 除 `commons/data/DataServices.ets` 外，`new Mock*` / `new Real*` 一律禁止 |
| R-06 | 跨模块只允许 `import { X } from 'detail'`（走对方 `Index.ets` 桶导出），禁止深路径 |
| R-07 | feature 内 `view/` 不得 import `repository/`、`commons/data`；只吃 VM 暴露的类型 |
| R-08 | feature 内 `viewmodel/` 不得 import `view/`、不得出现 `promptAction` / `AlertDialog` / `bindSheet` |
| R-09 | 循环依赖：构建期必失败 + 评审先拦（`features` 白名单本身无环） |

**反模式清单**（评审逐条对照）：

1. 页面里 `new MockQuoteProvider()` —— 绕过 `DataServices`，二期换真实实现要改页面。
2. VM 里 `promptAction.showToast()` —— UI 副作用应在 L4，由 `@Event` 通知。
3. 仓储里 `pathStack.push()` —— 领域层反向依赖路由。
4. Provider 里读断点/字号 —— 通道层持有 UI 状态。
5. 把 `@ObservedV2` 实体直接传给 View —— 跳过 VM，视图与数据层耦合。
6. L2 返回中文文案 —— 应返回错误码，文案在 L3（VM 组装）或 L4（组件渲染）解析（占位文案同理）。
7. feature 之间 `import` 未登记在 §3.1.2 依赖图 —— 隐式耦合，CI R-04 拦截。
8. commons 里出现业务判断（如「停牌不可交易」）—— 业务规则应回 feature 的 L2/L3。

#### 3.1.11 模块到分层的落点

| 模块 | 主要落点（模块 + 层） | 说明 |
|---|---|---|
| M0 外壳 | `products/entry`（壳、路由、装配）+ `commons/ui`（token/组件） | 几乎没有业务逻辑，重点是模块骨架、装配与安全区 |
| M1 列表 | `features/watchlist`（L4 冻结表 / L3 行 VM / L2 几何排序）+ `commons/data`（QuoteBus） | 四层都动，是分层最容易破的地方 |
| M2 详情 | `features/detail`（L4 内容组件 / L3 DetailVM、ChartVM）+ `commons/data/chart` | 壳内容分离即 L4 内部的分层 |
| M3 交易 | `features/trade`（L3 TradeVM / L2 校验规则）+ `commons/data`（Gateway） | 校验是纯函数，必须放 L2 才能单测 |
| M4 多窗 | `features/pk`（L3 PkSessionVM / L4 布局）+ `commons/data`（SubscriptionRegistry） | 编排在 L3，订阅合并在 L1 |
| M5 质量 | `commons/basic`（字号、埋点接口）+ `commons/data`（连接）+ 各 feature L4（无障碍、toast） | 横切项要避免散落各层 |

#### 3.1.12 演进路径

| 触发 | 动作 | 对现有代码的影响 |
|---|---|---|
| 新增平板专用布局 / PC 入口 | 新增 `products/tablet` 第二个 Entry HAP，复用全部 features | products 之间独立，features 零改动 |
| 某特性需独立部署 / 动态加载 | 该 feature 由 HAR 升级为 Feature HAP | 只改打包类型与依赖声明 |
| 多团队并行、包体变大 | commons 由 HAR 升级为 HSP（同进程共享实例） | 注意 HSP 单例语义与版本约束 |
| 单特性过重 | 在 features 内再拆子特性 | 需同步更新 §3.1.2 依赖图与 §3.1.10 白名单 |
| 二期接真实行情/交易 | 替换 `commons/data/provider` 实现，`DataServices` 换一行 | features 与 UI 零改动（契约不变） |

### 3.2 运行时结构

```
EntryAbility
 ├─ onCreate: 解析深链 → 写入 LaunchParam
 ├─ onWindowStageCreate:
 │    loadContent(Index) 回调内
 │      ├─ mainWindow = getMainWindowSync()
 │      ├─ BreakpointService.init(uiContext)   // 首值 + windowSizeChange
 │      ├─ SafeAreaService.init(mainWindow)    // avoidArea + 变化监听
 │      └─ FontScaleService.init(config)
 └─ onWindowStageDestroy: off 全部监听

Index（AppRoot）
 └─ Navigation(pathStack, mode: Stack)
      ├─ navBar: TabShell（Tabs 四页 + 悬浮底栏）
      └─ NavDestination: DetailPage / PkPage（本期仅此两个）
```

### 3.3 工程目录（三层模块）

```
products/
└── entry/                                   # Entry HAP（产品定制层）
    ├── oh-package.json5                     # 依赖 features/* 与 commons/*
    └── src/main/
        ├── module.json5                     # deviceTypes / pages / abilities / skills
        ├── resources/                       # 产品级资源（图标、启动图、限定词目录）
        └── ets/
            ├── entryability/EntryAbility.ets
            ├── pages/
            │   ├── Index.ets                # AppRoot：Navigation + TabShell
            │   ├── HomePage.ets             # 占位 Tab：首页
            │   ├── NewsPage.ets             # 占位 Tab：最新资讯
            │   ├── MarketPage.ets           # 占位 Tab：行情
            │   ├── DetailPage.ets           # 详情壳（sm/md/lg 全屏）
            │   ├── PkPage.ets               # 多窗比价壳（PaneHost）
            │   └── NotFoundPage.ets         # 404 态
            ├── shell/                       # TabShell、FloatingTabBar、GlobalBanner、PlaceholderPage
            ├── router/                      # AppRouter、DeepLinkParser、LaunchParam
            └── di/AppServices.ets           # 页面装配点（路由注册、页面工厂）

features/
├── watchlist/                               # HAR
│   ├── oh-package.json5                     # 依赖 detail、commons_*
│   └── src/main/ets/
│       ├── view/                            # WatchlistPage、FrozenTable、NameColumn、QuoteCells、GroupTabs、IndexStrip
│       ├── viewmodel/                       # WatchlistVM、WatchRowVM、IndexStripVM
│       ├── repository/WatchlistRepository.ets
│       └── Index.ets                        # 桶导出（唯一对外入口）
├── detail/                                  # HAR
│   └── src/main/ets/
│       ├── view/                            # DetailContent、QuoteHeader、MetricPanel、ChartArea、
│       │                                    # OrderBookPanel、TickList、ContentTabs、ActionBar
│       ├── viewmodel/                       # DetailVM、ChartVM、OrderBookVM、MetricVM
│       ├── repository/DetailRepository.ets
│       └── Index.ets
├── trade/                                   # HAR
│   └── src/main/ets/
│       ├── view/                            # TradeSheet、EditLayer、ConfirmLayer、StepField
│       ├── viewmodel/                       # TradeVM、TradeFormVM、TradeGate
│       ├── repository/TradeRepository.ets
│       └── Index.ets
└── pk/                                      # HAR
    └── src/main/ets/
        ├── view/                            # PkHost、PaneSlot、WindowDeck、PagerDots
        ├── viewmodel/PkSessionVM.ets
        └── Index.ets

commons/
├── ui/                                      # HAR（设计系统）
│   └── src/main/ets/
│       ├── components/                      # Skeleton、StateView、ComingSoon、Banner、TagChip
│       ├── theme/                           # TokenRegistry、TokenRef
│       └── Index.ets
├── basic/                                   # HAR（无业务基建）
│   └── src/main/ets/
│       ├── constants/                       # ComingSoonText、LayoutConst、TimingConst
│       ├── i18n/                            # 文案 key 与格式化
│       ├── utils/                           # NumberFormat、MarketTime、Guard、Assert
│       ├── router/RouteService.ets          # 路由接口（由 products 实现）
│       └── Index.ets
└── data/                                    # HAR（数据能力）
    └── src/main/ets/
        ├── provider/                        # 契约 + Mock + index（Mock/Real 切换）
        ├── store/                           # QuoteCache、QuoteBus、SubscriptionRegistry、
        │                                    # ConnectionHub、SortStore、PkStore
        ├── chart/                           # ChartEngine 适配层（MpChart / Canvas）
        ├── entities/                        # 共享内核：QuoteSnapshot、WatchItem、OrderDraft…
        ├── DataServices.ets                 # 数据装配点（唯一 new Provider 处）
        └── Index.ets
```

**目录约定**：

1. 每个模块只通过 `Index.ets` 桶导出，跨模块禁止深路径 import（R-06）。
2. 资源分两级：`commons/ui` 放通用视觉 token，`products/entry/resources` 放产品级图标与限定词目录；feature 不自带主题。
3. 统一在模块根放 `oh-package.json5`，依赖显式声明，不靠相对路径穿透。

### 3.4 模块职责矩阵

| 阶段 | 落点模块 | 页面/壳 | ViewModel | Repository / Store |
|---|---|---|---|---|
| M0 | `products/entry` | `Index`、`TabShell` | `ShellVM` | — |
| M1 | `features/watchlist` | `WatchlistPage`、`FrozenTable` | `WatchlistVM`、`WatchRowVM` | `WatchlistRepository`；`QuoteCache`/`QuoteBus`/`SortStore`（commons/data） |
| M2 | `features/detail` | `DetailContent` | `DetailVM`、`ChartVM`、`OrderBookVM` | `DetailRepository`；`ChartEngine`（commons/data/chart） |
| M3 | `features/trade` | `TradeSheet` | `TradeVM`、`TradeFormVM` | `TradeRepository`；`AccountService`/`TradeGateway`（commons/data） |
| M4 | `features/pk` | `PkHost`、`PaneSlot` | `PkSessionVM`、`WindowSlotVM` | `PkStore`；`SubscriptionRegistry`（commons/data） |
| M5 | 横切 | `GlobalBanner`（products/shell） | `ConnectionVM`、`FontScaleVM` | `ConnectionHub`（commons/data） |

### 3.5 路由与深链

**路由表**（`Navigation` + `NavPathStack`）：

| name | 页面 | 参数 | 说明 |
|---|---|---|---|
| `detail` | `DetailPage` | `DetailParam`：`code`、`from`（list / card / search / deeplink）、`rank?` | 详情路由 |
| `pk` | `PkPage` | `PkParam`：`codes: string[]`、`focus?: number` | 多窗比价（2–3 窗） |
| `notFound` | `NotFoundPage` | `{ code?: string }` | 未知/下架/退市 |

**入口动线**：

| 入口 | sm/md/lg | xl（平板） |
|---|---|---|
| 列表行 / 卡片 / 搜索结果 | `pushPathByName('detail', param)` | 不路由，右栏 `DetailContent(mode: 'pane')` 换 `code`（INV-D2） |
| 深链 | 启动即 push，缺参按默认入口埋点 | 同左，右栏不参与 |

**返回恢复**（AC-53）：列表的滚动位置、选中行、分组、横滑偏移由 `WatchlistVM` 的 `@Trace` 字段持有（VM 状态），详情页 push 期间壳不销毁 → 天然保持；xl 右栏切换不走路由 → 天然保持。

**去重**（FR-06.2）：`NavigationGuard.tryNavigate(key)`，key = `detail:{code}`，300ms 窗口内只放行一次。

**深链**：`scheme://host/path?code=...`，示例 `zixuangu://detail?code=600519&from=deeplink`。测试命令 `hdc shell aa start -a EntryAbility -b <bundle> -U "zixuangu://detail?code=600519"`（bundle 以实际为准）。缺参/非法 code → `notFound`，并上报 `deeplink_invalid`。

**PK 入口**（FR-08.1）：详情动作栏「股票PK」、详情右上 ⧉、自选多选（2–3 只）→ `pushPathByName('pk', { codes, focus: 0 })`。单只不进 PK（提示「至少选择 2 只」），超 3 只截断，重复先去重。

### 3.6 全局状态与服务边界

| 单例 | 归属 | 生命周期 | 共享方式 |
|---|---|---|---|
| `ConnectionHub` | `commons/data/store` | 进程 | `AppStorageV2`（UI 只读状态） |
| `QuoteCache` + `QuoteBus` | `commons/data/store` | 进程 | 构造注入，不进 AppStorage |
| `SubscriptionRegistry` | `commons/data/store` | 进程 | 构造注入（多窗共享） |
| `SortStore` | `commons/data/store` | 页面会话（不持久化，CC-4.3） | `AppStorageV2` |
| `WatchlistRepository` | `features/watchlist/repository` | 进程 + 偏好持久化 | 构造注入 |
| `PkSession` | `commons/data/store` | 进程 + `PersistenceV2`（最后 1 组） | `PersistenceV2` |
| `BreakpointService` / `SafeAreaService` / `FontScaleService` | `commons/basic` | 进程 | `AppStorageV2`（组件持 `@Local` 引用读 `@Trace` 字段） |

**规则**：高频行情对象**绝不**进 `AppStorageV2`——全局可观测对象会让所有引用方重绘，直接破坏「单行刷新」。行情只经 `QuoteCache` 逐标的分发。

### 3.7 线程与调度模型

| 任务 | 线程 | 说明 |
|---|---|---|
| UI 渲染、状态更新 | 主线程 | ArkUI 状态只能在主线程改（非 UI 线程需 `flushUIUpdates`） |
| Mock 行情节拍 | 主线程单定时器 | `MockClock` 统一调度，禁止每个组件各起 `setInterval` |
| 1s 合并 | 主线程 | `QuoteBus` 定时 flush，12 标的量级无需并发 |
| K 线数据整形 | 主线程（V0 实测后决定是否 TaskPool） | 120~500 点，先不并发，避免 `@Sendable` 拷贝开销 |
| 持久化写入 | 异步 | 合并写、失败静默、启动读 |

**禁止**：在渲染回调内改状态（会触发 "state changed during render"）；在 `@Watch` 内直接调 `@Builder`。

### 3.8 架构决策记录（ADR）

| 编号 | 决策 | 备选 | 理由 |
|---|---|---|---|
| ADR-01 | 采用官方**三层模块化**：1 个 Entry HAP（products）+ 4 个 Feature HAR + 3 个 Common HAR | 单 HAP 目录分层 / 更多 HAR 细分 | 模块边界由构建系统强制（未声明依赖直接编译失败）；60 人日可承受，模块创建与依赖声明 +1.5 人日；多产品定制与 Feature HAP 留到二期（§3.1.12 演进） |
| ADR-02 | **自定义断点**，不用系统 `WidthBreakpoint` | 系统断点（xl 从 1440 起） | 基线要求 xl 从 ~1200 起（平板 1180 必须进 xl 分栏），系统阈值不匹配；见 §11-Q1 |
| ADR-03 | 冻结表 = 横向 `Scroll` 内竖向 `List` + 名称列 `translate` 同步 | 每行独立横滑 / 双 List 同步 / 自绘 Canvas | 每帧只 1 次状态更新（名称列），虚拟化保留在 `List`；见 §5.2 |
| ADR-04 | 图表走 `ChartEngine` 适配层 | 业务直连图表库 | R4：库与 V2/多实例兼容不可控，隔离后可换可退 |
| ADR-05 | 交易两层栈**单容器、单层渲染** | 两个弹窗叠开 | INV-T2；避免遮罩叠层与返回栈歧义 |
| ADR-06 | 订阅合并中心（按 code 引用计数 + 多播 + 分级节流） | 每窗独立订阅 | AC-83：3 窗 ≤3 路，同 code 合并；降频在一处实现 |
| ADR-07 | 状态 V2 单例走 `AppStorageV2`/`PersistenceV2`，行情不进全局 | 全量进 AppStorage | 观测粒度决定性能 |
| ADR-08 | 占位文案 = 5 条完整 i18n 字符串 + 常量类 + 单测校验模板 | 运行时模板拼接 | 模板统一、可测、可审；避免参数化带来的标点差异 |
| ADR-09 | 行情时间取快照时间，设备时钟只用于「已收盘」文案 | 设备时钟 | FR-06.3：时间取行情快照；收盘后冻结 |
| ADR-10 | 持久化用 `PersistenceV2`（PK 组合）+ `preferences`（自选/分组），不引入 RDB | RDB | 数据量 50 只/8 组，RDB 过重；二期真实数据再迁移 |

---

## 4. 数据层设计

### 4.1 契约总览

| 接口 | 职责 | Mock 必须支持（基线 §7） | 消费方 |
|---|---|---|---|
| `QuoteProvider` | 快照 / 推送 / 盘口 / 分笔 / 图表序列 | 1s 推送、增量 patch、断线、延迟、429 | M1、M2、M4 |
| `AccountService` | 登录态 / 股东账户 / 可买 / 持仓 | 未登录、未开户、可买 0、单账户 | M3 |
| `TradeGateway` | 委托受理 / 查询 | 成功 / 失败（资金不足、超涨跌停、风控）/ 超时 / 幂等去重 | M3 |

### 4.2 接口定义

> 约定：全部 `Promise` 化、全部显式类型、错误以 `QuoteError` / `OrderResult` **显式返回**（不靠异常做业务分支，避免 UI 层 try/catch 散落）。时间一律 `number`（毫秒时间戳），行情时间取**快照时间**。

```ts
// commons/data/provider/QuoteProvider.ets
export type Market = 'SH' | 'SZ' | 'BJ';
export type TradeStatus = 'pre' | 'auction' | 'open' | 'lunch' | 'closed' | 'suspended' | 'delisted';
export type ChartPeriod = 'timeline' | 'five' | 'd' | 'w' | 'm' | 'q' | 'hy' | 'y';

export interface OrderLevel {
  price: number;
  volume: number;          // 手
}

export interface Tick {
  time: number;
  price: number;
  volume: number;
  dir: 'buy' | 'sell' | 'neutral';
}

export interface OrderBook {
  code: string;
  asks: OrderLevel[];      // 卖1~卖5
  bids: OrderLevel[];      // 买1~买5
  askVolume: number;
  bidVolume: number;
  snapshotTime: number;
}

export interface QuotePatch {
  code: string;
  snapshotTime: number;
  last?: number;
  prevClose?: number;
  open?: number;
  high?: number;
  low?: number;
  chg?: number;
  pct?: number;
  volume?: number;
  amount?: number;
  turnover?: number;
  pe?: number;
  pb?: number;
  amplitude?: number;
  volumeRatio?: number;
  marketCap?: number;
  floatCap?: number;
  limitUp?: number;
  limitDown?: number;
  status?: TradeStatus;
  orderBook?: OrderBook;
  ticks?: Tick[];
}

export interface QuoteError {
  code: string;
  reason: 'timeout' | 'offline' | 'rate_limited' | 'not_found' | 'internal';
  retryAfterMs?: number;
}

export interface QuoteListener {
  onPatch(patch: QuotePatch): void;
  onStatus(state: ConnectionState): void;
  onError(error: QuoteError): void;
}

export interface QuoteSubscription {
  unsubscribe(): void;
}

export interface QuoteProvider {
  getSnapshot(code: string): Promise<QuoteSnapshot>;
  subscribe(codes: string[], listener: QuoteListener): QuoteSubscription;
  getOrderBook(code: string): Promise<OrderBook>;
  getTicks(code: string, limit: number): Promise<Tick[]>;
  getChart(code: string, period: ChartPeriod, limit: number): Promise<ChartSeries>;
}
```

```ts
// commons/data/provider/AccountService.ets
export interface AuthSession {
  loggedIn: boolean;
  userId?: string;
}

export interface AccountInfo {
  accountId: string;
  maskNo: string;          // 前 3 后 2 脱敏
  available: number;
  holdQty: number;
  maxBuyQty: number;
  opened: boolean;
  canTrade: boolean;
}

export interface Tradable {
  code: string;
  canBuy: number;
  holdQty: number;
  limitUp: number;
  limitDown: number;
  status: TradeStatus;
  snapshotTime: number;
}

export interface AccountService {
  getSession(): Promise<AuthSession>;
  login(): Promise<AuthSession>;
  getAccount(): Promise<AccountInfo | null>;   // null = 未开户
  getTradable(code: string): Promise<Tradable>;
}
```

```ts
// commons/data/provider/TradeGateway.ets
export interface OrderDraft {
  code: string;
  accountId: string;
  side: 'buy';
  price: number;
  qty: number;
  clientOrderId: string;
}

export interface OrderResult {
  clientOrderId: string;
  orderId?: string;
  status: 'accepted' | 'rejected' | 'unknown';
  code?: string;           // 错误码，映射到 FR-07 §2.5 文案
  message: string;
  ts: number;
}

export interface TradeGateway {
  submit(draft: OrderDraft, timeoutMs: number): Promise<OrderResult>;
  query(clientOrderId: string): Promise<OrderResult | null>;
}
```

### 4.3 实体模型

| 实体 | 关键字段 | 来源 |
|---|---|---|
| `QuoteSnapshot` | `code`、`market`、`status`、`snapshotTime`、价格类、估值类、`limitUp/Down` | FR-06 §3 |
| `WatchItem` | `code`、`groups[]`、`addedAt`、`pending` | CC-2.7 |
| `Group` | `id`、`name`、`type`（system/user/virtual）、`order` | CC-2.7 |
| `StockDetail` | `quote`、`orderBook`、`ticks[20]`、`chart`、`news`、`added` | FR-06 §3 |
| `OrderDraft` / `OrderResult` | 见 §4.2 | FR-07 §3 |
| `PkGroup` / `WindowState` / `PkSession` | `codes[2..3]`、`host`、`windows[]`、`focus`、`layout` | FR-08 §3 |

**字段规约**：

- `tags[]` 只放板块/状态（融/创/科/停/新），`groups[]` 只放分组归属；**禁止**用 `tags.includes('fin')` 判断分组（CC-2.9）。
- `groups` 只在「加入自选」瞬间派生，之后独立存储（本期不做加自选，但模型先按此建）。
- 价格类空值用 `null`，由 View 层渲染 `--`；**禁止**用 `0` 或 `-1` 代替空值。
- 平盘：`chg === 0` 显示 `0.00`，不带正负号（FR-02.8）。

### 4.4 行情管线

```
MockQuoteProvider (1s 心跳)
   │  原始 patch（可能高频、可能乱序）
   ▼
QuoteBus.enqueue(patch)
   ├─ QuoteCache.apply(patch)        // 只改 @Trace 字段
   └─ dirty.add(code)
        │  (定时器 1000ms 首帧对齐)
        ▼
QuoteBus.flush()
   ├─ 对 dirty 中每个 code 通知 row sink（单行）
   └─ dirty 清空
        │
        ├─ 可见行 sink   → WatchRowVM.onPatch() → 单行重绘
        ├─ 详情 sink     → DetailVM.onPatch()   → 头部/盘口局部更新
        └─ 多窗 sink     → 按窗节流（焦点 1s / 非焦点 5s）
```

**关键规则**：

| 规则 | 实现 |
|---|---|
| 合窗 1s（FR-02.7、FR-06.8） | 单定时器，首帧对齐到下一个 1s 边界；flush 后清 dirty |
| 变动高亮一次 | `row.flashSeq++`，300–500ms 后 `flashSeq` 失效；1s 内连续变动不重复 |
| 单行刷新 | `WatchRowVM` 持有 `@Trace quote: SymbolQuote`；`SymbolQuote` 字段全 `@Trace` |
| 断线冻结 | `ConnectionHub.state === ConnectionState.Offline` 时 `QuoteBus` 只 mark 不 apply；恢复后补一帧全量 |
| 订阅合并 | `SubscriptionRegistry` 按 code 引用计数，1 路 provider 订阅 → N 个 sink |
| 降频 | sink 携带 `tier`（focus / normal / background），registry 按 tier 丢帧而非另开订阅 |
| 退订即释放 | `unsubscribe()` 必须幂等；销毁窗/退出页/退后台（可选）调用 |

**首帧策略**：`getSnapshot` 拉一次全量 → 渲染 → 再 `subscribe` 增量；避免「先订阅后快照」造成的中间态闪烁。

### 4.5 Mock 与调试面板

**数据集下限 12 只**（基线 §7），覆盖：涨 / 跌 / 平 / 停牌 / 新股 / 负市盈率 / 涨停 / 跌停。

| 标的（示例） | 场景 | 用途 |
|---|---|---|
| `600519` 样例白酒 | 正常上涨 | 主流程 |
| `000001` 样例银行 | 平盘 `0.00` | 平盘着色 |
| `300750` 样例电池 | 下跌 | 跌绿 |
| `688981` 样例芯片 | 负市盈率「亏损」 | 格式化 |
| `600000` 样例停牌 | 停牌（价格 `--`、恒末尾、仍可点） | FR-02.12 / FR-06 停牌态 |
| `301999` 样例新股 | 新股（涨跌 `--`、「新」标） | 特殊行 |
| `600111` 样例涨停 | 涨停（`limitUp` 命中） | 交易边界 |
| `600222` 样例跌停 | 跌停 | 价格 clamp |
| 其余 4 只 | 批量填充至 12 | 滚动与排序 |

**Mock 能力开关**（仅 debug 构建可见的调试面板）：

| 开关 | 效果 |
|---|---|
| 切断线 / 恢复 | `ConnectionHub` 强制 `offline` / 回 `online` |
| 切延迟 | `delayed` 状态；推送延迟 3s |
| 注入失败 | 下单失败 / 快照失败 / 图表失败（按模块） |
| 模拟内存告急 | 触发多窗降级链（关非焦点窗 → 降频 → 单窗） |
| 模拟 3 窗 | 直接构造 3 窗 PK 会话 |
| 强制 429 | 触发限流退避 |

**约束**：调试面板不得进入 release 包（构建 profile 的 DEBUG 标记判定 + 代码裁剪）。

### 4.6 持久化与缓存

| 数据 | 位置 | 策略 |
|---|---|---|
| 自选列表 / 分组 | `preferences`（JSON） | 启动读、变更合并写（100ms 防抖）；损坏则回退默认集并上报 |
| PK 组合 | `PersistenceV2`（`{ codes, periods, focus }`） | 只保留最后 1 组（DEC-08-05），不存行情 |
| 排序状态 | 内存 | **不持久化**（CC-4.3） |
| 图表数据 | 内存 LRU（按 code+period） | 5min 内切回不重发（FR-06.7） |
| 行情快照 | 内存 | 断线时保留最后一帧用于冻结展示（CC-7.6） |
| 资讯条关闭 | 内存（按 code） | 会话内记忆，不持久化（FR-06.5） |

### 4.7 时间与交易时段

- **行情时间**：`snapshotTime` 来自快照，不由设备时钟生成；收盘后冻结（AC-55）。
- **交易时段判定**：`MarketSession.resolve(now, market)` → `pre / auction / open / lunch / closed`；只用于文案与按钮态，不作为「能否提交」的唯一依据（以网关返回兜底）。
- **测试可控时间**：`MockClock` 支持注入固定时间，供 UiTest 覆盖「收盘/午休/开盘前」。

### 4.8 错误模型与码表

| 层 | 表现 | UI 处置 |
|---|---|---|
| 网络/行情 | `QuoteError.reason` | `offline` → 全局 banner + 冻结；`timeout` → 重试（退避）；`rate_limited` → 延后，不弹错 |
| 详情首屏 | `DetailRepository` 返回失败 | 整页错误态 + 重试（FR-06 §2.5） |
| 图表 | `ChartEngine` 失败 | 局部错误 + 重试，不影响盘口（FR-06 §2.5） |
| 交易 | `OrderResult.code` | 映射 FR-07 §2.5 文案，字段级/弹窗内提示 |
| 未知异常 | 兜底 | 不白屏：进入 `StateView.Error` + 上报 |

---

## 5. 模块技术方案

### 5.1 M0 应用外壳

#### 5.1.1 结构

```
Index（AppRoot）
└─ Navigation(pathStack)
     ├─ navBar:
     │    Stack(alignContent: Bottom)
     │      ├─ TabShell(Tabs，隐藏系统 TabBar，自绘悬浮底栏)
     │      │    ├─ HomePage        (占位：首页)
     │      │    ├─ NewsPage        (占位：最新资讯)
     │      │    ├─ WatchlistPage   (M1：自选)
     │      │    └─ MarketPage      (占位：行情)
     │      └─ FloatingTabBar       // 四 Tab，悬浮胶囊
     └─ NavDestination: detail / pk
```

- 底栏为**自绘悬浮胶囊**（设计稿为浮于内容之上的圆角容器），不是系统 `Tabs` 默认 bar：`Tabs` 只负责页面切换，`barHeight(0)` 隐藏默认栏。
- 四 Tab：首页 / 最新资讯 / 自选 / 行情；自选为默认页（`currentIndex = 2`）。
- 占位三页用同一 `PlaceholderPage` 组件：标题 + 说明 + 灰色图标位，**不含第二个按钮**（基线 §4.1 规则 6）。

#### 5.1.2 安全区与沉浸式

| 项 | 方案 |
|---|---|
| 状态栏 | 内容延伸到状态栏（`expandSafeArea`），状态栏图标用深色（浅色底） |
| 底部导航条 | 底栏底部内边距 = `avoidArea.bottom` + 8vp |
| 列表底部 | 悬浮底栏遮挡 → 列表底部预留 **24vp** 安全内边距（基线 C3） |
| 监听 | `window.on('avoidAreaChange')` → `SafeAreaService`（`AppStorageV2` 单例）；`onWindowStageDestroy` 反注册 |
| 折叠/悬停 | `display.on('foldStatusChange')` + `windowSizeChange` 组合驱动断点与形态；回调名以 API 20 文档为准，V0 固化 |

> 沉浸式只做「内容延伸 + 避让」两件事，不做状态栏颜色动画，避免与折叠态切换打架。

#### 5.1.3 主题 token

**原则**：组件内禁止出现颜色字面量；一律 `$r('app.color.xxx')`。颜色取自设计稿的近似值见下表，**最终以设计交付的 `color.json` 为准**。

| token | 用途 | 参考值（取样近似） |
|---|---|---|
| `color_bg_page` | 页面底色 | `#FFFFFF` |
| `color_bg_surface` | 卡片/指数条底色 | `#F7F8FA` |
| `color_text_primary` | 主文本 | `#1A1A1A` |
| `color_text_secondary` | 次级文本/代码 | `#8A8A8E` |
| `color_price_up` | 涨 | `#E8342A` |
| `color_price_down` | 跌 | `#00A870` |
| `color_price_flat` | 平 | `#6B6B70` |
| `color_accent` | 选中 Tab / 主按钮 / 下划线 | `#E8342A` |
| `color_divider` | 分割线 | `#EDEDED` |
| `color_tag_fin` | 「融」标签 | `#7C4DFF` |
| `color_tag_star` | 「创」标签 | `#FF7A00` |
| `color_disabled_bg` / `color_disabled_text` | 禁用按钮 | `#F2F2F2` / `#B0B0B5` |
| `color_banner_bg` | 断线 banner | `#FFF4E5` |
| `color_chart_line` / `color_chart_avg` | 分时线 / 均价线 | `#E8342A` / `#F5A623` |
| `opacity_offline` | 断线整体置灰 | `0.55` |

尺寸 token 进 `float.json`：`row_height_base=56`、`header_height_base=40`、`touch_min=44`、`pill_radius=22`、`fade_width=20`、`gap_2/4/8/12/16/24`。

#### 5.1.4 占位组件（DEC-10-02）

```ts
// commons/basic/constants/ComingSoonText.ets
export class ComingSoonText {
  static readonly ADD_WATCHLIST: ResourceStr = $r('app.string.coming_soon_add_watchlist');
  static readonly CARD_VIEW: ResourceStr = $r('app.string.coming_soon_card_view');
  static readonly HOME: ResourceStr = $r('app.string.coming_soon_home');
  static readonly NEWS: ResourceStr = $r('app.string.coming_soon_news');
  static readonly MARKET: ResourceStr = $r('app.string.coming_soon_market');
}
```

| 触发 | 组件 | 呈现 |
|---|---|---|
| 底部「添加自选」胶囊 | `showComingSoon(ADD_WATCHLIST)` | toast 1.8s，居中偏下 |
| 视图切换图标 | `showComingSoon(CARD_VIEW)` | 同上；图标**不置灰** |
| 切到首页/资讯/行情 | `PlaceholderPage(title, desc)` | 整页空态，常驻 |

**强制校验**（单测，进 CI）：

```ts
// ComingSoonSpec.test.ets（伪代码）
// 1) 每条字符串必须以「下阶段开放」结尾
// 2) 不得包含「敬请期待」「即将上线」「暂未开放」「Coming」「~」「!」「！」
// 3) 不得包含版本号片段（v1.1 / （一期））
```

> 之所以用 5 条完整字符串而不是运行时拼接模板：`$r` 返回 `Resource`，拼接需要 `getStringSync` 且易出现空格/标点差异；用**测试约束格式**比运行时拼接更可靠（ADR-08）。

#### 5.1.5 状态视图与全局 banner

| 组件 | 用途 | 规则 |
|---|---|---|
| `Skeleton` | 首屏 | ≤300ms 出现；原地替换为内容，**不闪白** |
| `StateView.Empty` | 空态 | 自选空态带「添加自选」入口；其余空态无第二按钮 |
| `StateView.Error` | 失败 | 文案 + 重试；重试中按钮 loading |
| `GlobalBanner` | 断线/弱网/延迟 | **全页唯一**，挂在 TabShell 顶部；`DetailContent` 内禁止渲染 |

`GlobalBanner` 是唯一订阅 `ConnectionHub.state` 的 UI 组件；所有页面通过布局给它让位（顶部占位高度），**不允许**各页自绘提示条（CC-7.3）。

---

### 5.2 M1 自选列表（核心技术难点）

#### 5.2.1 需求到实现的约束

| 约束 | 来源 | 实现要求 |
|---|---|---|
| 固定 11 列，顺序不可配 | FR-02.1 | 列定义常量化，渲染顺序唯一 |
| 名称列与表头竖向冻结、左侧横向冻结 | FR-02.3 / CC-6.4 | 名称列不参与横滑；表头不参与竖滑 |
| 富余全给名称列，不足全转横滑 | FR-02.2 | 名称列 `max(base×scale, 视口 - 数字列宽)` |
| 表头列头循环 降序→升序→取消 | CC-4.2 | `SortStore.cycle(key)` |
| 空值恒末尾 | CC-4.4 | 排序比较器把 `null` 固定放末尾，不随方向翻转 |
| 50 行 ≥55fps，单行刷新 | CC-1.2 | 虚拟化 + 逐标的 `@Trace` |
| 1.45× 不截断、不隐藏列 | CC-6.5 / AC-51 | 只增宽横滑，不减列 |
| 平板坚持 11 列 | DEC-09-02 | 不按宽度减列；横滑量 ≈311vp |

#### 5.2.2 方案选型（ADR-03）

| 方案 | 做法 | 优点 | 致命问题 | 结论 |
|---|---|---|---|---|
| A 每行独立横滑 | 每行一个 `Scroll`，`onScroll` 广播偏移 | 结构直白 | 50 个滚动容器 + 50 次/帧同步，必掉帧；惯性不同步 | 否 |
| B 双 List 同步 | 名称列 List + 数据 List 各自竖向滚动，`scrollTo` 互跟 | 都虚拟化 | 每帧 `scrollTo` 往返、易抖动；惯性/回弹不同步 | 备选 |
| C 横滑内含竖 List + 名称列 `translate` | 1 个横向 `Scroll`，内部 `Column{表头, List}`；名称列在容器外，按竖向偏移整体 `translate` | **1 次/帧状态更新**（仅名称列），横向滚动原生处理；`List` 保留虚拟化；表头与列天然同源横滑 | 名称列不虚拟化（50 行可接受）；需固定行高 | **采用** |
| D Canvas 自绘整表 | 全自绘 | 性能上限高 | 无障碍、选中、字号全自建；工作量翻倍 | 否（仅兜底） |

**采用方案 C**，理由：偏移同步的更新次数是决定帧率的主因。C 每帧只需 1 次状态更新（名称列 `translate`），横向偏移完全交给原生 `Scroll`，表头与数据列同源、零同步。

#### 5.2.3 结构

> `metrics` 为 `@Local`，随视口与 `fontScale` 由 `computeTableMetrics` 重算（§5.2.4）。

```
Column() {
  IndexStrip()                       // 指数条：3/5/5/3 项
  GroupTabs()                        // 全部 + 系统组 + 用户组（带只数）
  Row() {                            // 表格主体
    // ① 名称列（冻结）
    Column() {
      NameHeader()                   // 宽 nameW
      Column() {
        NameBody()                   // 50 行，固定 rowH
          .translate({ y: -this.vOffset })
      }
      .layoutWeight(1)
      .clip(true)
    }.width(this.metrics.nameWidth)

    // ② 数据区（横滑 + 竖滑）
    Scroll(this.hScroller) {
      Column() {
        NumericHeader({ widths: this.metrics.widths })   // 与数据列同一横滑内容
        List(this.vScroller) {
          ForEach(this.rows, (row: WatchRowVM) => {
            ListItem() { QuoteCells({ row, widths: this.metrics.widths }) }
          }, (row: WatchRowVM) => row.code)
        }
        .layoutWeight(1)
        .cachedCount(6)
        .edgeEffect(EdgeEffect.None)
        .onScroll(() => { this.vOffset = this.vScroller.currentOffset().yOffset })
      }
      .width(this.metrics.numericWidth)
      .height('100%')
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
    .layoutWeight(1)
  }.layoutWeight(1)
}
```

**为什么表头放进横向 `Scroll`**：表头与数据列同处一个横向滚动内容 → 横向偏移**零同步**；`Scroll` 只横滑，表头在 `Column` 顶部不被竖向 `List` 影响 → 竖向**天然冻结**。

#### 5.2.4 几何计算（唯一实现）

```ts
// features/watchlist/view/TableMetrics.ets
export interface TableMetrics {
  widths: number[];        // 11 列宽，[0] 为名称列
  nameWidth: number;
  numericWidth: number;
  totalWidth: number;
  overflow: number;        // >0 才横滑
  rowHeight: number;
  headerHeight: number;
}

const NAME_BASE: number = 112;
const NUMERIC_BASE: number[] = [76, 70, 78, 82, 68, 78, 66, 66, 70, 68]; // 最新价…市净率
const ROW_BASE: number = 56;
const HEADER_BASE: number = 40;

export function computeTableMetrics(viewport: number, fontScale: number): TableMetrics {
  const numeric: number[] = NUMERIC_BASE.map((b: number): number => Math.round(b * fontScale));
  const numericSum: number = numeric.reduce((s: number, w: number): number => s + w, 0);
  const nameBase: number = Math.round(NAME_BASE * fontScale);
  const nameWidth: number = Math.max(nameBase, viewport - numericSum);
  const widths: number[] = [nameWidth].concat(numeric);
  const totalWidth: number = nameWidth + numericSum;
  const overflow: number = Math.max(0, totalWidth - viewport);
  return {
    widths, nameWidth, numericWidth: numericSum, totalWidth, overflow,
    rowHeight: Math.max(ROW_BASE, Math.round(ROW_BASE * fontScale)),
    headerHeight: Math.max(HEADER_BASE, Math.round(HEADER_BASE * fontScale))
  };
}
```

**自检数**（与 CC-6.3 对齐）：1.0× 名称 112 + 数字 722 = **834vp**；1.3× ≈ **1084vp**；1.45× ≈ **1209vp**；断点视口下横滑量见基线 §6。

#### 5.2.5 横滑与冻结的关键细节

| 细节 | 做法 |
|---|---|
| 名称列竖向跟随 | `NameBody.translate({ y: -vOffset })`；`vOffset` 来自 `List.onScroll` 时的 `currentOffset().yOffset` |
| 行高一致 | 名称行与数据行共用 `metrics.rowHeight`，**禁止**任一列自适应撑高（否则错位） |
| 回弹 | 两侧 `edgeEffect(EdgeEffect.None)`，避免回弹期间两列错位；如需回弹只允许数据区，名称列按 clamp 跟随 |
| 右侧渐隐 | 数据区上层叠 `Row().width(20)` 渐变；`xOffset = hScroller.currentOffset().xOffset`，`opacity = overflow > 0 && xOffset < overflow - 8 ? 1 : 0` |
| 横滑条 | **隐藏**（`scrollBar(BarState.Off)`，2026-11-12 产品要求）；底部保留 8vp 呼吸位，最后一行不被裁 |
| 列头点击 | 表头数字列可点（`sortableKeys` 内），点击循环 `desc → asc → none`；名称列点击不做排序 |
| 排序指示 | 表头右侧三角 + 色值 accent；`none` 时隐藏 |
| 横滑位置保持 | `xOffset` 存 `WatchlistVM`，切分组/进详情返回后恢复；分栏切换按「比例」恢复（AC-53） |
| 名称列手势 | 名称列自身不滚动：`PanGesture({ direction: PanDirection.All })` 把 dx 转发 `hScroller.scrollBy(-dx, 0)`、dy 转发 `vScroller.scrollBy(0, -dy)`，并保留点击进详情；惯性不转发（松手即停），换取两列绝对同步 |

> 为什么名称列不做成第二个 `List`：两个可滚动容器各有惯性与回弹，双向 `scrollTo` 在甩动时必然抖动（方案 B 的问题），且 50 行不需要它虚拟化。用「单侧滚动 + 手势转发」把不确定性降到零。

**已知取舍**：表头本身**不响应横向拖拽**（拖拽入口为数据区与滚动条）。若验收要求表头可拖，需把表头换成独立 `Scroll` 并双向同步，成本 +0.5 人日、且有回环风险，列入 §11-Q6 待确认。

#### 5.2.6 行渲染与刷新

```ts
@ObservedV2
export class SymbolQuote {
  code: string = '';
  @Trace last: number | null = null;
  @Trace chg: number | null = null;
  @Trace pct: number | null = null;
  @Trace volume: number | null = null;
  @Trace amount: number | null = null;
  @Trace status: TradeStatus = 'closed';
  @Trace flashSeq: number = 0;      // 变动高亮
}

@ObservedV2
export class WatchRowVM {
  code: string = '';
  @Trace name: string = '';
  @Trace tags: string[] = [];
  @Trace quote: SymbolQuote = new SymbolQuote();
  @Trace selected: boolean = false;
}
```

- `ForEach` key = `code`（业务 ID），**禁止**索引用作 key。
- 行组件 `@Param row: WatchRowVM`（只读引用），内部读 `row.quote.xxx` → 只有该行被标记脏。
- 变动高亮：`flashSeq` 变化触发一次 320ms 背景渐变，`QuoteBus` 保证 1s 内不重复。
- 停牌/新股行：价格类渲染 `--`，附加标签；行仍可点（FR-02.12）。

#### 5.2.7 排序

```ts
export type SortKey = 'price' | 'chg' | 'pct' | 'vol' | 'amt' | 'amp' | 'turn' | 'pe' | 'pb';
export type SortDir = 'desc' | 'asc' | 'none';

@ObservedV2
export class SortStore {
  @Trace key: SortKey | null = null;
  @Trace dir: SortDir = 'none';
  cycle(key: SortKey): void { /* desc → asc → none */ }
}
```

**比较器规则**：

1. `dir === 'none'` → 用手动序（`addedAt` 升序，本期 Mock 固定序）。
2. 任一侧为 `null`（停牌/新股）→ 恒排末尾，**不做方向翻转**。
3. 平盘（`chg === 0`）按 `last` 次键排序，仍稳定。
4. 排序在 ViewModel 层对已缓存的 `WatchRowVM[]` 做一次重排，不重新请求。

#### 5.2.8 分组与指数条

| 项 | 规则 |
|---|---|
| 分组 Tab | 「全部」+ 系统组（融/创/科）+ 用户组，显示只数；**最多 5 个**、最少 1 个「全部」；横向可滑动、内容**始终居左**；选中红色下划线 3vp |
| Tab 右侧占位 | 最右侧固定预留两个占位符（卡片切换 / 排序），不随 Tab 横滑移动；本期仅占位，行为后续接入 |
| 无组股票 | 不出现（INV-1/INV-3）；Mock 数据保证 |
| 指数条条目 | **与当前 Tab 的列表行逐股票一一对应**：条数与顺序均与列表一致，每条展示「名称 + 涨跌幅」 |
| 指数条实现 | `List`（`listDirection: Axis.Horizontal`）+ `LazyForEach`（`IndexBarDataSource`）；可视宽度内平铺，**超出部分横向滚动** |
| 分组切换 | 条目集合与顺序随分组重建（如切「创业板」只剩该组 3 条） |
| 排序影响 | 逐股票对应，**随列表排序同步变化**（CC-4.5「排序不影响指数条」不再适用） |
| 数据刷新 | 条目复用列表的 `WatchRowVM`，推送只改该条目的 `@Trace` 字段，不整体重建 |
| 推荐卡片 | 与指数条**平级**（不在横滑 `List` 内），固定在该行最右侧；与指数条同一水平带、垂直居中；横滑指数条时卡片不动 |
| 卡片样式 | 本期为**样式占位**：设计系统 token（`bgSurface` + `divider` 描边 + 圆角 8 + accent 文案），内容与点击行为后续再定；xl 下贴在列表列右缘（非窗口右缘，见 §11-Q8） |

> **2026-11-12 产品口径调整**：原「`IndexSet[groupId]` 固定 3/5/5/3 项、不做横向滚动」方案废弃，`BreakpointService.indexCount` 一并移除；指数条改为逐股票一一对应 + 横向滚动，并新增右侧推荐卡片（平级、固定）。

#### 5.2.9 四形态与字号

| 断点 | 屏宽 → 列表可用宽 | 列表形态 | 11 列横滑量（1.0×） | 备注 |
|---|---|---|---|---|
| sm | 375 → 343 | 单列全宽 | ≈491vp | 首屏约 4.5 列 |
| md | 720 → 688 | 单列全宽 | ≈146vp | — |
| lg | 1000 → 968 | 单列全宽 | 0 | 富余给名称列 |
| xl | 1180 → 523（左栏） | 左栏 + 右栏 | ≈311vp | 名称列冻结改为「栏内冻结」 |

> 可用宽度 = 屏宽 − 左右各 16vp 内边距；xl 取左栏 523vp。横滑量 = 834 − 可用宽度（负值取 0），与基线 §6 的 491 / 146 / 0 / 311 对齐。

**字号**：字体用 `fp`（系统自动缩放），列宽用 `base × fontScale` 同步放大 → 不会「字大了格子没大」。1.45× 只增加横滑量，**不减列、不截断**（G8 的「只降列」仅适用于指标面板与卡片，见 §11-Q3）。

#### 5.2.10 无障碍

- 行 `accessibilityText`：`名称 + 代码 + 最新价 + 涨跌 + 涨跌幅`；停牌追加「停牌」，新股追加「新股」。
- 表头 `accessibilityText` 含当前排序方向（如「最新价，降序」）。
- 行可聚焦；聚焦框不遮挡冻结列。
- 1.3× 下行高按 `rowHeight` 增长，不重叠（AC-09）。

#### 5.2.11 性能与坑

| 坑 | 规避 |
|---|---|
| 行内多层 `if` + 多次格式化 | 格式在 VM 层算好（字符串缓存），行只做渲染 |
| `ForEach` 无 key 或索引 key | 业务 key（code） |
| 每行读全局 `@Trace` 大对象 | 逐标的 `SymbolQuote` |
| `List` 在 `Scroll` 内 lazy 失效 | V0 用 50 行实测首屏与滚动帧率；若失效，降级为 `Column + ForEach`（50 行可接受） |
| 表头与数据列宽误差 | 两侧共用同一 `widths[]`，禁止各自 round |

#### 5.2.12 V0 验证清单（R2）

| # | 验证 | 通过判据 |
|---|---|---|
| 1 | 50 行 1.0× 连续滚动 | ≥55fps，无白块，名称列与数据列无 1px 级错位 |
| 2 | 1.45× 横滑 | 1209vp 全量可滑到最后一列，不截断、不隐藏 |
| 3 | 折叠展开切换 | 横滑偏移与滚动位置不丢 |
| 4 | 名称列 translate 同步 | 快速甩动 + 回弹后仍对齐（允许 ±0.5vp） |
| 5 | 单行刷新 | 1s 推送只重绘目标行（DevTools 组件更新计数验证） |
| 6 | 平板左栏 523 | 11 列可横滑，关闭详情后恢复偏移 |

---

### 5.3 M2 个股详情

#### 5.3.1 壳 / 内容分离（INV-D1~D4）

```ts
// features/detail/view/DetailContent.ets
export type DetailAction = 'watchlist' | 'pk' | 'more' | 'trade';

@ComponentV2
export struct DetailContent {
  @Param code: string = '';
  @Param mode: 'page' | 'pane' | 'window' = 'page';
  @Param compact: boolean = false;
  @Event onAction: (etype: DetailAction) => void = () => {};
  @Event onLoaded: (code: string) => void = () => {};
  // 内部：QuoteHeader / MetricPanel / ChartArea / OrderBookPanel / ContentTabs / ActionBar
}
```

| 约束 | 落地 |
|---|---|
| INV-D1 | `DetailContent` 不调用 `pathStack.push/pop`、不创建 `GlobalBanner`、不起重连定时器 |
| INV-D2 | 周期、指标展开态由 `DetailVM` 持有（按 code 缓存），page↔pane 切换不重建 VM |
| INV-D3 | window 每实例独立 `DetailVM` + `ChartEngine`，关闭即 `dispose` |
| INV-D4 | 「去交易」全页唯一：page 在动作栏，pane/window 收进「⋯」菜单 |

#### 5.3.2 形态映射

| 形态 | 触发 | 组成 |
|---|---|---|
| page | sm/md 全屏 push；lg 可全屏 | 全量 |
| pane | xl 右栏 | 紧凑版（FR-06 §2.6） |
| window | 多窗实例 | 紧凑版，独立订阅 |
| compact | 窗宽 <360vp | 图表在上，五档两列 + 明细在下 |

#### 5.3.3 报价头与指标

- 头部：名称（代码）、市场标签、交易状态 + **行情时间**、最新价、涨跌、涨跌幅；价格闪一次（`flashSeq`）。
- 时间显示：开盘 `已收盘 10-19 15:03:03` 类文案由 `MarketTime.format(status, snapshotTime)` 产出；**不读设备时钟**。
- 指标池 12 项，展示 6/9/12、列数 2/3/4；`fontScale` 每档减 1 列，下限 1 列（FR-06 §2.2）。
- 第 4 组固定「振幅 / 量比 / 流通市值」（基线 C4），避免平板稿重复「今开/昨收/换手」。
- 负市盈率显示「亏损」；空值 `--`；开/高/低相对昨收着色。

#### 5.3.4 图表区

```ts
export interface ChartSeries {
  period: ChartPeriod;
  points: ChartPoint[];       // 分时 241；K 线 ≤500
  prevClose: number;
  limitUp: number;
  limitDown: number;
}

export interface ChartEngine {
  mount(): void;
  setSeries(series: ChartSeries): void;
  setCrosshairEnabled(enabled: boolean): void;
  setZoomEnabled(enabled: boolean): void;
  resetZoomFor(period: ChartPeriod): void;
  dispose(): void;
}
```

| 项 | 方案 |
|---|---|
| 周期 Tab | 8 个（分时/五日/日K/周K/月K/季K/半年K/年K），`List + ForEach` 横滑；间距 sm 12 / md 14 / lg 16 / xl 20；首尾 16 内边距 |
| 点击即刷新 | `ChartVM.selectPeriod(p)`：自增 `seq` → 取消在途 → 有缓存（5min）直接 `setSeries` → 否则请求；**禁止沿用上一周期画面** |
| 容器 | 一页一实例，切周期只换 series，不重建容器、不跳布局 |
| 缩放 | K 线可双指缩放 + 左右拖动；分时禁止缩放；每周期记忆缩放（`zoomByPeriod`） |
| 长按十字光标 | `setCrosshairEnabled(true)`；读数含时间/价/均价/量/涨跌幅 |
| 加载 | 首帧骨架；失败局部重试；120 根/次，上滑加载至 500 根 |
| 释放 | 页面 `aboutToDisappear` / 窗关闭 → `dispose()` + `unsubscribe()` |

**ChartEngine 适配层职责**：把三方库的类型、生命周期、线程约束关在 `commons/data/chart/` 内；`ChartVM` 只认 `ChartSeries`。V0 失败时换 Canvas 实现，VM 零改动（ADR-04）。

#### 5.3.5 盘口与成交明细

| 项 | 规则 |
|---|---|
| 位置 | 图表右侧、同顶对齐；宽 = 图表行 30%（sm ≈102vp），上限 170vp；紧凑版 32%，上限 132vp |
| 顺序 | 五档标题 → 卖1~5 → 比例条 → 买1~5 → 明细标题 → 逐笔列表 |
| 比例条 | 红=委买占比、绿=委卖占比，5%~95% 钳制；停牌/未开盘隐藏 |
| 明细 | 20 条、可视约 4 条、区内滚动、时间倒序、按主动买卖着色 |
| 更新 | 1s 合并；档位变动闪一次（320ms），1s 内不重复 |
| 冻结 | 停牌/收盘后保留最后快照并整体置灰；明细不再追加 |
| 着色 | 五档价格相对**昨收**着色，不按相邻档 |

#### 5.3.6 资讯条、内容 Tab、动作栏

| 区块 | 规则 |
|---|---|
| 资讯条 | 单条，高 44vp；本期只展示 + 关闭，点击不跳转（无资讯模块，避免新增占位口径，见 §11-Q8） |
| 关闭 | 会话内按 code 记忆；失败整条隐藏且不占位 |
| 内容 Tab | 讨论/必读/研报/资金/资料（lg/xl 加公告）；默认讨论；`Tabs` + 每 Tab 独立 `Scroller` 保活；单 Tab 失败只降级自身 |
| 动作栏 | 通栏底栏；左三项（自选设置/股票PK/更多）点击区 ≥44vp；右「去交易」红底胶囊 ≥44vp、占宽 ≥40%；停牌/退市禁用 |
| 紧凑版 | 无资讯/内容 Tab/动作栏；四项动作进「⋯」 |

#### 5.3.7 状态机

```ts
export type DetailUiState =
  | 'loading' | 'ready' | 'firstLoadError' | 'chartError'
  | 'offlineWithCache' | 'offlineNoCache' | 'suspended' | 'newStock' | 'notFound';
```

映射严格按 FR-06 §2.5：首屏失败只留「返回」；图表失败保留盘口与动作栏；离线有缓存冻结置灰、无缓存错误态；404 隐藏动作栏。

---

### 5.4 M3 买入委托

#### 5.4.1 承载与层级

| 断点 | 壳 | 宽 | 高 |
|---|---|---|---|
| sm/md | 底部 sheet（`bindSheet`） | 近满宽（左右 8vp） | ≤90% / ≤88% |
| lg/xl | 居中模态（自定义覆盖层） | **640vp 恒定**（上限 88% 宽） | ≤82% |

**单容器两层**：`TradeSheet` 内部 `@Local step: 'edit' | 'confirm'`，**只渲染一层**（INV-T2）；确认层压在编辑层之上用同容器切换 + 150ms 过渡，不用两个弹窗叠开（ADR-05）。

#### 5.4.2 门禁（判定优先级）

```ts
export enum TradeGate {
  NeedLogin, NoAccount, Suspended, Delisted, Offline, ClosedSession, FundShort, Ready
}

export function resolveGate(s: AuthSession, a: AccountInfo | null, t: Tradable, online: boolean): TradeGate {
  if (!s.loggedIn) { return TradeGate.NeedLogin; }
  if (a === null || !a.opened || !a.canTrade) { return TradeGate.NoAccount; }
  if (t.status === 'suspended') { return TradeGate.Suspended; }
  if (t.status === 'delisted') { return TradeGate.Delisted; }
  if (!online) { return TradeGate.Offline; }
  if (t.status !== 'open' && t.status !== 'auction') { return TradeGate.ClosedSession; }
  if (a.maxBuyQty < 100) { return TradeGate.FundShort; }
  return TradeGate.Ready;
}
```

| 层 | 判定项 | 表现 |
|---|---|---|
| 入口 | NeedLogin / NoAccount / Suspended / Delisted | 未登录**放行**并弹登录，成功后回原标的自动续开；其余 toast 且不打开弹窗 |
| 弹窗内 | Offline / ClosedSession / FundShort | 提示条 + 主按钮禁用，字段仍可编辑 |
| 提交时 | 服务端校验 | 失败留在弹窗，按 `code` 映射文案 |

> 基线 C5 / DEC-07-04：**收盘可开单、按钮禁用**；这里 `ClosedSession` 落在弹窗内而不是入口，理由见 FR-07.10 的判定边界。

#### 5.4.3 字段与校验

```ts
export enum OrderErrorCode {
  PriceEmpty, PriceAboveLimit, PriceBelowLimit,
  QtyEmpty, QtyLot, QtyOver
}

export interface FieldError {
  field: 'price' | 'qty';
  code: OrderErrorCode;
}

export function validateOrder(draft: OrderDraft, t: Tradable, canBuy: number): FieldError[] {
  const errors: FieldError[] = [];
  if (!Number.isFinite(draft.price) || draft.price <= 0) {
    errors.push({ field: 'price', code: OrderErrorCode.PriceEmpty });
  } else if (draft.price > t.limitUp) {
    errors.push({ field: 'price', code: OrderErrorCode.PriceAboveLimit });
  } else if (draft.price < t.limitDown) {
    errors.push({ field: 'price', code: OrderErrorCode.PriceBelowLimit });
  }
  if (!Number.isFinite(draft.qty) || draft.qty <= 0) {
    errors.push({ field: 'qty', code: OrderErrorCode.QtyEmpty });
  } else if (draft.qty % 100 !== 0) {
    errors.push({ field: 'qty', code: OrderErrorCode.QtyLot });
  } else if (draft.qty > canBuy) {
    errors.push({ field: 'qty', code: OrderErrorCode.QtyOver });
  }
  return errors;
}
```

> 校验规则是**纯函数**（L2），只返回错误码；文案映射在 `TradeFormVM`（L3）完成，文案内容对齐 FR-07 §2.5，不在 L2 出现中文。

| 规则 | 实现 |
|---|---|
| 单一出口 | 只有 `validateOrder` 一个校验入口；点「买入」才校验；不通过**不得**进确认层 |
| 就近提示 | 错误渲染在价格/数量字段下方；多错按 价格 → 数量 顺序 |
| 价格 | 默认 `round(last,2)`；步进 ±0.01；`clamp(limitDown, limitUp)`；手输与步进双向同步；非法输入拒绝并保留原值 |
| 数量 | 默认 100；步进 ±100；上限 = `canBuy`；超额回填为可买（向下取整到手）并提示；仅 100 整数倍 |
| 涨跌停 | 由昨收推导（主板 ±10%），**禁止硬编码**稿内数值 |
| 停牌 | 价格锁最后快照，不可改 |

#### 5.4.4 提交、幂等与结果

```ts
@ObservedV2
export class TradeVM {
  @Trace step: 'edit' | 'confirm' = 'edit';
  @Trace submitState: 'idle' | 'submitting' | 'unknown' = 'idle';
  @Trace result: OrderResult | null = null;
  clientOrderId: string = TradeId.next();      // 进入弹窗生成一次，流程内复用
}
```

| 阶段 | 行为 |
|---|---|
| 提交 | 按钮 loading，关闭入口失效；重复点击直接丢弃；`submit(draft, 2000)` |
| 成功 | `accepted` → 记录委托号/状态 → toast → 700ms 后关闭回详情 |
| 失败 | `rejected` → 弹窗内原因（资金不足/超涨跌停/非交易时段/风控），保留输入可改可重试 |
| 超时 | 2s 无响应 → `unknown`：**不自动重发**，主按钮禁用，给「查询委托」 |
| 查询 | 调 `TradeGateway.query(clientOrderId)`，弹层展示 `clientOrderId`、委托号、状态、时间；**不做委托列表** |

**幂等**：`clientOrderId` 进入弹窗生成、重试复用、成功后作废；网关按它去重（INV-T1）。Mock 网关内部维护 `Set<string>` 模拟去重，重复提交返回同一 `orderId`。

#### 5.4.5 关闭矩阵

| 路径 | 编辑层 | 确认层 | 提交中 |
|---|---|---|---|
| 右上 X | 关闭丢弃 | 关闭整个流程 | **禁止** + toast |
| 点遮罩 | 关闭丢弃 | **不关闭** | **禁止** |
| 系统返回/侧滑 | 关闭 | 回编辑层（保留输入） | **禁止** |
| 切后台 | 保留 | 保留 | 保留并等待 |

实现要点：确认层遮罩绑定 `onClick` 判空；提交中 `onWillDismiss` 拦截 + `onBackPress` 拦截；所有关闭路径统一走 `TradeVM.tryClose()`，避免四套分支。

#### 5.4.6 三态按钮与键盘

- 按钮三态：可用（实心红）/ 禁用（灰底灰字 55%）/ loading（转圈 +「提交中」）（基线 C6）。
- 手输：点击数值切输入框；`type: InputType.NUMBER_DECIMAL`；失焦/回车提交；非数字拒绝。
- 键盘：容器整体上移，主按钮贴键盘上沿（距 8vp）；确认层不得被键盘覆盖（FR-07.2）。

---

### 5.5 M4 多窗比价

#### 5.5.1 宿主抽象（DEC-08-01）

```ts
export interface SlotLayout {
  index: number;
  x: number;
  width: number;
  zIndex: number;
  compact: boolean;
}

export interface WindowHost {
  readonly kind: 'pane' | 'window';
  layout(count: number, viewport: number): SlotLayout[];
  focus(index: number): void;
  destroy(index: number): void;
}
```

| 实现 | 本期 | 说明 |
|---|---|---|
| `PaneHost` | **先落** | 单页内并排 N 个 `DetailContent`，共享 `Navigation` 与全局 banner |
| `WindowHost` | 保留接入位 | 每窗一套 page；二期接入，验收口径不变 |

#### 5.5.2 布局计算

```ts
// PaneHost 布局计算
computeLayout(count: number, viewport: number): SlotLayout[] {
  if (count === 1) return [{ index: 0, x: 0, width: viewport, zIndex: 0, compact: viewport < 360 }];
  if (count === 2) {
    const w: number = Math.floor((viewport - 8) / 2);   // 中缝 8vp
    return [
      { index: 0, x: 0, width: w, zIndex: 0, compact: w < 360 },
      { index: 1, x: w + 8, width: w, zIndex: 0, compact: w < 360 }
    ];
  }
  const w: number = Math.floor(viewport / 3 + 6);       // 三窗叠放
  return [0, 1, 2].map((i: number): SlotLayout => ({
    index: i, x: i * (w - 12), width: w, zIndex: i, compact: w < 360
  }));
}
```

| 窗数 | 布局 | 中缝/重叠 | 圆角 | 指示器 |
|---|---|---|---|---|
| 1 | 铺满 | — | 14 | 无 |
| 2 | 1:1 | 8vp | 14 | 无 |
| 3 | 卡片叠放 | 重叠 12vp，焦点置顶 | 16 | 顶部 3 点 |

> 三窗公式保证整体不溢出、所有关闭按钮可见（基线 C8），`x + width ≤ viewport` 由单测断言。

> **实现备注（M4，2026-11-12；口径已确认 DEC-08-10/11）**
> - 本项目无 UT 运行器，`x + width ≤ viewport` 改为 `PkLayout.layoutViolations()` 在 debug 首次布局时打印（`pk_layout_violation`，正常不出现）。
> - 卡宽 <360vp 走 FR-06.11 紧凑版；**<240vp 再走 mini 版**（只留报价头 + 周期 Tab + 图表，收起指标/资讯/盘口），否则折叠屏 3 窗每窗约 165vp 会出现标签与数值重叠。阈值 240vp 为定案值，不按窗数硬编码。
> - 指示器**内联在 `PkToolbar` 左侧**（3 窗才出现，当前点拉长高亮），**仅点击切焦点**；不做卡片顶部浮层、不做滑动切换（DEC-08-10）。
> - 窗卡位置由 `computeLayout(count, viewport)` 现算（纯函数），窗数/宽度变化即重排，无需缓存坐标系。
> - 窗内图表实例的容器宽度会随窗数变化：`ChartArea` 在 `viewportWidth` 变化后延迟 80ms 重设 series 并 resetZoom，否则 mpchart 会沿用旧视口的缩放，K 线聚在一侧。

#### 5.5.3 换股、焦点、关闭

| 动作 | 规则 |
|---|---|
| 换股 | 点击窗卡工具栏「换股」→ **自选选择器**（DEC-08-08；二期替换为 FR-05 搜索，见 §11-Q9）；新窗取 PK 组中未占用标的 |
| 交换 | 目标 code 已被他窗占用 → **两窗交换**，不产生重复（DEC-08-03） |
| 焦点 | 点击窗体 → 置顶 + 边框高亮，全屏唯一；指示器**仅点击**切换（DEC-08-10） |
| 关闭 | 关闭即销毁该窗 VM/图表/订阅；焦点移交相邻；最后一窗关闭 = 退出 PK |
| 返回 | 返回键退出 PK 回来源页（不逐窗回退） |

> **实现备注（M4，2026-11-12；口径已确认 DEC-08-07~09）**
> - 换股入口做成窗卡工具栏的「换股」按钮（不点标题）：报价头已展示名称/代码，再加标题会重复；FR-08.4「标题可点」语义等价。
> - 详情入口（动作栏「股票PK」/ 标题栏 ⧉）只带 1 只时，进入 PK 后**自动拉起选择器**补齐第 2 只；取消则保留 1 窗 +「+」。
> - PK 内退出用系统返回或「关最后一窗」；标题栏不放 ⧉（Q5-b 已关闭：不做「退出 PK」图标）。

#### 5.5.4 订阅预算与降频

```ts
export type SinkTier = 'focus' | 'normal' | 'background';

export interface QuoteSink {
  onPatch(patch: QuotePatch): void;
}

export interface SubscriptionHandle {
  release(): void;
}

export class SubscriptionRegistry {
  acquire(code: string, sink: QuoteSink, tier: SinkTier): SubscriptionHandle { /* refCount + fanout */ }
  setTier(handle: SubscriptionHandle, tier: SinkTier): void { /* 5s/1s */ }
  activeCount(): number { /* 可查，供调试面板断言 */ }
}
```

| 规则 | 值 |
|---|---|
| 逻辑订阅 | 3 窗 ≤3 路；同 code 合并后更少（AC-83） |
| 降频 | 非焦点 1s → 5s；恢复焦点立即补一次全量，首帧 ≤300ms |
| 退订 | 关闭窗/退出详情 → `release()`；全部关闭后 `activeCount() === 0` |
| 一窗故障 | 只该窗局部错误，不全局置灰 |

#### 5.5.5 同步分级与持久化

| 级别 | 项 |
|---|---|
| 必须一致 | 涨跌配色、空值规则、时间轴刻度、交易状态文案、断线置灰 55% |
| 可选同步 | 周期（一次性按钮，作用于全部窗，默认不同步） |
| 禁止同步 | 滚动位置、内容 Tab、图表缩放、十字光标 |

**持久化**：`PersistenceV2` 只存 `{ codes, periods, focus }`；恢复失败降级单窗并提示；冷启恢复 ≤800ms。

#### 5.5.6 降级链

```
内存告急 / 超预算
  1. 关闭非焦点窗（保留焦点窗）
  2. 非焦点窗降频（1s → 5s）
  3. 退化为单窗
```

每次降级给一次 toast 说明；第 4 窗被拦：`+` 禁用 + 提示「最多 3 只对比」（不挤掉已有窗）。

#### 5.5.7 全局 banner 与窗内表现

- banner 由 `PkHost` 所在的 page 层唯一渲染，`DetailContent` 内不得出现（FR-06.11）。
- 断线：所有窗冻结 + 置灰 55% + 页面级一条 banner；切窗时 banner 不重建、不闪。

---

### 5.6 M5 全局质量

#### 5.6.1 连接状态机

```ts
export enum ConnectionState { Online, Weak, Offline, Delayed }

@ObservedV2
export class ConnectionHub {
  @Trace state: ConnectionState = ConnectionState.Online;
  private miss: number = 0;
  private retry: number = 0;
  private readonly backoff: number[] = [1000, 2000, 4000, 8000, 16000, 30000];
  onHeartbeatOk(): void { /* state=Online; miss=0; retry=0 */ }
  onHeartbeatTimeout(): void { /* miss++ → 2: Weak; 3: Offline + 调度重连 */ }
}
```

| 事件 | 迁移 |
|---|---|
| 连续 2 次心跳超时 | `weak` |
| 心跳失败 ≥3 次 / 断网 | `offline` |
| 服务端标记延迟 | `delayed` |
| 重连成功 | `online`，5s 内提示消失并刷新 |

**退避**：1s → 2s → 4s → 8s → 16s → 30s 封顶，恢复回 1s；**单一调度器**，页面禁止自带定时器（CC-7.5）。

#### 5.6.2 断线数据处置（CC-7.6）

| 动作 | 实现 |
|---|---|
| 冻结 | `QuoteBus` 停止 apply，保留 `QuoteCache` 最后一帧 |
| 置灰 | 列表/卡片容器 `opacity(0.55)`；表头与名称列仍可读 |
| 提示 | 唯一 banner，文案「行情连接中断，数据可能延迟」 |
| 不显示行内时间 | 行内不渲染「最后更新时间」 |
| 恢复 | 5s 内 banner 消失、去灰、补一帧全量 |

`weak`/`delayed` 不置灰，只保留 banner 与角标（`delayed` 角标附在涨跌幅列头）。

#### 5.6.3 字号与缩放

| 项 | 规则 |
|---|---|
| 档位 | `fontScale ∈ {1.0, 1.3, 1.45}`，由系统字体设置换算到最近档 |
| 字体 | `fp` 自动缩放；局部用 `.maxFontScale(1.45)` 防极端值 |
| 列宽 | `round(base × fontScale)`；名称列 `max(base×scale, 视口-数字列)` |
| 指标/卡片 | 每档减 1 列，下限 1 列；不减字号、不省略号 |
| 列表 | 11 列不减（CC-6.5）；只增加横滑 |
| 行高 | `max(56, round(56 × fontScale))`，保证 1.45× 两行不重叠 |

#### 5.6.4 无障碍

| 对象 | 要求 |
|---|---|
| 列表行 | 朗读名称、代码、最新价、涨跌、涨跌幅；停牌/新股追加状态 |
| 表头 | 朗读列名 + 排序方向 |
| 图表 | 提供替代文本摘要（周期、区间、开高低收、涨跌幅），**不逐点朗读** |
| 详情顺序 | 状态 → 价格 → 涨跌 → 指标 → 盘口 |
| 交易读屏顺序 | 标的 → 账户 → 价格 → 数量 → 可买 → 买入；步进按钮可独立聚焦 |
| toast | 系统 toast 由读屏播报；自绘 toast 需发无障碍事件 |
| 多窗 | 每窗独立读屏域；指示器朗读「第 2 个，共 3 个」 |

#### 5.6.5 埋点与合规

```ts
export interface AnalyticsParam {
  key: string;
  value: string;
}

export interface Analytics {
  track(event: string, params: AnalyticsParam[]): void;
}
```

- 事件：`page_view`、`period_switch`、`action_click`、`entry_click`、`modal_open`、`value_change`、`confirm_view`、`submit`、`result_success|result_fail|result_unknown`、`pk_entry`、`group_created`、`window_open|window_close`、`code_swap`、`period_sync`、`degrade`、`exit_pk`。
- 合规：账号、持仓、金额、委托明细**不上报三方**；日志不落明文；埋点失败静默、不阻塞交互。
- 队列：内存队列 + 批量上报；页面退出 flush 一次（不阻塞 UI）。

#### 5.6.6 性能探针

- `PerfProbe.mark(name)`：首屏、图表首帧、弹窗打开、切窗；debug 构建写日志，release 只计数。
- 帧率：连续滚动/切窗时用系统帧回调统计，超阈值打点。
- 内存：切 20 次周期、开关 10 次弹窗、关闭全部窗后，与基线对比（±5%）。

---

## 6. 横切机制

### 6.1 断点与形态服务（ADR-02）

**基线阈值与设备对应**：

| 断点 | 基线 §6 宽度 | 本文采用 | 典型设备 / 样张宽度 |
|---|---|---|---|
| sm | <600（375） | `< 600` | 直板机 375 |
| md | 600–840（720） | `[600, 840)` | 折叠展开 720 |
| lg | 840–1200（1000） | `[840, 1180)` | 阔折叠 1000 |
| xl | >1200（1180） | `≥ 1180` | 平板 1180（左栏 523 + 右栏） |

> **必须澄清**：基线 §6 写「xl >1200」却标注样张 1180，二者互斥。本文取 `xl ≥ 1180`，否则平板 1180 会落进 lg，失去「左栏 + 右栏」形态，与 §6 的「xl 左栏 ≈523」自相矛盾。此差异登记为 §11-Q1，**不阻塞开发**（一个常量可改）。

**为什么不直接用系统断点**：系统 `WidthBreakpoint` 的 lg 上界是 1440，平板 1180 会被判成 lg；而产品要求 1180 就进分栏。因此自建 `BreakpointService`，只借用系统的**窗口尺寸事件**，阈值由产品定义（ADR-02）。

```ts
export type WidthBp = 'sm' | 'md' | 'lg' | 'xl';

@ObservedV2
export class BreakpointService {
  @Trace widthBp: WidthBp = 'sm';
  @Trace viewportWidth: number = 0;      // vp
  @Trace isSplit: boolean = false;       // xl：列表 + 右栏
  @Trace listColumns: number = 11;       // 固定 11，保留字段便于二期

  apply(widthVp: number): void {
    this.viewportWidth = widthVp;
    if (widthVp < 600) {
      this.widthBp = 'sm'; this.isSplit = false;
    } else if (widthVp < 840) {
      this.widthBp = 'md'; this.isSplit = false;
    } else if (widthVp < 1180) {
      this.widthBp = 'lg'; this.isSplit = false;
    } else {
      this.widthBp = 'xl'; this.isSplit = true;
    }
  }
}
```

**规则**：

1. 每个断点分支**显式赋值全部派生状态**（`isSplit` 等），不依赖初始值——避免宽→窄残留。
2. 断点只驱动布局与显隐，**不在回调里发请求**。
3. 尺寸监听 100–200ms 防抖；`windowSizeChange` 注册在 `loadContent` 回调内，`onWindowStageDestroy` 反注册。
4. `px → vp` 用 `UIContext.px2vp`，不用全局 `px2vp`（已废弃）。
5. 折叠/展开、悬停由 `foldStatusChange` 与尺寸变化组合判定；**不重建页面**，只切换布局参数（保证 AC：折叠↔展开不丢状态）。

**共享方式**：`BreakpointService` 经 `AppStorageV2.connect(BreakpointService, 'breakpoint', () => new BreakpointService())` 提供；组件持 `@Local` 引用读 `@Trace` 字段（不用 `@StorageProp`，避免字符串断点与枚举值混用导致比较永假）。

### 6.2 主题与资源组织

| 资源 | 位置 | 说明 |
|---|---|---|
| 颜色 | `resources/base/element/color.json` | 全部语义 token；组件禁写字面量 |
| 尺寸 | `resources/base/element/float.json` | 行高、间距、圆角、点击区 |
| 文案 | `resources/base/element/string.json` | 中文全部入资源；**含占位 5 条** |
| 图标 | `resources/base/media/` | 统一 SVG；占位空态用统一灰图标位，不新增插画 |

**深色模式预留**：本期只建 `base`。二期新增 `resources/dark/element/color.json` 即可全局生效，**组件零改动**——这是「颜色全走 token」的唯一目的（G7）。

**禁止**：`Color.Red` 等系统色直接用于业务语义（涨跌必须走 `color_price_up/down`，否则深色适配时无法区分）。

### 6.3 i18n 与占位文案校验

| key | 文案 |
|---|---|
| `coming_soon_add_watchlist` | 添加自选下阶段开放 |
| `coming_soon_card_view` | 卡片视图下阶段开放 |
| `coming_soon_home` | 首页下阶段开放 |
| `coming_soon_news` | 最新资讯下阶段开放 |
| `coming_soon_market` | 行情下阶段开放 |
| `placeholder_home_title` | 首页 |
| `placeholder_news_title` | 最新资讯 |
| `placeholder_market_title` | 行情 |
| `retry` / `loading` / `empty_watchlist_desc` | 重试 / 加载中 / 暂无自选，可添加后查看 |

**校验测试**（进 CI，防止文案漂移）：

```ts
// 断言：所有 coming_soon_* 均以「下阶段开放」结尾
// 断言：不含禁用变体（敬请期待/即将上线/暂未开放/Coming/~/!/！）
// 断言：不含版本号片段（v1、一期、（二期））
```

### 6.4 错误与降级分级

| 级别 | 场景 | 表现 | 是否可重试 |
|---|---|---|---|
| L1 局部 | 图表失败、单窗失败、单 Tab 失败 | 局部错误块 | 是 |
| L2 页面 | 详情首屏失败 | 整页错误 + 重试 | 是 |
| L3 全局 | 断线 | 冻结 + 置灰 + 唯一 banner | 自动退避 |
| L4 致命 | 未捕获异常 | 兜底页 + 上报；不白屏 | 返回首页 |

**原则**：能降级到 L1 的，绝不升到 L2；L3 期间不叠加 L1/L2 的错误块（避免一个断线看到四五个红叉）。

### 6.5 调试开关与构建裁剪

| 开关 | 实现 | 裁剪 |
|---|---|---|
| 调试面板入口 | 设置页长按 5 次 / debug 构建自动显示 | 构建 profile 的 DEBUG 标记 |
| 切断线/延迟/失败注入 | `MockScript` 直连 `ConnectionHub`/Provider | 同上 |
| 模拟 3 窗 | `PkSessionVM.testBuild(3)` | 同上 |
| 强制 Canvas 图表 | `FeatureFlag.chartEngine = 'canvas'` | 保留（用于线上降级） |

> FeatureFlag 保留在 release，但只读常量配置；Mock 注入代码在 release 必须被裁剪，避免误触。

### 6.6 工程红线与 CI 门禁

**红线清单**（详见附录 C，CI 用 grep 检查）：

1. 禁止 V1 装饰器残留（`@State|@Prop|@Link|@ObjectLink|@Provide|@Consume`）。
2. 禁止 `view/`、`pages/` 内出现十六进制颜色。
3. 禁止全局 `router.push|replace`（统一走 `NavPathStack`）。
4. 禁止 `pages/`、`view/` 内 `setInterval`（定时器只在 `commons/data/`）。
5. 禁止 `: any`、禁止 `as any`。
6. 禁止在 `DetailContent` 内调用 `pushPath`。
7. 禁止业务层直接 import 图表库符号（只能经 `ChartEngine`）。
8. 禁止跨层 import 与就地 `new Mock*`（R-01~R-09，见 §3.1.10）。

**门禁三步**：`lint` 通过 → `ut` 通过 → `redline` 无命中。任一失败不允许合入。

---

## 7. 性能设计

### 7.1 预算总表

| 场景 | 指标 | 出处 |
|---|---|---|
| 冷启动首屏骨架 | ≤300ms | CC-1.2 |
| 首屏内容 | ≤1s | CC-1.2 |
| 列表 50 行滚动 | ≥55fps，无白块 | CC-1.2 / AC-02 |
| 单行推送刷新 | 只更新该行 | FR-02.7 |
| 详情头部 | ≤500ms（P90） | FR-06.14 |
| 图表首帧 | ≤800ms | FR-06.14 / AC-65 |
| 切周期（有缓存） | ≤300ms | FR-06.14 |
| 切 20 次周期内存 | 无持续增长 | AC-65 |
| 交易弹窗打开 | ≤200ms（P90） | FR-07.14 |
| 编辑↔确认 | ≤150ms | FR-07.14 |
| 提交反馈 | 2s 内必出 | FR-07.14 / AC-76 |
| 3 窗同屏 | ≥50fps | FR-08.12 / AC-86 |
| 切窗首帧 | ≤300ms | FR-08.7 |
| 冷启恢复 PK | ≤800ms | FR-08.8 |
| 断线恢复 | 5s 内提示消失并刷新 | CC-7.6 |

### 7.2 关键路径优化

| 路径 | 手段 |
|---|---|
| 启动 | 首屏只建 TabShell + 自选列表；详情/图表按需加载；Provider 不阻塞首帧（先骨架，后快照） |
| 列表滚动 | 常量级偏移同步（§5.2）、业务 key、格式预计算、`cachedCount(6)` |
| 详情 | 头部与图表分阶段渲染；图表数据 5min 缓存；切周期取消在途 |
| 交易 | 弹窗预构建表单结构；校验同步；提交走 Promise 不阻塞 UI |
| 多窗 | 订阅合并 + 分级节流；非焦点窗 5s；关闭即释放图表与订阅 |
| 内存 | 图表实例 `dispose()`；订阅 `release()`；图表数据 LRU 上限（code+period ≤ 12 项） |

### 7.3 度量与回归

| 项 | 方法 | 频率 |
|---|---|---|
| 帧率 | 系统帧回调 + SmartPerf/DevEco Profiler 录制 | V0、每里程碑 |
| 首屏/首帧 | `PerfProbe` 打点（debug 日志） | 每次构建 |
| 组件更新次数 | DevEco Inspector / 自定义计数 | 单行刷新验证 |
| 内存 | Profiler 快照对比（切周期 20 次、开关 10 次、关闭全部窗） | M2/M3/M4 收尾 |
| 回归 | 升 SDK 小版本后回归「11 列横滑、多窗、图表」 | 每次工具链变更 |

**阈值落库**：所有实测值写入 `docs/perf-report.md`，与预算表逐行对比；超标必须在里程碑验收前给出结论（优化或改口径，改口径需产品确认）。

---

## 8. 可测性与验收

### 8.1 测试分层

| 层 | 范围 | 工具 | 门禁 |
|---|---|---|---|
| 单元测试 | 格式化、校验器、布局数学、状态机、订阅注册表、占位文案 | 本地 UT 框架（Local Test） | 必须全绿 |
| UiTest | 四 Tab、列表横滑与冻结、详情 8 周期、交易三态、多窗 3 窗、断线 | UiTest | P0 用例全绿 |
| 人工 checklist | 折叠真机（折叠/展开/悬停）、字号三档、无障碍读屏、深链 | 真机 | 验收前完成 |
| 性能 | 预算表逐项 | Profiler | 达标 |

### 8.2 AC → 实现 → 验证映射

| AC | 要点 | 实现点 | 验证 |
|---|---|---|---|
| AC-01/05/10 | 骨架/空/失败 | `StateView` + `Skeleton` | UiTest + 目视 |
| AC-02 | 50 行 ≥55fps | §5.2 冻结表 | Profiler |
| AC-03/04 | 单行刷新、1s 合并 | `QuoteBus` | 组件更新计数 |
| AC-06 | 停牌/新股行 | `WatchRowVM` + 空值规则 | UiTest |
| AC-07 | 连接状态与提示 | `ConnectionHub` + `GlobalBanner` | UiTest（注入断线） |
| AC-08 | 涨红跌绿平灰 | token + `formatPct` | 快照测试 |
| AC-09 | 1.3× 不截断 | `rowHeight` 公式 | 三档目视 + UiTest |
| AC-11 | 11 列/冻结/排序 | §5.2 | UiTest |
| AC-12 | 分组与指数条 | `GroupTabs` + `IndexSet` | UiTest |
| AC-13 | 1.0/1.3 无横滑、1.45 允许 | `computeTableMetrics` | 单测（数值断言） |
| AC-48~52 | 分组不变量、搜索同源、排序单源、字号、banner 单例 | 模型约束 + `SortStore` + `GlobalBanner` | 单测 + UiTest |
| AC-53/54 | 入口/返回恢复、壳内容同一 | `AppRouter` + `DetailContent` | UiTest |
| AC-55/56 | 头部/指标 | `QuoteHeader` + `MetricPanel` | UiTest |
| AC-57 | 8 周期 + 点击刷新 + 三方库 | `ChartVM` + `ChartEngine` | UiTest + 目视 |
| AC-58 | 盘口/明细 1s 合并 | `OrderBookVM` | UiTest |
| AC-59 | 资讯条失败隐藏 | `NewsBar` | UiTest（注入失败） |
| AC-60 | 内容 Tab 惰性保活 | `ContentTabs` | UiTest |
| AC-61 | 动作栏四动作 | `ActionBar` | UiTest |
| AC-62 | 断线冻结置灰 | CC-7.6 统一实现 | UiTest |
| AC-63 | 六形态无截断 | `DetailContent` + `compact` | 目视 + 截图比对 |
| AC-64 | 读屏顺序/替代文本 | `accessibilityText` | 真机读屏 |
| AC-65 | 性能/内存 | `ChartEngine.dispose` | Profiler |
| AC-66~76 | 交易入口→结果 | §5.4 | UiTest（含 Mock 注入） |
| AC-77~86 | 多窗 | §5.5（`PkVM` / `PkLayout` / `DetailSubscriptionRegistry` / `PkStore` / `PkHost`） | UiTest + 真机折叠 |

> **实现备注（M4）**：本项目暂无 UT 运行器，「布局数学」与「订阅注册表」改为可观测断言——
> `PkLayout.layoutViolations()` 在 debug 打印 `pk_layout_violation`（正常不出现）；
> `DetailSubscriptionRegistry.stats()` 输出 `subs=/sinks=/codes=`，由 `DetailPerf` 的 `subs_acquire/subs_tier/subs_release` 与 PK 调试面板「订阅统计」核对（AC-83）。接 Local Test 后这两项迁回单测。

### 8.3 设备矩阵（基线 §8.1）

| 场景 | 直板 | 折叠展开 | 阔折叠 | 平板 |
|---|---|---|---|---|
| 11 列横滑 | ✓ | ✓ | ✓ | ✓（左栏） |
| 详情页/右栏 | ✓ | ✓ | 待补稿（按 sm 补） | ✓ |
| 买入/确认 | ✓ | ✓ | 待补稿（按 lg 居中） | ✓ 居中 |
| 双窗/三窗 | — | ✓ 真机（460/940vp） | — | ✓ 模拟器（1280vp） |
| 折叠↔展开不丢状态 | — | ✓ 真机 | ✓ 真机 | — |
| 悬停态 | — | ✓ 真机 | — | — |

> 阔折叠缺稿两项按「lg 规则」实现（弹窗 640vp 居中、详情全屏），设计补图后只调视觉、不改结构。

### 8.4 缺陷门禁

| 级别 | 定义 | 发布门禁 |
|---|---|---|
| P0 | 崩溃、白屏、交易错单、数据串窗、冻结失效 | 清零 |
| P1 | AC 不通过、性能不达标、无障碍不可用 | 清零或产品书面接受 |
| P2 | 视觉偏差、文案、非关键体验 | 可带入下一里程碑 |

---

## 9. 交付计划

### 9.1 里程碑与 DoD

| 阶段 | 人日 | 交付 | DoD（可验收） |
|---|---|---|---|
| V0 技术验证 | 3 | 4 个 spike + 报告 | 50 行冻结表 ≥55fps；图表库 API 20 跑通 8 周期；折叠切换状态不丢；V2+Navigation 样例绿 |
| M0 外壳 | 4.5 | 三层模块骨架、四 Tab、路由、深链、token、占位组件、状态视图 | 8 个模块（1 HAP + 7 HAR）可编译、依赖白名单生效；四 Tab 可切、占位文案合规、深链可进详情、三态可见 |
| M1 列表 | 11 | 冻结表、指数条、分组、排序、四形态、状态矩阵 | AC-11/12/13 通过；AC-02 达标；平板横滑可用 |
| M2 详情 | 13 | 页/右栏/紧凑三形态、8 周期、盘口明细、内容 Tab、动作栏 | AC-53~63 通过；首帧/切周期达标 |
| M3 交易 | 6 | 弹窗两层、校验、三态结果、关闭矩阵 | AC-66~74 通过；幂等与超时用例通过 |
| M4 多窗 | 8 | 2/3 窗、换股、同步、降频、降级、恢复 | AC-77~85 通过；3 窗 ≥50fps |
| M5 质量 | 6 | 断线、字号、无障碍、埋点、性能 | AC-48~52 与性能项通过；真机 checklist 完成 |

### 9.2 WBS 摘要（按模块拆到可认领粒度）

| 模块 | 任务 | 人日 |
|---|---|---|
| V0 | 冻结表原型；图表库 spike；折叠/断点 spike；V2+Navigation spike；报告 | 0.5 + 1 + 0.5 + 0.5 + 0.5 |
| M0 | 三层模块骨架与依赖声明；TabShell/底栏/安全区；路由与深链；token/占位/状态视图；CI 门禁 | 1.5 + 1 + 0.5 + 1 + 0.5 |
| M1 | 表格几何与结构；名称列同步/渐隐/滚动条；排序与空值；指数条与分组；状态矩阵与特殊行；四形态与字号；无障碍；性能调优 | 2 + 2 + 1 + 1.5 + 1.5 + 1.5 + 0.5 + 1 |
| M2 | 壳内容分离；头部与指标；图表适配层与 8 周期；盘口与明细；资讯条/内容 Tab/动作栏；紧凑版；状态机与错误；性能与释放 | 1.5 + 1.5 + 3 + 2 + 1.5 + 1.5 + 1 + 1 |
| M3 | 弹窗壳与两层；字段与步进/手输；校验；提交/幂等/超时；关闭矩阵；无障碍与埋点 | 1 + 1.5 + 0.5 + 1.5 + 0.5 + 1 |
| M4 | WindowHost/PaneHost；布局与叠放；焦点/关闭/换股；订阅合并与降频；同步与持久化；降级与恢复 | 1 + 1.5 + 1.5 + 1.5 + 1 + 1.5 |
| M5 | 连接状态机与 banner；字号与断点收口；无障碍；埋点；性能测量与回归 | 1.5 + 1 + 1.5 + 1 + 1 |

### 9.3 并行与集成

- **关键路径**：V0 → M2 → M4；M1 与 M2 可并行（双人）。
- **契约冻结**：V0 结束即冻结三 Provider 接口与实体字段；之后只增不改，避免 M1/M2 互相等待。
- **集成节奏**：每日一次主干构建；功能用 FeatureFlag 隔离（`ff_multiwindow`、`ff_chart_canvas`）；每周五演示。
- **顺序建议**：第 1 周 V0 + M0；第 2–3 周 M1 与 M2 并行；第 4 周 M2 收尾 + M3；第 5 周 M4；第 6 周 M5 + 验收；第 7 周缓冲。

### 9.4 交付物清单

| 交付物 | 位置 | 责任 |
|---|---|---|
| 源码与工程 | 仓库主干 | 开发 |
| 本设计说明书 | `docs/phase1-technical-design.md` | 技术负责人 |
| V0 验证报告（含帧率/版本/结论） | `docs/v0-spike-report.md` | 开发 |
| 性能报告（预算 vs 实测） | `docs/perf-report.md` | 开发 + 测试 |
| 用例（UiTest + 人工 checklist） | [validation/fr02-test-cases.md](../validation/fr02-test-cases.md)、[validation/fr03-test-cases.md](../validation/fr03-test-cases.md)，新增 fr06–08 用例同目录 | 测试 |
| 埋点字典 | 附录 B | 开发 + 产品 |
| 无障碍自检表 | 附录（§8.2 + §5.6.4） | 开发 |

---

## 10. 风险与应对

| # | 风险 | 触发信号 | 影响 | 应对 |
|---|---|---|---|---|
| R2 | 11 列冻结横滑是 ArkUI 最难交互 | V0 帧率 <55fps 或错位 | M1 返工，关键路径阻塞 | 方案 C + 双兜底（方案 B/无虚拟化）；V0 先验 |
| R3 | 三窗图表叠加性能与内存 | 3 窗 <50fps 或内存超基线 5% | M4 不达标 | 订阅合并 + 非焦点 5s + 图表降采样；阈值先测后定 |
| R4 | 图表库与 V2/多实例不兼容 | 切周期崩溃、多窗花屏 | M2/M4 返工 | `ChartEngine` 隔离；Canvas 兜底（+3~5 人日） |
| R5 | 全 Mock，真实接入在二期 | 契约与真实网关不一致 | 二期重写 | 契约按真实定义；Mock 与 Real 同接口；契约冻结评审 |
| R6 | 三处占位入口影响体验 | 评审/试用反馈 | 体验扣分 | 产品已知悉接受；文案统一、无二级占位 |
| R16 | 测试设备低于 API 20 装不上包 | 安装失败 | 验收阻塞 | 验收前统一升 HarmonyOS 6.x 或借设备 |
| T1 | 断点阈值 1180/1200 歧义 | 平板形态不符预期 | 布局返工 | §11-Q1 尽快定；常量集中，一处改 |
| T2 | 多窗「换股」依赖搜索（本期无搜索） | 换股不可用 | AC-80 无法验收 | 本期用「自选选择器」替代（§11-Q9） |
| T3 | 表头不可横向拖拽 | 验收提出 | 体验/AC 争议 | 先按已知取舍实现；如需可 +0.5 人日 |
| T4 | 冻结表与读屏焦点冲突 | 读屏跳焦 | 无障碍不达标 | 行级 `accessibilityText` + 焦点顺序单测 |
| T5 | i18n 漏文案/硬编码 | CI 红线命中 | 评审打回 | 红线 grep + 评审 checklist |
| T6 | Mock 数据不覆盖边界（负市盈率、涨跌停） | 边界 bug 漏到验收 | 返工 | 12 只数据集强制覆盖 8 类场景；用例逐类过 |

---

## 11. 待确认与本文提出的修正（差异登记）

> 以下 10 项均**不阻塞开工**：已有默认值，开发按默认推进；确认后只改常量或文案。

| # | 事项 | 冲突/缺口 | 本文默认 | 需谁确认 |
|---|---|---|---|---|
| Q1 | xl 断点阈值 | 基线 §6「>1200」与样张「1180」互斥 | `xl ≥ 1180`（否则平板无分栏） | 产品 + 设计 |
| Q2 | 图表周期契约 | FR-06 §3 枚举缺 `y`（正文 8 周期） | 契约补 `'y'`，8 周期全实现 | 技术（回写 FR-06） |
| Q3 | 1.45×「只降列」适用范围 | G8 说「只降列」，CC-6.5 禁「隐藏列」 | 列表 11 列不减；指标/卡片降列 | 产品 |
| Q4 | 交易断线处置 | FR-07 要求「禁止提交、不置灰详情」，CC-7.6 要求全局置灰 | 详情置灰；交易弹窗内只提示不置灰 | 技术（回写 CC-7.6） |
| Q5 | 三窗第 3 窗关闭可达性 | 基线 C8 要求可见，设计稿仅露 55vp 且无控件 | 12vp 重叠 + 顶部指示器 + 关闭按钮常显 | 设计补图 |
| Q6 | 表头是否支持横向拖拽 | 需求未写 | 仅数据区可拖；表头点击排序 | 产品 |
| Q7 | 指数条运营卡片 | 设计稿有 1 张卡片，基线只定义 N 项指数 | 本期不做运营位 | 产品 |
| Q8 | 资讯条点击行为 | FR-06.5 说「点击进入资讯详情」，但本期无资讯模块 | 本期只展示 + 可关闭，不跳转（避免新增占位） | 产品 |
| Q9 | 多窗换股依赖搜索 | FR-08.4 复用 FR-05 搜索，但本期搜索无入口 | 本期换股用「自选选择器」（从自选挑未占用标的） | 产品 + 技术 |
| Q10 | 「查询委托」范围 | FR-07.8 要求查询入口，本期无委托列表 | 只查当前 `clientOrderId` 的本地回执，不做列表 | 产品 |

**建议回写动作**（本迭代内完成，避免文档分叉）：

1. FR-06 §3 的 `period` 枚举补 `'y'`（Q2）。
2. CC-7.6 增补「交易类页面：禁止提交 + 弹窗内单条提示，不置灰整个详情页」（Q4）。
3. 基线 §6 的 xl 阈值与样张统一（Q1）。
4. 基线 §4 G8 明确「只降列」仅适用于指标面板与卡片（Q3）。

---

## 12. 附录

### 附录 A 常量总表（唯一来源）

| 常量 | 值 | 用于 |
|---|---|---|
| 列宽 base（名称…市净率） | 112 / 76 / 70 / 78 / 82 / 68 / 78 / 66 / 66 / 70 / 68 | 11 列 |
| 列宽合计 | 834vp（1.0×）/ 1084（1.3×）/ 1209（1.45×） | 横滑判定 |
| 行高 / 表头高 | 56 / 40（× fontScale） | 表格 |
| 自选上限 / Mock 数据集 | 50 只 / ≥12 只 | 列表 |
| 断点 | 600 / 840 / 1180 | 四形态 |
| 指数条条目 | 与当前 Tab 的列表行数一致（逐股票），超出可视宽度横向滚动 | 指数条 |
| 骨架 / 首屏 | 300ms / 1s | 启动 |
| 图表周期数 | 8 | 详情 |
| 分时点数 / K 线默认 / 上限 | 241 / 120 / 500 | 图表 |
| 图表缓存 | 5min | 切周期 |
| 盘口宽度 | 30%（sm 102vp，上限 170vp）；紧凑 32%（上限 132vp） | 盘口 |
| 比例条钳制 | 5% ~ 95% | 盘口 |
| 明细条数 / 可视 | 20 / 4 | 盘口 |
| 资讯条高 / 动作按钮高 | 44vp / ≥44vp | 详情 |
| 主按钮占宽 | ≥40% | 动作栏 |
| 交易弹窗宽 / 高 | 640vp / ≤90%（sm）、≤88%（md）、≤82%（lg/xl） | 交易 |
| 价格步进 / 数量步进 | 0.01 / 100 | 交易 |
| 提交超时 / 成功关闭 | 2s / 700ms | 交易 |
| 弹窗打开 / 层切换 | 200ms / 150ms | 交易 |
| 多窗上限 / 中缝 / 重叠 | 3 / 8vp / 12vp | 多窗 |
| 紧凑阈值 | 360vp | 多窗 |
| 非焦点降频 | 1s → 5s | 多窗 |
| 退避 | 1/2/4/8/16/30s | 连接 |
| 断线置灰 | 55% | 全局 |
| 恢复提示 | 5s | 连接 |
| 防重 | 300ms | 路由/入口 |
| toast | 1.8s | 占位 |

### 附录 B 埋点字典（本期）

| 事件 | 关键字段 | 触发 |
|---|---|---|
| `page_view` | `page`、`code?`、`from?` | 页面可见 |
| `entry_click` | `code`、`source`、`blocked` | 点「去交易」 |
| `modal_open` | `code`、`account`、`canBuy` | 交易弹窗打开 |
| `value_change` | `field`、`old`、`new`、`input` | 价格/数量变更 |
| `confirm_view` | `price`、`qty` | 进入确认层 |
| `submit` / `result_*` | `clientOrderId` / `orderId`、错误码（金额脱敏） | 提交与回执 |
| `pk_entry` / `group_created` | 入口、组大小 | 建立 PK |
| `window_open` / `window_close` | 窗序、窗数 | 开关窗 |
| `code_swap` / `period_sync` | 源/目标窗、周期 | 换股/同步 |
| `degrade` | 原因 | 降级 |
| `period_switch` | `code`、`period` | 切周期 |
| `action_click` | `code`、`action` | 详情四动作 |

### 附录 C 实现红线（评审逐条核对）

1. V2 单轨：不出现 V1 装饰器；`@Param` 不赋值；`@Local` 不外传初始化。
2. 行情对象只改 `@Trace` 字段，不整体替换；行情不进 `AppStorageV2`。
3. `DetailContent` 内无路由、无 banner、无重连定时器。
4. 交易两层只渲染一层；`clientOrderId` 一次生成、全程复用、成功作废。
5. 全局只有一个 banner，只有 `ConnectionHub` 能驱动。
6. 颜色/尺寸/文案不写字面量；颜色走 token，文案走 i18n。
7. 滚动容器的 key 用业务 ID；禁止索引 key；禁止 `JSON.stringify` 默认 key。
8. 页面/组件内无自建定时器；所有节拍在 `commons/data/`。
9. 退出页面/关闭窗：`unsubscribe` + `dispose` + 定时器释放，三者齐全。
10. 停牌/新股：价格类 `--`、排序恒末尾、仍可点击；不使用 `0` 代替空值。
11. 交易禁用只覆盖「未开户/无权限/停牌/退市」；未登录放行、非交易时段可开单不可提交。
12. 占位文案只用「{对象}下阶段开放」，无变体、无标点、无版本号。
13. 分层：products → features → commons 单向（§3.1）；`new Mock*` 只出现在 `commons/data/DataServices.ets`；features 横向依赖仅限白名单；L2 不返回中文文案、VM 不碰 UI 副作用。

### 附录 D 与阶段二的衔接点

| 阶段二模块 | 本期预留 |
|---|---|
| M6 搜索 | `SearchService` 接口位（本期不实现）；换股先用自选选择器，二期替换 |
| M7 添加自选 | `WatchlistStore.add()` 与分组派生（`deriveGroups`）已按 CC-2.9 建好 |
| M8 卡片视图 | `SortStore` 共用；视图切换入口已占位 |
| M9 真实行情 | `QuoteProvider` 同契约换实现；`SubscriptionRegistry` 不动 |
| M10 真实交易 | `TradeGateway` 同契约换实现；幂等键已按真实委托设计 |
| M11 持仓 | `AccountInfo` 已含 `holdQty`；字段预留 `accountId` |
| M12 横屏/深色 | 颜色全 token（加 `dark/` 即可）；断点服务已集中 |
| M13 合规 | 埋点已脱敏；日志不落明文；权限最小化在 `module.json5` 控制 |

### 附录 E 变更记录

| 版本 | 变更 | 影响 |
|---|---|---|
| v1.0 | 首版：架构、数据层、M0–M5 方案、横切、性能、验收映射、计划、风险、10 项差异登记 | 可进入 V0；Q1/Q9 建议优先确认 |
| v1.1 | 工程形态补「分层架构设计」并展开为 §3.1：五层职责与出入口、允许依赖矩阵、数据流、状态归属、`AppServices` 组合根、分层校验（R-01~R-06）；交易校验改为「L2 返回错误码、L3 映射文案」 | 目录新增 `app/AppServices.ets`；评审、CI 红线、代码分层约束 |
| v1.2 | 按华为官方《分层架构设计》改为**三层模块化**：products（Entry HAP）/ features（4 个 HAR）/ commons（3 个 HAR）；新增依赖白名单、两个装配点（`DataServices` / `AppServices`）、模块级 CI 规则 R-01~R-09、§3.1.12 演进路径；目录与全部路径引用同步改写 | ADR-01 由「单 HAP」改为「三层模块」；M0 3→4.5 人日（从缓冲支出，总 60 不变） |

---

> **下一步（本文发出后 3 个工作日内）**：
> 1. 评审会确认 Q1（断点）、Q9（换股替代方案）、Q3（1.45× 口径）三项，其余默认通过。
> 2. 按 §2.4 执行 4 项开工前核验，产出 `docs/v0-spike-report.md`。
> 3. 冻结三 Provider 契约（§4.2），此后只增不改。


