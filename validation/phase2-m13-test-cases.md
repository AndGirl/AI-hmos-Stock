# M13 合规与上架 · 验收用例（AC-125~127）

> 版本：v1.0 · 日期：2026-11-14 · 适用：小杨股票 **2b / 1.2.0 / 1002000**
> 执行环境：HUAWEI Mate 60 Pro（`23E0224222002707`，HarmonyOS 7.0 / API 26）
> 证据目录：[shots/phase2/m13](../shots/phase2/m13)；性能/包体数据：[docs/perf/phase2-m13.md](../docs/perf/phase2-m13.md)
> 门禁：[scripts/check-compliance.mjs](../scripts/check-compliance.mjs)（X-01~X-04，`gate.ps1` 第 7 步）

## 0. 逐条结果总览

| AC | 断言 | 结果 | 备注 |
|---|---|---|---|
| AC-125 | 隐私政策可查、首启同意（拒绝可退出）、权限最小化（仅网络类）、SDK 清单完整、可撤回同意 | ✅ 5/5（法务复核外部） | 权限为 **0**（比"仅网络类"更小） |
| AC-126 | release HAP ≤10MB、冷启 P90 ≤2s、内存峰值 ≤350MB（3 窗+深色） | ✅ 3/3 | 2.13MB / 241ms / 154.2MB |
| AC-127 | 崩溃率 ≤0.1% 会话、ANR ≤0.05%、前台 1h 耗电 ≤3%、弱网/切网 30 次无崩溃 | 🟡 2/4 + 1 替代 | 崩溃/ANR 采集与 30 次切网通过；**耗电因设备充电无法测**（缺口 §3-1）；线上崩溃率需 AGC |

## 1. AC-125 隐私同意与权限最小化

| # | 步骤 | 预期 | 证据 |
|---|---|---|---|
| 125-1 | 全新安装后首次启动 | 全屏同意页：标题「欢迎使用小杨股票」+ 说明 +「查看《隐私政策》」+「同意并继续」+「不同意」；**不渲染 TabShell** | `m13/01-consent-first-launch.png` |
| 125-2 | 点「不同意」 | 二次确认「确认不同意」（再想想 / 退出应用）；选「再想想」页面不变 | `m13/03-consent-reject-confirm.png` |
| 125-3 | 二次确认选「退出应用」 | `terminateSelf()` 退出应用（AC-125「拒绝可退出」）：日志 `consent_page_reject_exit`，**进程消失**（`pidof` 为空） | 真机实测（`hilog -T Consent`） |
| 125-4 | 点「查看《隐私政策》」 | 页内切到政策全文（8 节 + 版本 1.0 + 更新日期 + 在线地址占位），可返回 | `m13/02-consent-policy-inline.png` |
| 125-5 | 点「同意并继续」 | 立即写 `privacy_consent_v1` 并进入自选（默认 Tab）；杀进程重启不再弹 | `m13/04-consent-agreed-watchlist.png`；磁盘见 125-9 |
| 125-6 | 首页 Tab 底部 | 常驻「隐私政策 / 撤回同意」与「版本 1.2.0 · 模拟数据，仅供学习参考」 | `m13/05-home-privacy-entry.png` |
| 125-7 | 首页 →「隐私政策」 | 路由页全文 + 底部「当前状态：已同意（时间）」+「撤回同意」 | `m13/06-privacy-page-route.png` |
| 125-8 | 点「撤回同意」→ 确认 | 回到首启同意页；本机数据不删除 | `m13/07-revoke-confirm.png`、`m13/08-revoked-back-to-consent.png` |
| 125-9 | 磁盘核对 `xiaoyang_stock_v1` | 同意后 `privacy_consent_v1 = {"agreed":true,"version":"1.0","agreedAt":<ms>}`；撤回后**该键消失** | `hdc file recv` 实测（见 §4 日志摘录） |
| 125-10 | 策略版本升版（`PRIVACY_POLICY_VERSION` 变更） | 旧版本同意记录视为过期，重新弹同意页 | 单测 `version_mismatch_needs_reconsent` |
| 125-11 | 权限最小化 | `module.json5` **无 `requestPermissions`**（0 权限）；门禁 X-02 白名单校验 | `check-compliance` 输出「权限：声明 0 项」 |
| 125-12 | SDK 清单完整 | 清单仅 `@ohos/mpchart@3.0.31`（Apache-2.0，本地渲染）；与依赖双向一致 | [phase2-sdk-list.md](../docs/phase2-sdk-list.md) + X-01 PASS |
| 125-13 | 首笔风险揭示（M10-7 遗留收口） | 首次提交委托前弹「模拟交易风险揭示」；「我已了解并继续」后成交，写 `trade_risk_v1`；再次提交不再弹 | `m13/09-trade-risk-notice.png`、`m13/10-trade-after-risk-ack.png`、`m13/11-trade-second-submit-no-prompt.png` |
| 125-14 | 深色/横屏下同意页与隐私页 | 只用 30 个 token、无颜色字面量（D-01~D-03 绿）；**深色同意页可读**（调试切深色后撤回 → 回到深色同意页） | `check-dark-tokens` PASS；`m13/18-consent-dark-after-revoke.png` |

> **法务逐项签字**：外部待办（AC-125 要求法务签字，本轮只能做到「文案齐备 + 行为可验证」）。

## 2. AC-126 包体与性能

| # | 步骤 | 预期 | 证据 |
|---|---|---|---|
| 126-1 | `devecocli build clean` + `build --build-mode release` | signed HAP **2,227,953 bytes ≈ 2.13MB** ≤10MB | `docs/perf/phase2-m13.md` §1 |
| 126-2 | 冷启 5 次（force-stop + `aa start`） | P90 **241ms**、中位 225ms、最大 244ms ≤2s | 同上 §2（`StartupPerf` 日志） |
| 126-3 | 3 窗 PK + 深色，`hidumper --mem` | Total PSS **154.2MB**（debug 上界）/ release 3 窗 123.3MB ≤350MB | 同上 §3；`m13/16-dark-pk3-memory.png` |
| 126-4 | release 包调试入口 | 长按「自选股」标题无调试面板；`check-compliance` X-03 静态拦截 | `m13/15-release-no-debug-menu.png` |
| 126-5 | 混淆 | **未启用**（见偏差登记）：属性混淆会破坏 preferences JSON 字段名 | `docs/perf/phase2-m13.md` §7-1 |

## 3. AC-127 稳定性与监控

| # | 步骤 | 预期 | 证据 |
|---|---|---|---|
| 127-1 | 启动 4 次后查看计数 | `session=4 crash=0 freeze=0 jserr=0 rej=0 last=none` | `m13/12-stability-counters.png` |
| 127-2 | 调试注入一次未捕获异常 | 日志 `js_error` → `stability_event js_error` → `APP_CRASH`；重启后计数 `crash=1 jserr=1 last=APP_CRASH` | `m13/13-stability-after-crash.png` + `hilog -T Stability` |
| 127-3 | 调试「切网 30 次压测」 | `ConnLog net_state=` 60 条（30 断/30 恢复）、进程存活、无崩溃 | `m13/14-net-stress-30.png` + 日志计数 |
| 127-4 | 3 窗 + 深色前台 soak 10 分钟 | 无崩溃/无冻屏，内存不持续增长 | `docs/perf/phase2-m13.md` §4.4 |
| 127-5 | 前台 1h 耗电 ≤3% | ⬜ **无法测**：设备处于充电态（`chargingStatus=1`） | 缺口（换非充电条件补测） |
| 127-6 | 崩溃率 ≤0.1% 会话 / ANR ≤0.05% | 🟡 本机口径：注入 1 次后 `crash=1 / session=5`（验证链路）；正常会话为 0；**线上口径需 AGC** | 缺口（外部） |

## 4. 关键日志与磁盘证据摘录

```text
# 125-9 同意后（hdc file recv .../preferences/xiaoyang_stock_v1）
privacy_consent_v1 = {"agreed":true,"version":"1.0","agreedAt":1794637399059}
trade_risk_v1 = true
# 125-8 撤回后
privacy_consent_v1 = <absent>

# 127-2 崩溃采集链路
Stability: js_error len=3383
Stability: stability_event event=js_error
Stability: stability_event event=APP_CRASH
Stability: stability_ready session=5 crash=1 freeze=0 jserr=1 rej=0 last=APP_CRASH

# 126-2 冷启
StartupPerf: cold_start_ms=241 oncreate_ms=86 phase=tabs
StartupPerf: cold_start_ms=219 oncreate_ms=76 phase=tabs
StartupPerf: cold_start_ms=215 oncreate_ms=73 phase=tabs
StartupPerf: cold_start_ms=244 oncreate_ms=78 phase=tabs
StartupPerf: cold_start_ms=225 oncreate_ms=78 phase=tabs
```

## 5. 自动化覆盖

| 层 | 用例 | 结果 |
|---|---|---|
| Local Test（`commons/data`） | `PrivacyConsentStore` 6 例 + `RiskNoticeStore` 2 例 + `StabilityStore` 4 例 | **166/166**（M13 新增 12） |
| UiTest（`entry`） | 既有 21 例（首启同意基线由 `TestDriver.seedCompliance` + `dismissConsentIfShown` 保证） | **21/21** |
| 门禁 | `check-compliance` X-01~X-04（SDK 清单/权限白名单/调试守卫/隐私文案） | PASS（gate 8 步全绿） |

## 6. 缺口（登记，不阻塞内测）

| # | 项 | 原因 | 后续 |
|---|---|---|---|
| 1 | 前台 1h 耗电 | 设备充电中，无放电条件 | 换「满电 + 非充电」补测（同 §2 口径） |
| 2 | 线上崩溃率 / ANR 率 | 无 AGC 崩溃服务（零权限、零联网） | 上架后在 AGC 开启，并更新隐私政策 §4 与 SDK 清单 |
| 3 | 法务逐项签字 | 外部 | 法务复核隐私政策与免责声明 |
| 4 | release 证书/Profile、AGC 提审 | 需华为开发者账号 | 见 [release-metadata-phase2.md](../docs/release-metadata-phase2.md) §6 |
| 5 | 深色冷启下的同意页 | 系统深色冷启未取证（2a 遗留同项） | 与 2a 缺口一并补 |
