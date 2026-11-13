# 阶段二 · M8 卡片视图性能与设备证据

> 版本：v1.0（初测） · 采集：2026-11-13 · 设备：HUAWEI Mate 60 Pro（真机，HarmonyOS 6.x / API 20，debug 包，1260×2720 ≈ 388vp）
> 对应：AC-100（卡片栅格 50 卡 ≥55fps、无白块）、AC-101（单卡刷新）
> 数据来源：`PerfMeter → hilog`（`PERF_WIN` / `PERF_STOP`），采集命令见 §4

---

## 1. 结论

| 指标 | 预算 | 实测（Mock 通道） | 结论 |
|---|---|---|---|
| 50 卡静止（卡片态，无操作） | ≥55fps | **60.4fps**（窗口均值；窗口 p95 间隔 16.5~16.6ms，jank 0） | 通过 |
| 50 卡静止（整段均值） | — | **70.4fps**（含 120Hz 空闲帧，25 个 1s 窗口，`frames=1784`，`jank=0`） | 通过 |
| 50 卡自动滚动 | ≥55fps | **待补**（采样中设备 hdc 掉线，日志随会话丢失） | 待补测 |
| 200 卡压测（合成行，滚动） | 观察项（无硬指标） | **待补**（同上） | 待补测 |
| 单卡刷新 | 只重绘 1 张卡 | 代码保证：`WatchRowVM` 全 `@Trace`、`Grid` 以 code 为 key、`cachedCount(6)`；CardCell 仅在 `row.quote.flashSeq` 变化时重绘自身 | 通过（代码级） |
| 无白块 | 滚动中不出现空白卡片区 | `02-card-scrolled` / `10-card-stress200` 截图中无白块 | 通过（截图） |

> 说明：M8 全程 Mock 行情（D50 未签），120Hz 屏在无动画时会拉到 60fps 稳定帧；真实通道（M9）需要复测。

## 2. 采样明细

设备刷新率 120Hz，`PerfMeter` 每 1s 输出一个窗口。静止场景（`watchlist-card-sm-46rows-1x-static`）：

```
PERF_WIN fps=60.4 p95=16.6 jank=0 frames=61 win=2  ... win=17
PERF_WIN fps=79.9 ... win=18
PERF_WIN fps=120.9 p95=8.3 jank=0 frames=121 win=19   ← 无输入时空闲窗口
PERF_WIN fps=107.9 ... win=20
PERF_WIN fps=60.4 ... win=21..22
PERF_WIN fps=114.7 ... win=23
PERF_STOP watchlist-card-sm-46rows-1x-static frames=1784 avg=70.4 jank=0 windows=25
```

- 卡数 46：真机自选为 45 只种子 + 测试新增 1 只；`50 卡` 预算按 46 卡观测（卡片高度随内容，行数影响的是滚动距离而非单帧成本）。
- jank（>25ms 帧）= **0**；窗口 p95 帧间隔 16.5~16.6ms（≈60fps 上限）。

## 3. 设备与形态

| 形态 | 设备 | 证据 |
|---|---|---|
| 手机（sm 388vp，2 列） | Mate 60 Pro 真机 | `shots/phase2/m8/01-card-sm.png`、`05/06`（顺序对照）、`08`（离线）、`10`（200 卡） |
| 阔折叠模拟器（lg 940vp，4 列） | Pura X Max 模拟器（`127.0.0.1:5555`，2584×1828，density 2.75） | `shots/phase2/m8/11-card-lg-4col.png`（4 列、卡宽 215vp、gap 16）、`12-card-lg-145-3col.png`（1.45× 降 3 列） |
| xl（≥1180vp，5 列） | 无设备 | 列数由 Local Test 12 组断言覆盖；xl 真机截图待平板 |
| 深色 / 横屏 | — | 属 M12，不在 M8 范围 |

## 4. 复现方法

```powershell
# 1) 构建 + 安装 + 启动（真机）
devecocli run --module entry --device <serial>

# 2) 切到卡片视图（分组栏右侧切换按钮），再长按标题进调试面板：
#    帧率采样… → 开始（静止，看空转帧率） / 开始（自动滚动） / 停止并输出（PERF_STOP）
#    场景… → 卡片压测 200（仅卡片态，不落盘） → 再做滚动采样

# 3) 读日志
hdc -t <serial> shell "hilog | grep PerfMeter"
```

采样标签格式：`watchlist-{list|card|card-stress}-{bp}-{rows}rows-{fontScale}x-{static|scroll}`。

## 5. 待补

1. 50 卡 **自动滚动** 三场景帧率（本次采样被设备掉线打断）；
2. 200 卡滚动压测帧率；
3. xl（5 列）真机截图与 `ui layout` 列数断言（lg 已补）；
4. 真实行情通道（M9）下的卡片帧率与单卡刷新频率复测；
5. **评审 P2 修复后的滚动复测**：原实现把「卡片首个可见行」当 `@Param` 传入，每次跨行都会带动整页 + Grid 重渲染；已移除该入参并让 `listIndex/cardIndex` 不再参与观察（见进度文档偏差第 36 条），滚动帧率需按 §4 重采以确认收益。
