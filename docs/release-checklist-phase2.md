# 阶段二发版清单（Release Checklist · Phase 2）

> 版本：v1.0 · 日期：2026-11-14 · 适用：小杨股票 **2a / 1.1.0**（Mock 数据 + 应用内多窗 + 搜索/添加自选/卡片/横屏深色）
> 验收状态：**2a 收口完成**（P2-A1/A2/A3；构建 + 6 步门禁 + 69 例单测 + 19 例 UiTest + 3 设备冒烟全绿）
> 用法：发版前逐项打勾；未过项必须在「已知限制」登记，不允许静默放行。
> 关联：[阶段二进度文档](阶段二进度文档.md)、[P2-A1 集成记录](../validation/phase2-integration-acceptance.md)、[P2-A2 验收记录](../validation/phase2-acceptance.md)、[1.1.0 发布说明](../dist/phase2-1.1.0/RELEASE-NOTES.md)

## 1. 版本与工程信息

| 项 | 值 | 状态 |
|---|---|---|
| bundleName | `com.example.xiaoyangstock` | ✅ |
| versionName / versionCode | **`1.1.0` / `1001000`**（`AppScope/app.json5`） | ✅ 已核对（HAP `pack.info` 一致） |
| 模块版本一致性 | **9 个模块**（entry + 5 feature：watchlist/detail/trade/pk/search + 3 common：ui/basic/data）均为 `1.1.0` | ✅ `check-version` V-01~V-03 |
| SDK | compile/target/compatible = 20（HarmonyOS 6.x；构建机 SDK 26.0.0.105） | ✅ |
| deviceTypes | `phone` / `tablet` | ✅ |
| 权限 | 未申请任何 `requestPermissions` | ✅ |
| 签名产物（release） | `entry-default-signed.hap` **1,981,981 bytes ≈ 1.9 MB** | ✅ |
| 签名证书 | DevEco 自动生成的**调试证书**（`debugKey`）；2a 仅内部侧载，不提交 AGC | ⚠️ 上架前替换发布证书（M13） |
| 产物路径 | `dist/phase2-1.1.0/entry-default-signed.hap` | ✅ |

## 2. 构建与门禁

| 项 | 命令 | 门禁 | 状态 |
|---|---|---|---|
| Debug 构建 | `devecocli build` | BUILD SUCCESSFUL | ✅ |
| Release 构建 | `devecocli build --build-mode release` | BUILD SUCCESSFUL（signed HAP 1.9MB） | ✅ |
| 版本一致性 | `node scripts/check-version.mjs` | V-01~V-03 | ✅ |
| 占位文案 | `node scripts/check-coming-soon.mjs` | 2 条（home/news） | ✅ |
| 分层红线 | `node scripts/check-architecture.mjs` | R-01~R-09（150 文件） | ✅ |
| 深色 token | `node scripts/check-dark-tokens.mjs` | base/dark 30 键一致；.ets 166 文件 0 字面量 | ✅ |
| 对比度 | `node scripts/check-contrast.mjs` | dark 文本 23/23、非文本 5/5；红绿 ΔE 116.5 | ✅ |
| 一键门禁 | `powershell -File scripts/gate.ps1` | **6 步 GATE PASS** | ✅ |
| CodeLinter | `devecocli check lint` | 0 error / 4 warning（阶段一既有） | ✅ |
| Local Test | `hvigor test -p module=search` / `module=watchlist` | **69/69**（search 48 + watchlist 21） | ✅ |
| UiTest | `hvigor onDeviceTest -p module=entry` | **19/19**（M6 8 + M7 6 + M8 4 + M12 1，真机 Mate 60 Pro） | ✅ |

## 3. 功能冒烟（发版前必跑）

| # | 步骤 | 预期 | 状态 / 证据 |
|---|---|---|---|
| 1 | 冷启动 → 四 Tab | 默认自选；首页/资讯占位 2 条 | ✅ `shots/phase2/acceptance/p4-01-release-phone.png` |
| 2 | 自选 11 列横滑 | 名称/表头冻结，滑到市净率；无横向溢出 | ✅ `p1-14-hscroll.png` |
| 3 | 搜索 → 加自选 | 搜 `600900` → 行尾＋ →「已添加」→ 自选页出现新行（46 只） | ✅ `p1-03/04/05/06` |
| 4 | 列表 ↔ 卡片 | 视图切换、卡片 2 列、排序 chip、位置保留 | ✅ `p1-07`；UiTest AC100~103 |
| 5 | 详情 | 报价头 / 指标 / 8 周期 / 盘口 / 动作栏；深链冷启可直达 | ✅ `p1-08`、`p1-17`；`p4-02` |
| 6 | 交易 | 价格/数量、买入→确认→提交，弹窗归属详情 | ✅ `p1-09/10/11`；`p4-03` |
| 7 | 多窗比价 | 2/3 窗、换股、同步周期 | ✅ `p1-19-pk-2win`、`p1-20-pk-3win` |
| 8 | 断线/恢复 | 唯一 banner、数据冻结置灰；恢复后 banner 消失 | ✅ `p1-21`、`p1-22` |
| 9 | 深色 | 自选/详情/卡片/搜索/添加/交易/平板全深色；热切无白闪 | ✅ `p1-12/13`、`p3-02`；M12 证据 25 张 |
| 10 | 字号 1.45× | 列表列宽同比、详情降列、不截断 | ✅ `p1-23` |
| 11 | 横屏详情 | 左 62%（报价/周期/图表/指标）+ 右 38%（盘口/明细）+ 动作栏固定 | ✅ `p4-05`、`p2-03` |
| 12 | 404 / 非法深链 | 落「页面不存在」并可返回自选 | ✅ `p1-18` |
| 13 | 折叠↔展开 | 460vp↔940vp 布局切换、状态保持、无崩溃 | ✅ `p2-04`、`p2-05`；M12 `21/22/23` |

## 4. 设备矩阵

| 形态 | 设备 | 结论 | 证据 |
|---|---|---|---|
| 直板 388vp | HUAWEI Mate 60 Pro 真机（ALN-AL80，HarmonyOS 7.0 / API 26） | ✅ 主链路、深链、交易、PK 3 窗、深色、1.45×、断网 | `shots/phase2/acceptance/p1-*`、`p4-01~03` |
| 折叠 460vp | Pura X Max 模拟器（fold close） | ✅ 竖屏详情、列表、折叠→展开 | `p2-04`、`p2-05` |
| 阔折叠 940vp | Pura X Max 模拟器（fold open） | ✅ 横屏详情 62/38、卡片、深色 | `p2-01~03`、`p4-04/05` |
| 平板 1280vp | M1 Tablet 模拟器（2880×1920） | ✅ 左栏 523 + 右栏全量、右栏去交易、深色 | `p3-01`、`p3-02`、`p4-06` |

> 折叠**真机**仍缺；折叠/阔折叠以 widefold 模拟器覆盖（与阶段一同口径）。

## 5. 已知限制（发版必须对外说明）

1. **数据全 Mock**：无真实行情/交易网关；接真实源只替换 `DataServices` 装配点。
2. **交易为演示流程**：Mock 网关；不含开户/KYC/真实风控。
3. **`WindowHost` 系统多实例**：本期仅应用内窗格（DEC-08-01），二期接入。
4. **深色冷启未真机取证**：系统深色冷启（启动窗口/首帧）未验证；热切与深色页面已验。
5. **4 形态 × 深色 × 字号矩阵未全量**：已覆盖直板/折叠/阔折叠/平板的主界面，深色 × 1.3/1.45× 为抽样。
6. **读屏语音未听测**：卡级/行级 `accessibilityText` 为代码级验证（T-08）。
7. **图表 pinch 缩放保留未实测**：`captureViewport/restoreViewport` 已实现，需真机手势复验。
8. **签名**：当前 debug 证书仅内部侧载；AGC 上架前必须替换发布证书 + Profile（M13）。
9. **首页/资讯**：仍为占位（2 条「下阶段开放」），M13 上架材料说明。

## 6. 发版步骤

```powershell
cd D:\deepseek_harness_work\xiaoyang-stock
node scripts/bump-version.mjs 1.1.0          # 已完成
devecocli build                              # 1) debug
powershell -File scripts/gate.ps1            # 2) 6 步门禁
devecocli build --build-mode release         # 3) release（signed HAP）
# 4) 归档
#    dist/phase2-1.1.0/entry-default-signed.hap
# 5) 三设备安装冒烟
devecocli run --skip-build --device 23E0224222002707
devecocli run --skip-build --device 127.0.0.1:5557
devecocli run --skip-build --device 127.0.0.1:5555
```

## 7. 2b 待办（本清单后续扩展）

- 契约 v1.1 + 契约测试（G2-05）
- 真实行情/交易通道（D50/D51）
- 隐私同意与权限最小化（M13-1）
- 发布证书/Profile、AGC 内测/上架
- `docs/release-checklist-phase2.md` 追加 2b 章节
