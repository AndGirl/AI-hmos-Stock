# 阶段一发版清单（Release Checklist）

> 版本：v1.1 · 日期：2026-11-12 · 适用：小杨股票 阶段一（Mock 数据 + 应用内多窗）
> 用法：发版前逐项打勾；未过项必须在「已知限制」里有对应登记，不允许静默放行。

## 1. 版本与工程信息

| 项 | 值 | 状态 |
|---|---|---|
| bundleName | `com.example.xiaoyangstock` | ✅ |
| versionName / versionCode | `1.0.0` / `1000000`（`AppScope/app.json5`） | ✅ 已核对 |
| 模块版本一致性 | 8 个模块（entry + 4 feature + 3 common）`oh-package.json5` 均为 `1.0.0` | ✅ 由 `scripts/check-version.mjs` 守护（V-01~V-03，已做负向探针） |
| SDK | compile/target/compatible = **20**（HarmonyOS 6.x） | ✅ |
| deviceTypes | `phone` / `tablet` | ✅ |
| 权限 | **未申请任何 `requestPermissions`**（无网络/位置/存储/通讯录等敏感权限） | ✅ |
| 签名产物（debug 构建） | `entry-default-signed.hap` 约 **4.3 MB**（含调试信息） | ✅ |
| 签名产物（release 构建） | `devecocli build --build-mode release` 通过；signed HAP 约 **1.5 MB**（不含调试信息） | ✅ |
| 签名证书 | 当前为 DevEco 自动生成的**调试证书**（`default_xiaoyang-stock_*.cer/.p7b/.p12`，`keyAlias: debugKey`） | ⚠️ 上架 AGC 前必须替换为**发布证书 + Profile**（见 §6） |

## 2. 构建与门禁

| 项 | 命令 | 门禁 | 状态 |
|---|---|---|---|
| 全量构建 | `devecocli build` | BUILD SUCCESSFUL（89 tasks） | ✅ |
| 占位文案 | `node scripts/check-coming-soon.mjs` | 5 条常量、无硬编码 | ✅ |
| 分层红线 | `node scripts/check-architecture.mjs` | R-01~R-09 全通过 | ✅ |
| 代码检查 | `devecocli check lint` | 0 error / 5 warning（均为页面级组件性能提示，历史遗留） | ✅ |
| 版本一致性 | `node scripts/check-version.mjs` | V-01 versionName/versionCode 格式、V-02 code 与 name 映射、V-03 八模块版本一致 | ✅ |
| 一键门禁 | `powershell -File scripts/gate.ps1` | 版本 → 文案 → 红线 → lint 四步 GATE PASS | ✅ |
| CI | `.github/workflows/gate.yml` | push/PR 跑版本 + 文案 + 红线（无 SDK，不跑 lint/构建） | ✅ |

## 3. 功能冒烟（发版前必跑）

| # | 步骤 | 预期 | 状态 |
|---|---|---|---|
| 1 | 冷启动 → 四 Tab | 默认自选；首页/资讯/行情为占位文案 | ✅ |
| 2 | 自选列表横滑 | 11 列、表头与名称列冻结、滑到「市净率」 | ✅ 真机 388vp |
| 3 | 点行 → 详情 | 报价头/指标/8 周期/盘口/动作栏 | ✅ |
| 4 | 详情「去交易」 | 弹窗门禁（未登录→登录层）、价格数量、提交三态 | ✅ |
| 5 | 详情 ⧉ / 动作栏「股票PK」 | 2→3 窗、叠放、指示器、换股交换、同步周期 | ✅ 真机 3 窗 |
| 6 | 自选长按多选 | 2–3 只 →「比价」；1 只/4 只边界提示 | ✅ |
| 7 | 断线注入（调试面板 → 网络 → 断线） | 唯一 banner、数据冻结、55% 置灰、去交易禁用 | ✅ |
| 8 | 恢复网络 | banner 消失、去灰、自动补订阅/图表 | ✅ |
| 9 | 杀进程 → 重进 PK → 恢复上次对比 | 窗序/焦点/周期恢复 | ✅ |
| 10 | 系统字号 1.0 / 1.3 / 1.45× | 列表列宽同比、详情降列、交易与多窗不截断 | ✅ 模拟器（1.45 真机未跑） |

## 4. 设备矩阵与证据

| 场景 | 设备 | 结论 |
|---|---|---|
| 388vp 直板 | HUAWEI Mate 60 Pro（真机，1260×2720） | ✅ 列表/详情/交易/3 窗（`shots/m5-mate60-*`、`m5-release-smoke-*`） |
| 460 / 940vp 折叠 | Pura X Max（widefold 模拟器） | ✅ 2/3 窗、mini 版、折叠↔展开保持（`m4-*`） |
| 1280vp 平板 | M1 Tablet（模拟器） | ✅ 左栏 523 + 右栏 pane、交易 640vp 居中（`m3-tablet-trade.png`） |
| 折叠**真机** | — | ⛔ 无折叠真机接入，以 widefold 模拟器覆盖（见 §5） |
| 读屏 | Mate 60 Pro + 系统「屏幕朗读」 | ✅ 焦点顺序：换股 → 窗卡 → 图表；跨窗移动焦点；指示器语音未听测 |

## 5. 已知限制（发版必须对外说明）

1. **数据全 Mock**：无真实行情/交易网关；接真实源只替换 `DataServices` 内 provider 装配点（契约同形）。
2. **交易为演示流程**：Mock 网关、两账户、幂等键与超时注入；不含开户/KYC/真实风控。
3. **`WindowHost` 系统多实例**：本期仅应用内窗格（DEC-08-01），二期接入，验收口径不变。
4. **折叠真机未回归**：仅有折叠模拟器证据；真机折叠/展开与悬停态待设备回归。
5. **读屏语音未听测**：指示器「第 N 个，共 3 个」为代码级验证；`uitest` 双击无法触发读屏激活，自动化受限（进度文档 §10-77）。
6. **系统级 FPS 未取到**：模拟器镜像 `RenderService fps` 返回空，3 窗帧率以 `PerfMeter`（57.4fps@1.45×）+ `hitchs`（>16.67ms 帧数 0）双证据；真机建议 SmartPerf/Profiler 复测。
7. **深色模式/横屏重排/分享/搜索/自选管理**：按阶段一范围明确不做（占位或标灰）。
8. **埋点出口**：`AnalyticsHub` 队列 + hilog sink，未接三方 SDK；事件名与参数已按附录 B 就位。

## 6. 发版步骤

```powershell
cd D:\deepseek_harness_work\xiaoyang-stock
devecocli build                                  # 1) 全量构建（含 ohpm install/sync）
powershell -File scripts/gate.ps1                # 2) 版本 + 文案 + R-01~R-09 + lint
devecocli build --build-mode release             # 2b) 发版包（signed HAP ≈1.5MB）
devecocli run --skip-build --device "HUAWEI Mate 60 Pro"   # 3) 真机安装冒烟
# 4) 产物：products/entry/build/default/outputs/default/entry-default-signed.hap
# 5) 换发布证书：在 build-profile.json5 的 signingConfigs 填发布证书/Profile（当前 debugKey 仅内测）
#    或使用 hmos-connect-api-cli-skill 申请发布证书/Profile 后替换
# 6) 上传 AGC（二选一）：DevEco 发布向导 / connect-api-cli
```

## 7. 回滚与值守

- 回滚：AGC 保留上一版本（`versionCode` 递减不可行，需重新上传旧包并提升 code）；本地保留上一 tag 的 signed HAP。
- 值守：发版后 24h 观察崩溃/白屏/断线类反馈；Mock 阶段主要看布局与交互问题。
- 版本号变更规则：功能变更 +1 minor（1.1.0），仅修复 +1 patch（1.0.1），`versionCode` 同步递增（如 1000001）。
