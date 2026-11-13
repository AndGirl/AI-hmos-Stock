# 行情通道与前后端契约 v1（模拟数据）

> 版本：v1.0 · 2026-11-14 · 状态：**M9-1 已落地客户端侧；后端待实现**
> 适用：M9（模拟行情）、M10（模拟交易）与后续「App ↔ 本地后端」联调。
> 前置结论：**本项目永不接入真实行情与真实交易**。所有数据均为本地生成的模拟数据，
> 仅供学习与流程演示，不构成任何投资参考。见 §0。

---

## 0. 定位与红线

| 项 | 口径 |
|---|---|
| 数据来源 | **100% 本地生成**（App 内 Mock 通道 / 本地后端）。无供应商、无真实账户、无真实委托 |
| 展示 | 全局常驻「模拟数据 · 仅供学习参考」；文案中禁止出现「实时行情」类表述 |
| 真实行情 | 不做。D50 已作废，不再有「接真实源」的路线 |
| 真实交易 | 不做。D51 已作废；M10 改为本地模拟撮合 |
| 契约演进 | **只加不改**：新增成员一律可选（`?`），缺省行为与旧实现等价 |
| 门禁 | `scripts/check-contracts.mjs`（K-01~K-04）静态校验接口与实现齐备、可选成员不得写成必需 |

---

## 1. 客户端通道契约 v1.1 增量（已实现）

| 契约 | 新增（全部可选） | 用途 | 缺省行为 |
|---|---|---|---|
| `QuotePatch.seq?: number` | 帧序号 | 乱序丢弃、1s 合窗取最大 seq（AC-108） | 缺省视为 `0` → 不做序判定 |
| `QuoteListener.onError?(error)` | 下行错误通道 | 429 限流、401 鉴权失败（AC-109） | 未实现者不收到回调 |
| `QuoteError.retryAfterMs?: number` | 429 建议等待 | 降频节奏 | 缺省按 5s 下限 |
| `QuoteErrorReason` 增 `'unauthorized'` | 鉴权失败 | 刷新票据失败后进未授权态 | 旧值不受影响 |
| `QuoteProvider.capabilities?(): QuoteCapabilities` | 能力声明 | 无推送退轮询、无盘口不渲染 | 缺省按「全能力」处理 |
| `DetailProvider.chartPage?(code, period, beforeTs, count)` | K 线分页 | 500 根上限外翻页 | 缺省回退 `loadChart` |

### 1.1 帧序号规则（`rules/QuoteMergeRules.ets`）

```
seq 缺省/0  → unsequenced：接受，水位不变
seq >  水位 → accept：接受，水位 = seq
seq == 水位 → duplicate：丢弃（计数 +1）
seq <  水位 → out_of_order：丢弃（计数 +1），不进 UI
```

- 重订阅/换通道时**清空水位**（新通道 seq 从 1 重新计数，否则会被整体误判为乱序）。
- 1s 合窗：同 code 多帧按字段合并，`seq` 取最大；未定义字段不覆盖旧值。

### 1.2 帧校验规则（`rules/FrameValidator.ets`，AC-110）

| 判定 | 条件 | 处理 |
|---|---|---|
| `empty_frame` | patch 不含任何可变行情字段 | 丢弃 |
| `stale_time` | `snapshotTime` ≤ 该 code 上一条 | 丢弃（时间必须严格递增） |
| `price_invalid` | `last` 不在 `[0.01, 100000]` | 丢弃 |
| `price_out_of_limit` | `last` 在 `limitUp/limitDown` ±2% 容差外 | 丢弃 |
| `ok` | 其余 | 接受并推进时间水位 |

连续 10 帧异常 → 触发一次全量重订阅（`shouldResubscribe`）。异常帧**不报错给用户**，只累计计数并上报埋点 `quote_drop`。

### 1.3 限流降级（`rules/RateLimitRules.ets`，AC-109）

```
push ──429→ throttled（5s） ──累计 3 次→ polling（HTTP 快照 5s）
  ↑                                          │
  └──────── 持续 60s 无 429 ─────────────────┘
```

- `retryAfterMs` > 5s 时按服务端建议，否则按 5s 下限；
- 恢复以**最后一次 429** 起算 60s；
- 降级只改刷新节奏，**不改 UI 结构**；用一条「行情已降频」提示（与连接提示条同位置、不叠加）。

### 1.4 缓存（`rules/QuoteCacheRules.ets`，AC-111）

| 项 | 口径 |
|---|---|
| Key | `quote_cache_v1`（经 `StorageAdapter` 唯一入口） |
| 上限 | 100 条 |
| TTL | 交易时段（pre/auction/open/lunch）**60s**；收盘后（closed/停牌）**当日有效** |
| 写入 | 首屏快照批量写、增量帧 200ms 合并写 |
| 读取 | 冷启预热后内存直读，**先渲染缓存再订阅**（≤800ms 出内容） |
| 排序 | **不参与排序**（沿用列头快照序） |
| 不入缓存 | 价格类字段全空（停牌/未开盘）的快照 |

### 1.5 持仓契约（M11-1，客户端已实现）

| 契约 | 签名 | 说明 | 缺省行为 |
|---|---|---|---|
| `PositionProvider.positions(accountId?)` | `Promise<Position[]>` | 主账户持仓快照；`accountId` 可选（缺省 = 账户列表第一个） | 无持仓返回 `[]` |
| `PositionProvider.summary(accountId?)` | `Promise<PositionSummary>` | 市值/当日/累计/成本/只数/未估值只数 | 汇总为空时全 0 |
| `PositionProvider.positionOf?(code)` | `Promise<Position \| null>` | 单标的持仓（详情「已持有」用）；**可选成员**，缺失时调用方按 0 处理 | 无持仓返回 `null` |
| `Position` | `{code,name,qty,available,costPrice,last,prevClose,marketValue,pnl,pnlRatio,weight,dayPnl,costBasis,status,accountId}` | 只读快照，Provider 每次按「持仓 + 行情快照」现算，**不落盘** | — |
| `PositionSummary` | `{marketValue,dayPnl,totalPnl,costTotal,count,unvalued}` + `ratio()` | `unvalued` = 无有效价的只数 | — |
| `costBasis` | `'withFee' \| 'withoutFee'` | 本期恒 `withoutFee`（本地撮合不计佣金/印花税） | 字段只读 |

**实现与口径**：

- 客户端实现 `provider/LocalPositionProvider.ets`（命名与 M10 的 `LocalTradeProvider` 一致）；
- 估值/盈亏/仓位/排序全部是纯函数：`rules/PositionRules.ets`，口径见
  [phase2-position-metrics.md](phase2-position-metrics.md)；
- **不设 `subscribe`**：行情推送统一走 `QuoteBus`（`DataServices.quoteBus()`），持仓页不新建通道；
- 持仓来源 `trade_account_v1.holdings[]`，M11 增 `lastPrice` 字段（最近一次有效价，旧 JSON 缺字段回落成本价）；
- 停牌/退市快照 `last`/`prevClose` 均为 `null` 时用 `lastPrice` 估值、当日盈亏计 0。

**接本地后端时**：`GET /accounts/{id}/positions` 返回同形 `Position[]` 即可；
服务端只需给「数量/成本 + 最新价 + 昨收」，估值与盈亏口径仍由客户端按同一套纯函数计算（便于与单测对齐）。

---

## 2. 前后端协议（下一轮实现后端时按此施工）

> 本地后端仅监听 `127.0.0.1`，通过 `hdc rport tcp:8080 tcp:8080` 反代到真机；
> 不部署公网、不做账号体系、不接任何第三方。

### 2.1 基址与鉴权

```
REST   http://127.0.0.1:8080/api/v1
WS     ws://127.0.0.1:8080/api/v1/stream
```

`POST /auth/token`

```jsonc
// req
{ "ticket": "dev-<deviceId>-<ts>" }
// 200
{ "token": "mock-token-<random>", "expiresIn": 7200 }
// 401
{ "error": { "code": "unauthorized", "reason": "ticket_invalid" } }
```

- 无真实登录：`ticket` 是本地生成的伪设备票据，后端不校验真实性，只保证「非空 + 未过期」；
- token 只放内存，**不落盘**；失效时客户端刷新一次，仍失败则进未授权态并停止重试。

### 2.2 批量快照

`GET /quotes?codes=600519,000001,300750`

```jsonc
{
  "seq": 1234,
  "snapshotTime": 1765670400000,
  "items": [ /* QuoteSnapshot，字段同 commons/data/model/QuoteModels.ets */ ]
}
```

- `items` 顺序与 `codes` 一致，未知 code 跳过（不报错）；
- `limitUp` / `limitDown` 允许下发（**下发优先**，缺失时客户端按板块推导）。

### 2.3 市场时段

`GET /market/status` → `{ "status": "open", "asOf": 1765670400000 }`

`status ∈ pre | auction | open | lunch | closed`；停牌是**个股属性**（`QuoteSnapshot.status='suspended'`），不在市场时段里表达。

### 2.4 推送通道

客户端 → 服务端：

```jsonc
{ "type": "sub",   "codes": ["600519", "000001"] }
{ "type": "unsub", "codes": ["000001"] }
{ "type": "ping",  "t": 1765670400000 }
```

服务端 → 客户端：

```jsonc
{ "type": "patch", "code": "600519", "seq": 517, "snapshotTime": 1765670401000,
  "patch": { "last": 1682.5, "chg": 2.5, "pct": 0.149, "volume": 12345, "lastVolume": 88 } }
{ "type": "pong",  "t": 1765670400000 }
{ "type": "error", "error": { "code": "600519", "reason": "rate_limited", "retryAfterMs": 5000 } }
```

约定：

| 项 | 口径 |
|---|---|
| 心跳 | 客户端每 **10s** 发 `ping`；连续 2 次无 `pong` → weak，3 次 → offline（汇入 `ConnectionHub` 退避） |
| seq | 每 code 独立自增，从 1 开始；服务端不得回退 |
| 时间 | `snapshotTime` 为 **epoch 毫秒**，严格递增；同 code 回退帧客户端直接丢弃 |
| 退订 | `unsub` 后服务端必须停止推送；客户端 `stats()` 的订阅数同步下降 |
| 限流 | 429 用 WS `error` 帧或 REST `Retry-After` 头；客户端按 §1.3 降频 |
| 鉴权失败 | WS `close code 4001` 或 REST 401 → `unauthorized` |

### 2.5 错误码

| 场景 | REST | WS | `reason` |
|---|---|---|---|
| 票据失效 | 401 | 4001 | `unauthorized` |
| 限流 | 429 + `Retry-After` | `error` 帧 | `rate_limited` |
| 未知标的 | 200 + 空 items | 忽略 | — |
| 服务异常 | 500 | 1011 | `internal` |

---

## 3. 与客户端模拟数据的一致性（M9-7 双源比对）

后端必须能复现 App 内的模拟数值，否则「直连 vs 通道」比对无意义。算法固定为：

```
seed(code) = FNV1a(code) XOR SESSION_SEED       // SESSION_SEED = 20261114
rnd        = mulberry32(seed(code))             // 每次 advance 依次取数
drift     = (rnd() * 2 - 1) * 0.008 * volatility
last'     = clamp(last * (1 + drift), limitDown, limitUp)   // 两位小数
volume'   = volume + (10 + rnd.int(200))
```

参数与实现见 `commons/data/src/main/ets/mock/SeededRandom.ets`、`provider/MockQuoteProvider.ets`。
后端按同一序列生成，即可保证「同种子 → 同一走势」，比对一致率应为 **100%**。

比对项的容差：

| 字段 | 容差 |
|---|---|
| `last` / `limitUp` / `limitDown` | 0（两位小数后完全一致） |
| `pct` | 0.01 个百分点（浮点表示差异） |
| `snapshotTime` | 不比对（各自时钟） |

---

## 4. 未决项

| # | 项 | 处理 |
|---|---|---|
| 1 | 后端技术栈 | 暂定 Node.js + 原生 `http`/`ws`（仓库脚本已是 Node，零额外安装）；实现前再确认 |
| 2 | 联调网络方式 | `hdc rport tcp:8080 tcp:8080`（推荐）或局域网 IP |
| 3 | 鉴权是否保留 | 保留：AC-106 要验「401 刷新一次后转未授权」，删掉就少一条验收 |
| 4 | 多设备并发 | 不做；单机演示 |
