# 阶段二发版清单（Release Checklist · Phase 2）

> 版本：**v2.0** · 日期：2026-11-14 · 适用：小杨股票 **2b / 1.2.0 / 1002000**（模拟行情 + 模拟交易 + 持仓 + 合规上架）
> 历史版本：v1.0（2a / 1.1.0）见 §10 附录。
> 用法：发版前逐项打勾；未过项必须在「已知限制」登记，不允许静默放行。
> 关联：[阶段二进度文档](阶段二进度文档.md)、[phase2-m13 用例](../validation/phase2-m13-test-cases.md)、
> [phase2-m13 性能/稳定性](perf/phase2-m13.md)、[SDK 与权限清单](phase2-sdk-list.md)、[隐私政策](privacy-policy.md)、
> [AGC 上架材料](release-metadata-phase2.md)、[1.2.0 发布说明](../dist/phase2-1.2.0/RELEASE-NOTES.md)

## 1. 版本与工程信息

| 项 | 值 | 状态 |
|---|---|---|
| bundleName | `com.example.xiaoyangstock` | ✅ |
| versionName / versionCode | **`1.2.0` / `1002000`**（`AppScope/app.json5`） | ✅ 已核对（`check-version` V-01~V-03） |
| 模块版本一致性 | **10 个模块**（entry + 6 feature：watchlist/detail/trade/pk/search/account + 3 common）均 `1.2.0` | ✅ |
| SDK | compile/target/compatible = 20（HarmonyOS 6.x；构建机 SDK 26.0.0.105） | ✅ |
| deviceTypes | `phone` / `tablet` | ✅ |
| **权限** | **0 项**（无 `requestPermissions`；`check-compliance` X-02） | ✅ |
| **第三方 SDK** | **1 个**：`@ohos/mpchart@3.0.31`（Apache-2.0，本地渲染）；清单 [phase2-sdk-list.md](phase2-sdk-list.md) | ✅ X-01 |
| 签名产物（release） | `entry-default-signed.hap` **2,227,951 bytes ≈ 2.13 MB**（SHA256 `57A02AB9…7021A5`） | ✅（clean 构建，无 `symbolMap.map`） |
| 签名证书 | DevEco 自动生成的**调试证书**（`debugKey`）；**上架前必须替换发布证书 + Profile** | ⚠️ 外部待办 |
| 产物路径 | `dist/phase2-1.2.0/entry-default-signed.hap` | ✅ |

## 2. 构建与门禁

| 项 | 命令 | 门禁 | 状态 |
|---|---|---|---|
| Debug 构建 | `devecocli build` | BUILD SUCCESSFUL | ✅ |
| **Release 构建（发版口径）** | `devecocli build clean` → `devecocli build --build-mode release` | BUILD SUCCESSFUL，signed HAP 2.13MB | ✅ |
| 版本一致性 | `node scripts/check-version.mjs` | V-01~V-03 | ✅ |
| 占位文案 | `node scripts/check-coming-soon.mjs` | 2 条（home/news） | ✅ |
| 分层红线 | `node scripts/check-architecture.mjs` | R-01~R-09 | ✅ |
| 契约完整性 | `node scripts/check-contracts.mjs` | K-01~K-04（7 个 Provider） | ✅ |
| 深色 token | `node scripts/check-dark-tokens.mjs` | base/dark 30 键一致；0 字面量 | ✅ |
| 对比度 | `node scripts/check-contrast.mjs` | dark 文本 23/23、非文本 5/5 | ✅ |
| **合规（M13）** | `node scripts/check-compliance.mjs` | X-01~X-04 | ✅ |
| 一键门禁 | `powershell -File scripts/gate.ps1` | **8 步 GATE PASS** | ✅ |
| CodeLinter | `devecocli check lint` | 0 error / 6 warning（阶段一既有 4 + 路由壳 2） | ✅ |
| Local Test | `hvigor test -p module=search` / `watchlist` / `commons_data` | **50 / 21 / 166**（合计 237） | ✅ |
| UiTest | `hvigor onDeviceTest -p module=entry` | **21/21**（首启同意基线见 `TestDriver.seedCompliance`） | ✅ |

## 3. 合规（AC-125 / M13-1）

| # | 项 | 预期 | 状态 / 证据 |
|---|---|---|---|
| 1 | 首启同意页 | 全屏、未同意不渲染 TabShell；同意→进入自选；拒绝→二次确认→退出 | ✅ `m13/01`、`m13/03`、`m13/04` |
| 2 | 隐私政策可查 | 首启页内可看全文；同意后首页「隐私政策」常驻入口 | ✅ `m13/02`、`m13/05`、`m13/06` |
| 3 | 可撤回同意 | 首页/隐私页均可撤回；撤回后回到同意页、**不删本机数据** | ✅ `m13/07`、`m13/08` |
| 4 | 同意落盘 | `privacy_consent_v1` 写入/撤回删除（磁盘核对） | ✅ `m13-test-cases.md` §4 |
| 5 | 权限最小化 | 0 权限；白名单仅 INTERNET/GET_NETWORK_INFO 且未使用 | ✅ X-02 |
| 6 | SDK 清单 | 与实际依赖双向一致；无广告/统计/推送 SDK | ✅ X-01 |
| 7 | 首笔风险揭示 | 首次提交前弹「模拟交易风险揭示」，确认后写 `trade_risk_v1` | ✅ `m13/09`、`m13/10`、`m13/11` |
| 8 | 法务复核 | 隐私政策 + 免责声明逐条签字 | ⬜ 外部 |

## 4. 性能与稳定性（AC-126 / AC-127）

| # | 项 | 阈值 | 实测 | 状态 |
|---|---|---|---|---|
| 1 | release HAP | ≤10MB | **2.13MB** | ✅ |
| 2 | 冷启 P90（应用内口径） | ≤2s | **241ms**（中位 225ms） | ✅ |
| 3 | 内存峰值（3 窗+深色） | ≤350MB | **154.2MB**（debug 上界）/ release 3 窗 123.3MB | ✅ |
| 4 | 崩溃/ANR 采集 | 有链路且可验证 | `hiAppEvent` + `errorManager`；注入 1 次 → `crash=1 jserr=1` | ✅ |
| 5 | 弱网/切网 30 次 | 无崩溃 | 60 条 `net_state` 迁移，进程存活 | ✅ |
| 6 | 前台 soak 10 分钟（3 窗+深色） | 无崩溃/无持续增长 | 见 `perf/phase2-m13.md` §4.4 | ✅ |
| 7 | 前台 1h 耗电 | ≤3% | **未测**（设备充电） | ⬜ 缺口 |
| 8 | 线上崩溃率/ANR | ≤0.1% / ≤0.05% | 本机口径 only | ⬜ 缺口（需 AGC） |

## 5. 功能冒烟（发版前必跑，1.2.0 口径）

| # | 步骤 | 预期 | 状态 |
|---|---|---|---|
| 1 | 首启 → 同意 → 四 Tab | 同意后默认自选；首页/资讯占位 2 条 + 首页底部隐私入口 | ✅ `m13/04`、`m13/05` |
| 2 | 自选 11 列横滑 / 卡片视图 | 名称与表头冻结；卡片 2/3/4/5 列、排序 chip 可用 | ✅ M8 证据沿用 |
| 3 | 搜索 → 加自选 | 搜 `600519` → 行尾＋ →「已添加」→ 自选页出现新行 | ✅ M6/M7 证据沿用 |
| 4 | 详情 + 图表 + 盘口 | 8 周期、横屏 62/38、读数条不遮挡 | ✅ M12 证据沿用 |
| 5 | 交易（首次） | 买入 → 确认 → **风险揭示** → 成交回执 → 查看委托 | ✅ `m13/09`、`m13/10` |
| 6 | 委托列表 | 7 状态筛选、分页、撤单二次确认 | ✅ M10 证据沿用 |
| 7 | 持仓与收益 | 汇总卡 + 三行五项 + 排序 + 加自选 | ✅ M11 证据沿用 |
| 8 | 断线/恢复 | 唯一 banner、数据冻结置灰；恢复后消失 | ✅ M5/M9 证据沿用 |
| 9 | 深色 | 全站深色；3 窗 PK 深色可读 | ✅ `m13/16` |
| 10 | 字号 1.45× | 列宽同比、详情降列、不截断 | ✅ M8/M12 证据沿用 |
| 11 | 404 / 非法深链 | 落「页面不存在」并可返回自选 | ✅ M6 证据沿用 |
| 12 | 隐私撤回 | 首页撤回 → 回到同意页 → 重新同意 → 数据仍在 | ✅ `m13/07`、`m13/08` |

## 6. 设备矩阵

| 形态 | 设备 | 结论 | 证据 |
|---|---|---|---|
| 直板 388vp | Mate 60 Pro 真机（ALN-AL80，HarmonyOS 7.0 / API 26） | ✅ 主链路 + M13 合规 + 稳定性 + 性能 | `shots/phase2/m13`、`perf/phase2-m13.md` |
| 折叠/阔折叠 | Pura X Max 模拟器（fold close/open） | ✅（2a 证据沿用） | `shots/phase2/m12`、`shots/phase2/acceptance` |
| 平板 1280vp | M1 Tablet 模拟器 | ✅（2a 证据沿用） | `shots/phase2/m8/17`、`m7/28` |
| 折叠**真机** | — | ⬜ 仍缺（T-07，外部设备依赖） | — |

## 7. 回滚演练（M13-5）

| # | 步骤 | 预期 | 状态 |
|---|---|---|---|
| 1 | 安装 1.2.0 → 产生数据（自选/委托/持仓/同意） | 数据落盘 | ✅ |
| 2 | 回装上一版 1.1.0 HAP（`dist/phase2-1.1.0/entry-default-signed.hap`） | 安装成功、可启动；新增键（`privacy_consent_v1`/`trade_risk_v1`/`stability_v1`）被旧版忽略，旧功能正常 | ✅ 见 §7.1 |
| 3 | 再升回 1.2.0 | 数据与同意状态保持（不重复弹同意） | ✅ |
| 4 | 记录 | 回滚命令、耗时、结论 | ✅ §7.1 |

### 7.1 演练记录（2026-11-14）

```powershell
# 1) 升回/安装 1.2.0
hdc -t 23E0224222002707 install -r "<repo>\products\entry\build\default\outputs\default\entry-default-signed.hap"
# 2) 回装 1.1.0
hdc -t 23E0224222002707 install -r "<repo>\dist\phase2-1.1.0\entry-default-signed.hap"
# 3) 再升回 1.2.0
hdc -t 23E0224222002707 install -r "<repo>\products\entry\build\default\outputs\default\entry-default-signed.hap"
```

| 轮次 | 结论 |
|---|---|
| 1.2.0 → 1.1.0 | 安装与启动成功；1.1.0 无同意页（旧版无该逻辑），自选/委托数据保留，新增 preferences 键被忽略 |
| 1.1.0 → 1.2.0 | 安装成功；`privacy_consent_v1` 仍在 → **不重复弹同意页**；自选/持仓/委托数据完好 |

> 结论：**版本回退不丢数据、不阻断启动**；回退期间产生的数据（1.1.0 写的自选）升级后照常读取。

## 8. 已知限制（发版必须对外说明）

1. **数据全模拟**：无真实行情/交易网关；全局常驻「模拟数据 · 仅供学习参考」，交易页常显「模拟交易 · 不产生真实委托」。
2. **首页/资讯占位**（2 条「下阶段开放」）；M13 已允许从应用内查看隐私政策。
3. **签名仍为调试证书**：上架前必须替换发布证书 + Profile（外部待办）。
4. **隐私政策 URL / 客服邮箱待补**：应用内全文已可查，AGC 提审需外网 URL。
5. **法务未签字**：隐私政策与免责声明需法务复核。
6. **线上崩溃率/ANR 无 AGC 口径**：本机采集可用，线上口径待接 AGC（接入需更新隐私政策 §4 与 SDK 清单）。
7. **前台 1h 耗电未测**：设备充电条件所限，待补。
8. **折叠真机未回归**（T-07）；折叠/阔折叠以模拟器覆盖。
9. **深色冷启、读屏听测、图表 pinch 缩放**沿用 2a 缺口（未在 2b 补）。
10. **混淆未启用**：属性混淆会破坏 preferences/委托 JSON 字段名，HAP 体积仅为阈值 21%，登记偏差。

## 9. 发版步骤

```powershell
cd D:\deepseek_harness_work\xiaoyang-stock
node scripts/bump-version.mjs 1.2.0              # 已完成（10 模块 + app.json5）
devecocli build clean                             # 0) 必须 clean（否则 symbolMap 会进包 → 3.6MB）
devecocli build                                   # 1) debug（本地验证）
powershell -ExecutionPolicy Bypass -File scripts\gate.ps1   # 2) 8 步门禁
devecocli build --build-mode release              # 3) release（signed HAP 2.13MB）
# 4) 归档（哈希 + 说明）
#    dist/phase2-1.2.0/entry-default-signed.hap + RELEASE-NOTES.md
# 5) 真机冒烟（15 分钟）
hdc -t 23E0224222002707 install -r dist\phase2-1.2.0\entry-default-signed.hap
# 6) 回滚演练（§7）+ 首启同意/撤回复验（§3）
```

## 10. 附录：2a（1.1.0）发布记录（历史）

| 项 | 值 |
|---|---|
| 版本 | `1.1.0` / `1001000` |
| 产物 | `dist/phase2-1.1.0/entry-default-signed.hap`（1,981,981 bytes ≈ 1.9MB） |
| 范围 | M6 搜索 / M7 添加自选与分组 / M8 卡片视图 / M12 横屏与深色 |
| 门禁 | 6 步（当时无契约/合规脚本）→ 后扩到 7 步 |
| 自动化 | Local 69/69、UiTest 19/19 |
| 设备 | 直板真机 + 折叠/阔折叠模拟器 + 平板模拟器 |
| 已知限制 | 深色冷启未取证、4 形态×字号矩阵抽样、读屏未听测、pinch 缩放未测、调试证书 |
