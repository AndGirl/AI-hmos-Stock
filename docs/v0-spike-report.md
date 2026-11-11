# V0 技术验证报告（Spike Report）

> 版本：v1.1 · 更新：2026-11-11 · 对应代码：`23523d1`（V0 验证提交）+ M1 前补测（V0-P1/P2 关闭）
> 依据：设计 §2.4（开工前 4 项核验）、§9.1（V0 DoD）、基线 §12.1
> 结论口径：**本报告如实区分「已验证」与「未验证」**。V0 的功能原型通过；V0-P1（50 行帧率）与 V0-P2（375vp 真机）已于 2026-11-11 补测关闭（§4.3），图表完整能力（V0-P3）留 M2 开工前。

---

## 1. 结论摘要

| # | 验证项 | 结论 | 证据 | 缺口 |
|---|---|---|---|---|
| V0.1 | 工程创建 / 签名 / 装机启动 | ✅ 通过 | `shots/v0-01-hello.png` | — |
| V0.2 | 11 列冻结横滑 | ✅ 通过 | `shots/v0-02-*.png`、`shots/v0-p1-*`、`shots/v0-p2-*` | 无（50 行帧率与 388vp 真机已补测，见 §4.3） |
| V0.3 | `@ohos/mpchart` 在 API 20 可用 | 🟡 编译 + 基础渲染通过 | `shots/v0-03-chart.png` | 8 周期、十字光标、缩放、3 实例未验 |
| V0.4 | 状态管理 V2 + Navigation | ✅ 基础链路通过 | `shots/v0-04-*.png` | 多实例 / `AppStorageV2` 未验（非 V0 必需） |
| V0.5 | 折叠/展开与断点 | 🟡 手工宽度切换通过 | `v0-02-table`（展开）/`v0-02-closed`（折叠） | 自动断点服务在 M0 才实现 |

**对计划的影响**：V2 + Navigation 选型确认；11 列冻结结构确认可落地，**R2（冻结横滑性能）已由 V0-P1/P2 补测关闭**（§4.3）；图表库可继续用，但 M2 前必须补完整能力 spike。总人日不变，补测从缓冲支出。

---

## 2. 环境与设备

### 2.1 工具链

| 项 | 值 |
|---|---|
| 构建 | DevEco Studio + hvigor（命令行由 `devecocli` 封装） |
| SDK | `compileSdkVersion` / `targetSdkVersion` = **6.0.0(20)**；`compatibleSdkVersion` = 20 |
| 语言/框架 | ArkTS 严格模式、ArkUI 声明式、状态管理 V2 |
| 包管理 | ohpm（`@ohos/mpchart@3.0.31`） |
| 签名 | DevEco 默认调试证书（`default_xiaoyang-stock_*.p12/.cer/.p7b`） |

### 2.2 设备

| 设备 | 型号 | 系统 / API | 屏幕 | 刷新率 | V0 用途 |
|---|---|---|---|---|---|
| 折叠模拟器 | Pura X Max（widefold） | HarmonyOS 7.0.0.107(SP8DEVC00E999R4P11) / API 26 | 展开 2584×1828 px，折叠 1264×1848 px；密度 2.75 | 60Hz | **主验证设备** |
| 实体机 | HUAWEI Mate 60 Pro（ALN-AL80） | HarmonyOS 7.0.0.111(SP10C00E111R5P3) / API 26 | 1260×2720 px | 面板 120Hz，当前 60Hz | 未参与 V0；留作 M1 的 375vp/真机补测 |

> 换算（模拟器，密度 2.75）：展开约 **940×665vp**，折叠约 **460×672vp**。
> 说明 1：V0 提交信息里的「632/1292vp」与当前模拟器实测宽度不一致，本报告以截图与设备参数为准。
> 说明 2：设备运行 API 26（HarmonyOS 7.0），高于基线 20；兼容性满足「API ≥20」，但严格对齐「HarmonyOS 6.x」还需一台 6.x 设备回归（见 §6-V0-P5）。

复现命令：

```powershell
hdc shell param get const.product.model
hdc shell param get const.product.software.version
hdc shell param get const.ohos.apiversion
hdc shell hidumper -s RenderService -a screen   # 分辨率/刷新率
```

---

## 3. V0.1 工程、签名与装机

- Stage 模型单 EntryAbility；`loadContent('pages/Index')` 首屏正常。
- 调试证书签名、`hdc install` 安装、桌面图标启动均通过。
- 证据：`shots/v0-01-hello.png`。
- 结论：工程骨架可用，进入 V0.2。

---

## 4. V0.2 11 列冻结横滑

### 4.1 原型结构（`entry/src/main/ets/prototype/WatchTable.ets`，V0 提交内）

```
Row
├─ 名称列（112vp，固定）            ← Stack + Column，按 scrollY 做 offset
└─ 横向 Scroll（722vp，10 列）
   ├─ 表头 Row（宽 722）
   └─ 纵向 List（16 行 Mock）
```

- 表头与数据行放在同一个横向 `Scroll` 内，天然对齐；
- 名称列不参与横向滚动，仅按纵向 `List` 的 `yOffset` 做 `offset({ y: -scrollY })`；
- 列宽合计 834vp（112 + 722），行高 56、表头 40，与附录 A 一致。

### 4.2 实测

| 场景 | 结果 | 证据 |
|---|---|---|
| 展开（约 940vp） | 11 列完整可见，无横滑 | `shots/v0-02-table.png` |
| 折叠（约 460vp） | 名称列冻结，右侧 10 列可横滑；滑到最右可见「市净率」 | `shots/v0-02-closed.png` |
| 纵滑 + 横滑组合 | 名称列与数据行保持对齐 | `shots/v0-02-hscroll-left.png`、`v0-02-scrollv.png` |

### 4.3 补测结果（V0-P1 / V0-P2 关闭）

**探针**：临时页 `products/entry/src/main/ets/pages/TablePerfProbe.ets`（补测期间替换 `loadContent`，测毕删除，源码见本次提交历史）。结构严格按 §5.2.3 方案 C：横向 `Scroll` 内「表头 + 竖向 `List`（50 行、`cachedCount(6)`）+ 名称列 `translate`」；行高 56 / 表头 40 / 名称列 112 / 数字列 722（合计 834vp），Mock 每 13 行一条停牌 `--`。

**采样**：`UIContext.postFrameCallback` 逐帧串联，按 1s 窗口统计 fps、p95 帧间隔、卡顿帧（>25ms）、纵/横滚动事件数。负载为页内 `Scroller.scrollTo` 线性动画（1400ms/程、纵/横交替、1.6s 一次），与手指拖拽共用同一渲染路径（`List` 复用 + 每帧 1 次名称列 `translate` 更新），**未覆盖惯性/回弹抖动**。

| 场景 | 视口 | 设备 / 屏 | 活跃窗口 | 加权 FPS | 最低窗口 | p95 帧间隔 | 卡顿帧占比 |
|---|---|---|---|---|---|---|---|
| 展开纵滑 | 940×665vp | Pura X Max 模拟器 60Hz | 18 | 62.0 | 58.5 | 16.0ms（1 窗 32ms） | 0.53%（6/1125） |
| 折叠纵滑 + 横滑 | 460×672vp | 同上 | 141 | 62.0 | 54.6 | 16.0ms（偶发 32ms） | 0.47%（41/8803） |
| 真机纵滑 + 横滑 | 388×837vp | Mate 60 Pro（1260×2720，API 26，60Hz） | 58 | 59.9 | 59.4 | 16.5ms | 0.91%（32/3506） |

> 判定口径：帧间隔 ≤18ms 且最低窗口 ≥55fps。三组均通过；模拟器帧间隔 16.0ms（≈62.5fps）为模拟器 vsync 节奏，真机 16.5ms（≈60.4fps）。
> 统计剔除启动前 2 个窗口（首帧布局，最低 20.8fps），原始逐窗日志保留在 `docs/perf/`。

**V0-P2 结论**：Mate 60 Pro 实际视口 **388vp**（1260px ÷ 3.25 密度），落在计划区间 360–400vp；11 列可横滑到最后一列「市净率」，名称列与表头冻结、行对齐（`shots/v0-p2-mate60-lastcol.png`）。

**结论**：50 行 1.0× 连续滚动 ≥55fps 成立，名称列与数据列无错位；**R2 关闭**。

**遗留（不在 V0-P1/P2 判据内）**：手指甩动 + 回弹期间名称列跟随误差（§5.2.12 第 4 项，±0.5vp）需在 M1 真实组件上用真机手势复验；1.45× 字号横滑（§5.2.12 第 2 项）随 M1 字号能力一起验。

---

## 5. V0.3 图表库（`@ohos/mpchart`）

### 5.1 验证内容（`entry/src/main/ets/pages/ChartProbe.ets`，V0 提交内）

- 依赖：`@ohos/mpchart@3.0.31`，API 20 下编译通过；
- 分时 `LineChart`：241 点；
- 日 K `CandleStickChart`：120 根；
- 数据构建耗时：页面显示 **7ms**（仅数据构建，不是首帧）。

### 5.2 实测

- 两类图表均能渲染，页面无崩溃；截图 `shots/v0-03-chart.png`。
- 默认样式不适合产品：分时圆点过大、默认 label/图例未裁剪；需要 `ChartEngine` 适配层统一配置。
- 图表在折叠态（460vp）可渲染。

### 5.3 未验证 / 风险

- 未验证 8 个周期（分时/五日/日K/周K/月K/季K/半年K/年K）；
- 未验证长按十字光标、双指缩放、左右拖动、上滑加载；
- 未验证 3 个图表实例同屏（M4 多窗）；
- 未测首帧 ≤800ms、切周期 ≤300ms、内存/句柄释放；
- 未验证 V2 状态与图表多实例的兼容性。

**结论**：选型保留，但只是「能编译、能渲染」。**M2 开工前必须补一轮 8 周期 + 十字光标 + 缩放 + 3 实例 spike**；不通过则按设计 §2.3 退 Canvas 自绘（+3~5 人日）。

> M0 为精简包体曾临时移除 `@ohos/mpchart`；M2 做 `ChartEngine` 适配层时按 `3.0.31` 加回 `commons/data`。

---

## 6. V0.4 状态管理 V2 + Navigation

### 6.1 验证内容（`entry/src/main/ets/pages/V2Probe.ets`，V0 提交内）

- `@ComponentV2` + `@Local` 计数；
- `@Param` 下行、`@Event` 上行；
- `Navigation(NavPathStack)` + 单一 `@Builder pageMap` + `NavDestination` push/pop。

### 6.2 实测

- 点击 +1 立即刷新；子组件 `@Param` 收到新值，`@Event` 回写父组件；
- push 进入 `NavDestination: detail`，返回键 pop 回首页；
- 返回后 `@Local` 计数未被重置（截图序列 5 → 6）；
- 单 builder 分派、`hideTitleBar(true)` 行为正常。

证据：`shots/v0-04-v2.png`、`v0-04-navdest2.png`、`v0-04-index.png`。

### 6.3 未验证 / 边界

- `@Provider/@Consumer`、`@Monitor/@Computed` 未在 V0 覆盖（M0/M1 按需使用）；
- `AppStorageV2/PersistenceV2` 未验证（M0 的断点/安全区服务已补验）；
- 多实例（详情右栏 / 多窗）未验证（M2/M4）；
- V1 与 V2 混用未验证——按规范直接禁止。

**结论**：V2 + Navigation 基础链路可用，M0 的 AppRoot/TabShell/路由栈沿用该模型。

---

## 7. 折叠 / 断点

- V0 仅验证「同一张表在展开/折叠宽度下结构不坏」，未实现自动断点服务；
- 正式 `BreakpointService` 已在 M0 外壳步骤落地：600/840/1180、`windowSizeChange` 120ms 防抖、`AppStorageV2` 单例；已在 460vp（折叠）与 940vp（展开）实测；
- 折叠↔展开的列表滚动位置/选中态保持，M1 用 `WatchlistVM` 的 `@Trace` 字段验证。

---

## 8. 未完成项与关闭计划

| ID | 缺口 | 影响 | 关闭条件 | 状态 |
|---|---|---|---|---|
| V0-P1 | 50 行冻结表帧率未采样 | R2 未关闭，M1 性能无基线 | 50 行滚动 ≥55fps，留截图/日志 | ✅ 2026-11-11 关闭：940vp 62.0fps / 460vp 62.0fps / 388vp 59.9fps（§4.3，`docs/perf/`） |
| V0-P2 | 375vp 未验证 | 直板机横滑体验未知 | Mate 60 Pro（约 360~400vp）跑 11 列横滑 + 名称冻结 | ✅ 2026-11-11 关闭：Mate 60 Pro 388vp，横滑到市净率、名称/表头冻结（§4.3） |
| V0-P3 | 图表 8 周期/十字光标/缩放/3 实例未验 | M2 图表方案可能返工 | API 20 设备：8 周期切换、长按、双指、3 实例 30min 无崩溃/内存增长 | ⬜ M2 开工前 |
| V0-P4 | 折叠↔展开状态保持未验 | AC 要求 | 折叠/展开后列表滚动、选中、分组、横滑偏移不丢 | ⬜ M1/M5 |
| V0-P5 | 6.x 基线设备未回归 | 设备矩阵缺口 | 一台 HarmonyOS 6.x（API 20~）设备安装并跑 M0 外壳 | ⬜ M1 前 |
| V0-P6 | 本报告缺失 | 交接断档 | 本文 | ✅ 已完成 |

> 上述补测从设计缓冲（8.5 人日）支出，不改变 60 人日总盘。

---

## 9. 证据索引

| 文件 | 说明 |
|---|---|
| `shots/v0-01-hello.png` | V0.1 工程启动成功 |
| `shots/v0-02-table.png` | 展开态 11 列完整显示 |
| `shots/v0-02-closed.png` | 折叠态横滑到最右，名称列冻结 |
| `shots/v0-02-hscroll-left.png` | 纵滑 + 横滑组合，行对齐 |
| `shots/v0-02-scrollv.png` | 纵向滚动 |
| `shots/v0-02-after-run.png` | 安装后运行态 |
| `shots/v0-03-chart.png` | mpchart 分时 241 点 + 日 K 120 根，数据构建 7ms |
| `shots/v0-04-v2.png` | V2 计数与 @Param/@Event |
| `shots/v0-04-navdest.png` / `v0-04-navdest2.png` | Navigation push / NavDestination |
| `shots/v0-04-index.png` | V0 入口页 |
| `shots/v0-p1-emu-unfolded-hud.png` | 补测：展开 940vp，50 行自动纵滑，HUD 实时帧率 |
| `shots/v0-p1-emu-folded.png` | 补测：折叠 460vp，纵滑 + 横滑同时生效 |
| `shots/v0-p2-mate60.png` | 补测：Mate 60 Pro 388vp，50 行渲染与名称列冻结 |
| `shots/v0-p2-mate60-lastcol.png` | 补测：Mate 60 Pro 横滑到「市净率」，名称/表头冻结 |
| `docs/perf/v0-p1-unfolded-940vp.log` | 逐 1s 窗口采样日志（展开态） |
| `docs/perf/v0-p1-folded-460vp.log` | 逐 1s 窗口采样日志（折叠态） |
| `docs/perf/v0-p2-mate60-388vp.log` | 逐 1s 窗口采样日志（真机） |

V0 源码已在 M0 删除，仍可从历史提交恢复：

```powershell
git show 23523d1:entry/src/main/ets/prototype/WatchTable.ets
git show 23523d1:entry/src/main/ets/pages/ChartProbe.ets
git show 23523d1:entry/src/main/ets/pages/V2Probe.ets
```

---

## 10. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| v1.0 | 2026-11-11 | 初版：补 V0 报告；记录工程/11 列/图表/V2+Navigation/折叠五组结果，如实登记帧率、375vp、图表完整能力等待补项 |
| v1.1 | 2026-11-11 | V0-P1/P2 补测关闭：新增 §4.3（50 行三场景帧率表、采样方法、388vp 真机横滑结论）；V0.2 结论转 ✅，R2 关闭；§8 更新 P1/P2 状态，§9 补 4 张截图 + 3 份逐窗日志 |
