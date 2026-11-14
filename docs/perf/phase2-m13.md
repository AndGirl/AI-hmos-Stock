# M13 包体 / 性能 / 稳定性实测（AC-126 / AC-127）

> 版本：v1.0 · 日期：2026-11-14 · 设备：HUAWEI Mate 60 Pro（`23E0224222002707`，HarmonyOS 7.0 / API 26）
> 构建：`devecocli build clean` + `devecocli build --build-mode release`（clean 后重建，避免 debug 中间产物混入）
> 版本：**1.2.0 / 1002000**
> 复现命令见 §6；口径与偏差见 §7。

## 1. 包体（AC-126：release HAP ≤10MB）

| 项 | 值 | 结论 |
|---|---|---|
| release signed HAP | **2,227,951 bytes ≈ 2.13 MB**（`dist/phase2-1.2.0/`，SHA256 `57A02AB9…7021A5`） | ✅ 远低于 10MB（阈值的 21%） |
| unsigned HAP | 2,172,430 bytes | — |
| 最大内部文件 | `ets/modules.abc` 2,005,188 bytes | 业务代码本体 |
| 资源 | `resources.index` 36,897 + 图片合计 ~0.15MB | — |
| 混淆 | **未启用**（`products/entry/build-profile.json5` 的 `obfuscation.enable=false`） | 见 §7-1 偏差登记 |

> 对照：2a/1.1.0 的 release HAP 为 1,981,981 bytes；1.2.0 增加 **约 0.25MB**（M13 同意页/隐私页/稳定性采集/文案）。
> 注意：**incremental release 构建**曾在 `ets/symbolMap.map`（1.4MB）被打进 HAP，产出 3.6MB；
> `build clean` 后恢复 2.23MB 且无 `symbolMap.map`。发版必须 **clean + release** 两次构建（已写入发版清单 §2）。

## 2. 冷启（AC-126：P90 ≤2s）

口径：**应用内冷启**＝进程创建（`process.getStartRealtime()`）→ 首帧 `Index.onAppear`，两端同一时钟
（`systemDateTime.getUptime(ACTIVE)`，见 `commons/basic/services/StartupMeter.ets`）。
每次 `aa force-stop` → `hilog -r` → `aa start`，5 次；日志标签 `StartupPerf`。

| # | cold_start_ms | oncreate_ms |
|---|---|---|
| 1 | 241 | 86 |
| 2 | 219 | 76 |
| 3 | 215 | 73 |
| 4 | 244 | 78 |
| 5 | 225 | 78 |

| 指标 | 值 | 结论 |
|---|---|---|
| 中位数 | **225 ms** | ✅ |
| P90（5 次取第 5 个最大值，口径保守） | **241 ms** | ✅ 远低于 2000ms |
| 最大 | 244 ms | ✅ |
| onCreate 阶段 | 73~86 ms | 进程起来到 Ability onCreate |

> `oncreate_ms` 是 cold_start 的子集：剩余 130~160ms 为 `loadContent` + 首帧渲染 + 首屏数据装配。

## 3. 内存（AC-126：峰值 ≤350MB，3 窗 + 深色）

采集：`hdc shell hidumper --mem <pid>` 的 `Total Pss`。

| 场景 | 构建 | Total PSS | 结论 |
|---|---|---|---|
| 3 窗 PK（浅色） | release 1.2.0 | **126,229 kB ≈ 123.3 MB** | ✅ |
| 3 窗 PK + **深色**（debug 调试面板切深色） | debug 1.2.0 | **157,939 kB ≈ 154.2 MB** | ✅ 余量 195MB |

> debug 构建未裁剪、含调试通道，**高于** release（同场景 release 约 123MB），因此 154.2MB 是保守上界。
> 证据：`shots/phase2/m13/16-dark-pk3-memory.png`。

## 4. 稳定性（AC-127）

### 4.1 本机采集口径（无三方 SDK）

| 项 | 实现 | 存储 |
|---|---|---|
| 崩溃 | `hiAppEvent` 监听 `APP_CRASH`（下次启动落盘） | `stability_v1` |
| 冻屏/ANR | `hiAppEvent` 监听 `APP_FREEZE` | `stability_v1` |
| JS 未捕获异常 | `errorManager.on('error')` 兜底 | `stability_v1` |
| 未处理 Promise 拒绝 | `errorManager.on('unhandledRejection')` | `stability_v1` |
| 会话数 | 每次 `EntryAbility.onCreate` +1 | `stability_v1` |

代码：`commons/data/services/StabilityMonitor.ets` + `store/StabilityStore.ets`；只记次数/枚举/时间戳，
**不采集堆栈、账号、持仓、输入内容**，不上传。

### 4.2 采集链路验证（注入一次真实崩溃）

| 步骤 | 现象 | 证据 |
|---|---|---|
| 启动 4 次后查看计数 | `session=4 crash=0 freeze=0 jserr=0 rej=0 last=none` | `m13/12-stability-counters.png` |
| 调试面板「触发一次异常」 | 日志 `js_error len=3383` → `stability_event event=js_error` → `event=APP_CRASH` | `hilog -T Stability` |
| 崩溃后重新启动查看计数 | `session=5 crash=1 freeze=0 jserr=1 rej=0 last=APP_CRASH` | `m13/13-stability-after-crash.png` |

> 结论：**崩溃采集链路真实可用**（不是「代码写了但没验证」）。崩溃率 = 1 次崩溃 / 5 次会话（人为注入，
> 用于验证链路；正常会话下为 0）。

### 4.3 弱网/切网 30 次（AC-127：30 次无崩溃）

| 项 | 值 |
|---|---|
| 方式 | 调试面板「稳定性… → 切网 30 次压测」：断网→恢复 ×30（走全局 `ConnectionHub` 状态机） |
| 耗时 | 30 × (150ms + 150ms) ≈ 9.0s |
| 状态迁移 | `hilog -T ConnLog` 计 **60 条** `net_state=`（30 offline + 30 online） |
| 结果 | 进程存活（pid 不变）、无崩溃、页面数据正常（`m13/14-net-stress-30.png`） |

### 4.4 前台持续运行 soak

| 项 | 值 |
|---|---|
| 场景 | 3 窗 PK + 深色，前台持续 **10 分钟**（行情每秒推送到 3 窗 + 图表重绘） |
| 结果 | 见 §4.5（本轮实测补记） |

> **实测补记（可验证的 5 分钟复跑）**：因中途系统通知栏被唤起，10 分钟那一轮无法保证全程前台，
> 另做一轮**同场景 5 分钟**并留存首尾截图与内存：
> start `Total Pss = 138,289 kB ≈ 135.0MB`（`m13/17-soak-start.png`）→
> end `134,539 kB ≈ 131.4MB`（`m13/17b-soak-end.png`），**pid 不变、PSS 不增长（略降）**、无崩溃/冻屏；
> 3 窗行情按 1s 持续刷新、图表持续重绘，符合「长时间前台不泄漏」的判定。

### 4.5 缺口（登记，不阻塞内测）

| # | 项 | 原因 | 处理 |
|---|---|---|---|
| 1 | **前台 1h 耗电 ≤3%** | 设备当前处于**充电状态**（`chargingStatus=1`、`pluggedType=2`），无法测放电；`nowCurrent` 为充电电流，不能用于耗电结论 | 换「非充电 + 满电」条件补测；本轮以 10 分钟 soak + 60 次切网替代稳定性证据 |
| 2 | 崩溃率/ANR 率的**线上口径** | 无 AGC 崩溃服务（零权限、零联网、不接三方），只能本机会话比 | 上架后如需线上口径，在 AGC 侧开启并更新隐私政策 §4（登记在 `release-metadata-phase2.md`） |
| 3 | ANR 主动注入 | 未构造主线程 6s 卡死（会触发系统 ANR 弹窗，影响后续用例） | `APP_FREEZE` 监听已挂；需要时用调试通道补 |

## 5. release 包卫生

| 项 | 结论 | 证据 |
|---|---|---|
| 调试入口在 release 不可达 | ✅ 长按「自选股」标题无调试面板（`m13/15-release-no-debug-menu.png`）；`check-compliance` X-03 静态拦截「引用 DEBUG 无守卫」 | 截图 + 门禁 |
| 深色/横屏/字号未因 M13 回归 | ✅ M12 用例与截图沿用；M13 新增页面只用既有 30 个 token（`check-dark-tokens` D-01~D-03 绿） | 门禁 |
| 隐私同意/撤回后不残留脏状态 | ✅ 撤回后 preferences 无 `privacy_consent_v1`（磁盘核对） | §6-4 |

## 6. 复现命令

```powershell
cd D:\deepseek_harness_work\xiaoyang-stock
# 1) 干净 release 构建 + 体积
devecocli build clean; devecocli build --build-mode release
(Get-Item products\entry\build\default\outputs\default\entry-default-signed.hap).Length

# 2) 冷启 5 次（每次 force-stop + 清日志）
hdc -t 23E0224222002707 shell "aa force-stop com.example.xiaoyangstock"
hdc -t 23E0224222002707 shell "hilog -r"
hdc -t 23E0224222002707 shell "aa start -a EntryAbility -b com.example.xiaoyangstock"
hdc -t 23E0224222002707 shell "hilog -T StartupPerf -x"    # cold_start_ms / oncreate_ms

# 3) 内存（3 窗 + 深色）
hdc -t 23E0224222002707 shell "pidof com.example.xiaoyangstock"
hdc -t 23E0224222002707 shell "hidumper --mem <pid>"        # Total Pss

# 4) 稳定性计数（磁盘证据）
hdc -t 23E0224222002707 file recv /data/app/el2/100/base/com.example.xiaoyangstock/haps/entry/preferences/xiaoyang_stock_v1 .\pref.xml
# 关注键：privacy_consent_v1 / trade_risk_v1 / stability_v1

# 5) 切网 30 次（真机调试面板）
#    自选页长按标题 → 场景…（持仓页长按标题 → 稳定性…）→ 切网 30 次压测
hdc -t 23E0224222002707 shell "hilog -T ConnLog -x" | Select-String 'net_state='   # 期望 60 条
```

## 7. 口径与偏差

1. **未启用混淆**（与计划 M13-2「`obfuscation-rules.txt` 收紧」不同）：
   `-enable-property-obfuscation` 会重命名 `watchlist_v1` / `trade_account_v1` / `order_journal_v1` 等
   落盘 JSON 的字段名，破坏 1.1.0 → 1.2.0 的本地数据兼容（自选/持仓/委托会读成空）。
   HAP 2.13MB 仅为阈值 21%，混淆收益与回归风险不成比例 → **本轮保持关闭并登记**（见进度文档 §9 偏差）。
2. **冷启口径为「应用内」**：起点是进程创建、终点是应用首个内容帧；不含桌面点击到 AMS 调度的系统段
   （系统级口径需 SmartPerf/Profiler 或 AGC，登记为待补）。
3. **内存证据用 debug 上界**：release 同场景 123.3MB 已单独记录；深色只在 debug 可脚本化切换（M12 同口径）。
4. **耗电未测**：见 §4.5-1。
