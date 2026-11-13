# M9 模拟行情通道 性能与流量记录

> 版本：v1.0 · 2026-11-14 · 设备：Mate 60 Pro（`23E0224222002707`，1200×2720，`fontScale 1.0`）
> 前提：**无真实行情源，无网络请求**。所有数据由本地 Mock 生成、经 `QuoteChannel`（鉴权/校验/限流）分发。
> 因此本文件的「流量」项恒为 0；时延项衡量的是「本地链路 + 缓存 + 首帧渲染」。

---

## 1. 冷启出内容（AC-111，目标 ≤800ms）

口径：`WatchlistVM.load()` 起点 → `applyData()` 完成（列表可交互）的打点，见日志
`QuoteLog: watchlist_ready ms=<n> quotes=<n>`；进程用 `aa force-stop` 后由 `aa start` 冷启。

| 场景 | 打点 | 结果 |
|---|---|---|
| 缓存命中（TTL 内重启） | `quote_cache_hit codes=51` → `watchlist_ready ms=32 quotes=51` | **32ms** |
| 缓存未命中（首启/过期） | `quote_cache_miss filled=51` → `watchlist_ready ms=33 quotes=51` | **33ms** |
| 缓存预热日志 | `quoteCache ready size=51` | 读盘 51 条 ≤10ms（与首帧并行） |

结论：两种路径都远低于 800ms；差异主要来自 51 条快照的构建与首帧布局，缓存路径省掉了一次
`getSnapshots` round-trip（本地 Mock 下约 1ms，接后端后将是主要差异项）。

**复现命令**

```powershell
hdc -t <sn> shell "hilog -r"
hdc -t <sn> shell "aa force-stop com.example.xiaoyangstock"
hdc -t <sn> shell "aa start -a EntryAbility -b com.example.xiaoyangstock"
hdc -t <sn> shell "hilog -x | Select-String 'watchlist_ready|quote_cache|quoteCache'"
```

---

## 2. 推送节奏与降频

| 模式 | 间隔 | 说明 |
|---|---|---|
| `push` | 1s | Mock 每 tick 推 1~3 只（保证单行刷新可观察） |
| `throttled` | 5s（或服务端 `retryAfterMs`） | 429 后降频，UI 出「行情更新已降频」 |
| `polling` | 5s 批量快照 | 连续 3 次 429 |
| 恢复 | 60s 无 429 | 自动回 `push` |

实测：注入 429 后 2s 内提示条出现、行情刷新间隔变为 5s；清除注入 60s 后恢复（单测覆盖恢复边界）。

---

## 3. 流量

| 项 | 值 |
|---|---|
| 网络请求数 | **0**（无 `@kit.NetworkKit` 调用，无 INTERNET 权限） |
| 前台流量 | **0 KB/min** |
| 指标口径 | 接本地后端后按 `docs/api-contract-v1.md` 的 WS 帧统计（目标 ≤30KB/min / 50 只） |

---

## 4. 帧校验开销

注入异常帧 12s，`QuoteChannel` 统计：`accepted=28 drop=12/stale=0,range=4,limit=4,empty=4`。
校验为纯内存判定（Map 查时间水位 + 两次数值比较），未观察到掉帧或卡顿；列表 45 行滚动、
卡片 50 卡静止指标与 M8/M12 基线一致（本次未改列表/卡片渲染路径）。

---

## 5. 自动化规模

| 模块 | 例数 | 说明 |
|---|---|---|
| `commons_data`（新增） | **85** | 涨跌停 10、合并 8、校验 9、限流 8、缓存 10、契约 6、鉴权 10、通道 9、时段 9、随机 6 |
| `search` | 48 | 回归无退化 |
| `watchlist` | 21 | 回归无退化 |
| 合计 | **154** | |

---

## 6. 采样比对（M9-7）

```
$ node scripts/compare-quote.mjs shots/phase2/m9/quote-samples.log
采样 46 条，参与校验 45 条，跳过 1 条（停牌/无昨收）
一致 45 条；舍入差 0；板块规则不符 0；超涨跌停 0；价格越界 0
一致率 100.00%（阈值 99.5%）  PASS
```

比对方式：用独立实现的板块规则（10/20/30/5 + 两位小数）复算 `limitUp/limitDown`，
再校验 `last ∈ [limitDown×0.98, limitUp×1.02]` 且落在 `[0.01, 100000]`。
