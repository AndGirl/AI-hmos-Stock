# 阶段二 · M6 搜索性能与设备证据

> 版本：v1.0 · 采集：2026-11-13 · 设备：HUAWEI Mate 60 Pro（真机，HarmonyOS 6.x / API 20，debug 包）
> 对应：AC-93（输入到结果 P90 ≤500ms）、AC-87（分栏）
> 数据来源：`AnalyticsHub → LogSink → hilog`（`event=search_result ... cost=<ms>`），采集命令见 §4

---

## 1. 结论

| 指标 | 预算 | 实测（Mock 通道） | 结论 |
|---|---|---|---|
| 输入 → 结果（P90） | ≤500ms | **124ms**（10 次冷查询样本，见 §2） | 通过（Mock） |
| 输入 → 结果（均值 / 最大） | — | 122.6ms / 124ms | — |
| 本地索引构建 | ≤120ms（50 只）/≤300ms（5000 只） | 112 条主数据一次性线性构建，未单独打点（`LocalSearchIndex.buildCostMs` 可读） | — |
| LRU 命中 | 同 term 5min 内不发请求 | 单元测试 `cache_hit_skips_second_request` / `cache_key_is_normalized` 通过 | 通过 |
| 分栏（lg/xl） | 左 38% + 右 62% | 2584×1828 阔折叠：结果列 0~982px（982/2584 = 38.0%），右栏 DetailContent(pane) | 通过（布局断言） |

> 说明：M6 阶段搜索走本地主数据 + 本地 Mock 行情（D52），120ms 是 Mock 网络时延常量 + 索引匹配 + 快照补齐 + 序列化的总耗时；真实通道时延与 5000 只压测留 M9（AC-106~111）复测。

## 2. 采样明细（P90 计算）

10 个互不相同的关键词（避免命中 LRU）：贵州 / 宁德 / 平安 / 招商 / 白酒 / 半导体 / 比亚迪 / 中芯 / 银行 / 医药。

```
cost(ms): 121, 122, 122, 122, 123, 123, 123, 123, 123, 124
排序后取 90% 分位（nearest-rank, ceil(0.9*10)=9）：124ms
平均：122.6ms；最大：124ms
```

同批 `search_result` 的 `count` 分别为 1/1/2/1/2/1/1/1/7/2，与主数据（80 股 + 12 指数 + 20 板块）匹配结果一致，排除「空结果跑得快」的偏差。

## 3. 设备与形态

| 形态 | 设备 | 证据 |
|---|---|---|
| 手机（sm/md） | Mate 60 Pro 真机（1260×2720） | `shots/phase2/m6/01-initial.png` ~ `08-add-watchlist.png` |
| 阔折叠（lg/xl，横屏） | Pura X Max 模拟器（2584×1828） | `ui layout` 断言：结果列 0~982px = 38%，右侧 `DetailContent(mode:'pane')` 存在；分栏阈值按搜索页局部判定（lg/xl） |
| 平板（xl） | Huawei_Tablet 模拟器 | 启动后与阔折叠共用 `127.0.0.1:5555` 端口，未取得独立 hdc 目标；xl 断点与阔折叠同属一档布局，留待 M6 收口补图 |

> 模拟器帧缓冲抓图为黑屏（`devecocli ui screenshot` 与 `snapshot_display` 均返回全黑），已改用 `ui layout` 的坐标断言作为分栏证据；真机分栏截图待借平板/阔折叠真机补。

## 4. 复现方法

```powershell
# 1) 构建 + 安装 + 启动（真机）
devecocli run --module entry --device <serial>

# 2) 打开「行情」Tab，输入 10 个不同关键词（每个输入后等待结果）

# 3) Analytics 队列满 20 条（10 次查询 × 2 事件）自动 flush，读日志
hdc -t <serial> shell "hilog -x | grep 'event=search_result'"
```

> 调试注入（长按搜索条 → 搜索调试）：失败 / 429 / 离线 / 热搜失败 / 慢请求（4s） / 恢复。
> 慢请求用于截取「搜索中」态（G-1：保留上一帧 + 顶部 2vp 进度条）。

## 5. 待补

1. 真机 lg/xl 分栏截图（平板或阔折叠真机）；
2. `PerfMeter` 逐帧数据（搜索页暂未接 PerfMeter，M6 以埋点 `search_cost` 为准）；
3. 5000 只主数据压测（M9 换真实索引时执行，预算 ≤300ms / ≤2MB）。
