# M9 模拟行情通道 验收用例（AC-106~111）

> 版本：v1.0 · 2026-11-14 · 状态：**代码已落地并在真机取证**
> 口径变更：本项目**永不接入真实行情/真实交易**（个人学习项目，无牌照、无供应商）。
> 原计划的「真实行情通道」改为「**模拟行情通道 + 后续本地后端**」，AC-106~111 的断言保留，
> 但「服务端」指**本地通道/将来的本地后端**，不是供应商。见 [api-contract-v1.md](../docs/api-contract-v1.md)。
>
> 证据目录：`shots/phase2/m9/`、`docs/perf/phase2-m9.md`。设备：Mate 60 Pro（`23E0224222002707`）。

---

## 0. AC 口径改写（与原表的差异）

| AC | 原口径（真实供应商） | 现口径（模拟通道） |
|---|---|---|
| AC-106 | 登录票据换**行情 token** | 设备内伪票据换**模拟 token**；401 只刷新一次；失败进未授权态 |
| AC-107 | 按 code 订阅、多窗合并、退订释放 | **不变**（本地通道同样走一套订阅/合并/退订） |
| AC-108 | 增量帧 `{seq, code, patch}`、1s 合窗、乱序丢弃 | **不变** |
| AC-109 | 429 降频/轮询/60s 恢复/banner | **不变**，429 用调试注入 |
| AC-110 | 时间单调/价格区间/涨跌停与服务端一致 | 涨跌停改为**本地板块规则**（10/20/30/5，下发优先）；其余不变 |
| AC-111 | 冷启先缓存 ≤800ms、TTL 60s/当日 | **不变** |

---

## 1. AC-106 鉴权与连接

**前置**：真机已装包；自选页可长按标题进调试面板。

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 106-1 | 冷启进入自选页 | `hilog` 出现 `token_state=valid`；行情正常跳动 | `quote_recover ... token_state=valid` |
| 106-2 | 调试面板 → 场景 → 行情通道 → **鉴权失败 401** | 1s 内顶部出现 `行情登录已失效，请重新进入页面`（红点）；行情停止更新；**不反复刷错误** | [07-unauthorized-banner.png](../shots/phase2/m9/07-unauthorized-banner.png)；日志 `quote_recover ... token_state=unauthorized refresh=1` |
| 106-3 | 再点 **恢复通道** | 提示条消失，行情恢复；`after[... token_state=valid refresh=0]` | 日志同一行 before/after |
| 106-4 | 连接退避 | 断线注入（网络… → 断线）后按 1→2→4→8→16→30s 重试，恢复回 1s | `ConnLog net_retry attempt=... delay=...`（沿用 M5 既有链路） |

**单测**：`AuthClient` 10 例（首换、过期重换、401 刷新一次、二次 401 锁定、刷新失败立即锁定、reset 解锁、token 不入日志）。

---

## 2. AC-107 订阅合并 / 退订释放

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 107-1 | 自选页 + 详情页 + 比价窗同时看同一只 | 通道 `subs` 不随窗口数线性增长；`QuoteBus` provider 侧仅 1 路 | `hilog` `stats()` → `subs=1 codes=46` |
| 107-2 | 关闭全部窗口 | 订阅数归零，`QuoteBus` 停表 | 单测 + 日志 |

**说明**：`QuoteBus` 负责「多个 sink 合并成一路 provider 订阅」，`QuoteChannel` 只保证每个外部订阅对应一路内部订阅。

---

## 3. AC-108 增量帧与乱序

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 108-1 | 正常推送 | 1s 合窗，同 code 多帧按字段合并、`seq` 取最大 | 单测 `merge_takes_max_seq_and_latest_fields` |
| 108-2 | 注入重复/乱序帧 | 丢弃且**不进 UI**；`QuoteBus.stats()` 的 `drop=` 增加 | 单测 8 例（accept/duplicate/out_of_order/unsequenced/跳帧） |
| 108-3 | 重订阅 | 水位清零，新通道 seq 从 1 开始不被误判乱序 | 单测 + 代码 `resubscribe()` |

---

## 4. AC-109 限流降级

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 109-1 | 调试 → 行情通道 → **限流 429（降频 5s）** | 2s 内顶部出现 `行情更新已降频，数据可能延迟`；行情刷新变 5s | [05-throttled-banner.png](../shots/phase2/m9/05-throttled-banner.png) |
| 109-2 | 连续 3 次 429 | 转轮询（5s 批量快照） | 单测 `three_429_switches_to_polling` |
| 109-3 | 清除注入后 60s | 自动恢复 `push`，提示条消失 | 单测 `recover_after_60s_quiet` + 真机恢复 |
| 109-4 | 服务端 `retryAfterMs` | 大于 5s 时按服务端建议 | 单测 `server_retry_after_is_honoured` |

---

## 5. AC-110 帧校验

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 110-1 | 调试 → 行情通道 → **异常帧注入**，跑 10s | UI 无任何脏数据（价格不乱跳、不回退） | [06-badframe-drop-stats.png](../shots/phase2/m9/06-badframe-drop-stats.png) |
| 110-2 | 再点 **恢复通道** | 统计串出现丢弃计数：`accepted=28 drop=12/range=4,limit=4,empty=4` | 日志 `quote_recover before[...]` |
| 110-3 | 时间回退帧 | 丢弃并计 `stale`，水位不回退 | 单测 `drop_stale_time`（真机 12s 采样内未命中 stale，见 §7） |
| 110-4 | 连续 10 帧异常 | 触发一次全量重订阅（最小间隔 5s） | 单测 `resubscribe_after_ten_bad_frames` |
| 110-5 | 涨跌停推导 | 主板 10% / ST 5% / 科创·创业 20% / 北交所 30%，下发优先 | 单测 9 例 + `scripts/compare-quote.mjs` 真机采样 **一致率 100%** |

**采样比对**（M9-7）：

```
导出行情采样 → hdc -t <sn> shell "hilog -x" | Set-Content dump.log -Encoding utf8
node scripts/compare-quote.mjs dump.log
→ 采样 46 条，参与校验 45 条，跳过 1 条（停牌）；一致 45；一致率 100.00%
```

---

## 6. AC-111 缓存与冷启

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 111-1 | 冷启（缓存有效） | 列表**直接出内容**，先缓存后推送；`watchlist_ready ms=32` | [04-cold-start-cache-hit.png](../shots/phase2/m9/04-cold-start-cache-hit.png) + 日志 |
| 111-2 | 缓存过期（>60s 日内外） | 走网络路径，`quote_cache_miss filled=51`，同样在 800ms 内出内容（本地 Mock 无网络时延） | 日志 |
| 111-3 | TTL 口径 | 交易时段 60s；收盘/停牌当日有效 | 单测 `trading_ttl_is_60s` / `closed_ttl_runs_to_end_of_day` |
| 111-4 | 停牌股也要缓存 | 否则有 1 只停牌时缓存命中率永远差 1 条 | 单测 `suspended_snapshot_is_cacheable` |
| 111-5 | 缓存不参与排序 | 冷启首帧顺序 = 列头快照序 | 代码：`repo` 只填 quotes，不排序 |
| 111-6 | 「切标的先缓存后网络」 | 详情页沿用 `cachedDetail`（M2 既有） | 本次未改详情路径 |

---

## 7. 已知缺口

| # | 缺口 | 原因 / 后续 |
|---|---|---|
| 1 | 真机 12s 采样未命中 `stale_time` | 注入按全局轮转，某只标的第一次遇到「时间回退」帧时还没有时间水位；单测已覆盖。后续按 code 轮转可补齐真机证据 |
| 2 | 3 窗并发订阅数未真机实测 | 需要比价 3 窗 + 详情同时打开，日志 `subs=` 断言；单测覆盖合并逻辑 |
| 3 | 冷启时延为「本地 Mock」口径 | 无网络往返；接本地后端后需复测（目标仍为 ≤800ms） |
| 4 | 收盘/盘前等静态时段只验状态推导 | 状态在 `TradingSession` 单测覆盖；界面只做「冻结」，未加「已收盘」角标 |
| 5 | CodeLinter 未在本次环境运行 | 沙箱限制管道输出；需本地终端补跑 |
