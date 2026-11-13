# 阶段二 · M12 横屏与深色性能/设备记录

> 版本：v1.0 · 采集：2026-11-14 · 设备：Pura X Max 模拟器（`127.0.0.1:5555`）
> 形态：展开 2584×1828 ≈ **940×665vp**（宽>高，横屏）；折叠 1264×1848 ≈ **460×672vp**（竖屏）；density 2.75；debug 包
> 对应：AC-122（横屏）、AC-123（深色热切/全站）、AC-124（切换不丢状态）。
> 说明：M12 无独立帧率预算；50 卡/搜索性能沿用 [phase2-m8.md](phase2-m8.md) / [phase2-m6.md](phase2-m6.md)。

---

## 1. 结论

| 项 | 预算 | 实测 | 结论 |
|---|---|---|---|
| 深浅热切（详情 + 分时图） | ≤300ms、无白闪 | 目视即时（点按后下一帧即深/浅色），无白闪/黑屏 | 通过（未逐帧量化） |
| 深色冷启 | 首帧深色、启动窗口不白闪 | **未取证**（模拟器无法脚本化系统深色） | 待真机 |
| 图表重着色 | 只换配色、不重建图表、不重置缩放 | `ChartArea.@Monitor('config.colorMode')` → `engine.setStyle`；`ChartEngine.setStyle` 用 `lastSeries` 重建 DataSet，图表容器与视口矩阵不变 | 通过（代码级 + 热切截图） |
| 图表周期保持 | 切换前后周期不变 | `18-dark-detail-dayk` / `19-light-detail-dayk` 均为「日 K」 | 通过 |
| 列表滚动保持 | 切换前后位置不变 | `16`/`17` 首行均为 `示例科技11`（`ui layout` 坐标 `[55,639]` 一致） | 通过 |
| 折叠↔展开（竖↔横） | 布局分支切换、无崩溃/黑屏 | `21`（460vp 竖屏）→ `22`（940vp 横屏）→ `23`（回竖屏）连续 | 通过 |
| 横屏 62/38 | 左 62%（报价/周期/图表/指标）+ 右 38%（盘口+明细）+ 动作栏固定 | `20`/`24` + `ui layout` `detail_landscape`；左列 583vp、右列 357vp（单测） | 通过 |
| 横屏读数条 | 不遮挡 K 线、动作栏上方 22vp | `25`：长按后读数条在动作栏上方通栏 | 通过 |
| 旋转后十字光标 | 取消，不残留读数 | `25`（有竖线/读数）→ `23`（无竖线/读数） | 通过 |
| 横屏图表高度 | 不挤压、不浪费 | `landscapeChartHeight(665)=226vp`，夹取 160~260vp | 通过（单测） |
| 深色对比度 | 文本 ≥4.5、非文本 ≥3 | `check-contrast`：dark 23/23 文本、5/5 非文本 PASS | 通过 |
| 红绿可辨 | ΔE≥20、亮度差≥15% | dark ΔE 116.5 / 27.0%；light ΔE 121.3 / 32.2% | 通过 |
| 颜色字面量 | `.ets` 清零 | `check-dark-tokens` D-03：**166 文件，0 处** | 通过 |

> 本轮未做 PerfMeter 帧率采样（深色为纯资源替换 + 图表重绘；横屏为一次布局重排，无新增动画/列表）；如后续发现热切/旋转卡顿，再按 M8 的 `PerfMeter` 通道补测。

## 2. 设备与形态

| 形态 | 设备 | 用途 | 证据 |
|---|---|---|---|
| 940×665vp（展开，横屏） | Pura X Max 模拟器 | 横屏 62/38、深色横屏、读数条、热切 | `20`/`22`/`24`/`25` |
| 460×672vp（折叠，竖屏） | 同上 `fold close` | 竖屏详情、旋转后十字光标取消、深色竖屏 | `21`/`23` |
| 388vp 直板 / 平板 xl | 无 | sm/xl 横屏与深色矩阵 | **缺口** |

> 折叠/展开用 `devecocli emulator fold open|close --target 127.0.0.1:5555`；旋转用 `devecocli emulator rotate left|right`（本模拟器宽高由折叠态决定，rotate 对当前 app 不改变窗口尺寸）。

## 3. 复现方法

```powershell
# 安装/启动（debug）
devecocli run --module entry --device 127.0.0.1:5555

# 折叠 ↔ 展开（竖屏 ↔ 横屏）
devecocli emulator fold close --target 127.0.0.1:5555
devecocli emulator fold open  --target 127.0.0.1:5555

# 深色切换（debug 通道）
#   自选页：长按「自选股」→ 外观…（跟随系统/浅色/深色）
#   详情页：长按股票名 → 切换深浅色（M12 验收）

# 证据
devecocli ui screenshot --device 127.0.0.1:5555 --path shots\phase2\m12\xx.png
devecocli ui layout --device 127.0.0.1:5555 --mode simplified

# 门禁 / 单测
node scripts/check-dark-tokens.mjs
node scripts/check-contrast.mjs
```

## 4. 待补

1. 真机系统深色冷启（`aa force-stop` + 拉起，验证启动窗口与首帧）。
2. 4 形态 × 3 主界面矩阵（sm / 折叠 / 阔折叠 / 平板）。
3. 深浅切换逐帧录屏（≤300ms、无白闪）与折叠/展开逐帧（无黑屏）。
4. 图表 pinch 缩放后展开/折叠，验证 `captureViewport/restoreViewport` 的缩放位置保持。
5. 1.45× 字号下 ▲/▼ 不截断的逐列断言；横屏 1.3× 降 4 列的实机截图。
