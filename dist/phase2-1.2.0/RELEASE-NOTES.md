# 小杨股票 · 1.2.0 内测发布说明

> 日期：2026-11-14 · 版本：**1.2.0 / 1002000** · 范围：阶段二 2b（M9 模拟行情 / M10 模拟交易 / M11 持仓 / **M13 合规与上架**）
> 关联：[阶段二进度文档](../../docs/阶段二进度文档.md)、[发版清单 v2.0](../../docs/release-checklist-phase2.md)、
> [M13 用例](../../validation/phase2-m13-test-cases.md)、[M13 性能/稳定性](../../docs/perf/phase2-m13.md)、
> [隐私政策](../../docs/privacy-policy.md)、[SDK 与权限清单](../../docs/phase2-sdk-list.md)

## 1. 产物

| 项 | 值 |
|---|---|
| 文件 | `entry-default-signed.hap` |
| 大小 | **2,228,592 bytes ≈ 2.13 MB** |
| SHA256 | `D3805A2495A1568D2BF2CE5A3C6E71828A590DDA00BE29F27128C3CF45149D93` |
| 包名 / 版本 | `com.example.xiaoyangstock` / **1.2.0（1002000）** |
| 签名 | DevEco 自动生成的**调试证书**（`debugKey`）——**仅内部侧载，未提交 AGC** |
| 构建 | `devecocli build clean` → `devecocli build --build-mode release` |

## 2. 相对 1.1.0 的变化

| 模块 | 内容 |
|---|---|
| M9 模拟行情 | 契约 v1.1（`seq`/`onError`/`capabilities`）、鉴权通道、帧校验、限流降级、行情缓存、确定性假数据、交易时段驱动；全局「模拟数据 · 仅供学习参考」 |
| M10 模拟交易 | 本地撮合（买卖/冻结/撤单/幂等流水）、委托列表 7 状态筛选与分页、成交回执、卖出方向 |
| M11 持仓与收益 | 持仓页（汇总/排序/三行五项）、收益口径文档、与自选/详情联动 |
| **M13 合规与上架** | **首启隐私同意（同意/拒绝退出/页内政策/撤回）**、隐私政策页、**0 权限 + SDK 清单 + 合规门禁（gate 第 7 步）**、**首笔风险揭示**、冷启打点、稳定性采集（崩溃/冻屏/JS 异常）与调试压测 |

## 3. 安装与验证

```powershell
cd D:\deepseek_harness_work\xiaoyang-stock
hdc -t 23E0224222002707 install -r dist\phase2-1.2.0\entry-default-signed.hap
# 首启会先出现隐私同意页（同意 → 自选；不同意 → 二次确认退出）
# 验证：首页底部「隐私政策 / 撤回同意」；详情「去交易」→ 首次提交弹风险揭示
```

## 4. 质量基线

| 项 | 结果 |
|---|---|
| 构建 / 门禁 | `build` ✅ + **8 步 gate** 全绿（含合规 X-01~X-05） |
| Local Test | **237/237**（search 50 / watchlist 21 / commons_data 166） |
| UiTest | **22/22**（Mate 60 Pro 真机；含同意基线与「撤回→重新同意回到四 Tab」回归例） |
| 冷启 P90 | **241ms**（release，应用内口径，5 次） |
| 内存峰值 | **154.2MB**（3 窗 + 深色，debug 上界；release 3 窗 123.3MB） |
| 稳定性 | 崩溃采集链路注入实测 `crash=1 jserr=1`；切网 30 次无崩溃；3 窗深色 5 分钟 soak PSS 135.0→131.4MB |

## 5. 已知限制

1. 数据全模拟（无真实行情/券商），不构成投资建议；首页/资讯仍为占位。
2. 签名仍为调试证书；AGC 提审前须替换发布证书 + Profile（外部）。
3. 隐私政策外网 URL、客服邮箱、法务签字待补（应用内全文已可查）。
4. 前台 1h 耗电未测（设备充电条件所限）；线上崩溃率/ANR 需 AGC。
5. 未启用混淆（属性混淆会破坏 preferences JSON 兼容），HAP 体积为阈值 21%。
6. 折叠真机、深色冷启、读屏听测、图表 pinch 缩放沿用 2a 缺口。

## 6. 回滚

回装上一版：`hdc -t 23E0224222002707 install -r dist\phase2-1.1.0\entry-default-signed.hap`
（演练记录见发版清单 §7：回退不丢数据、1.1.0 忽略新增键；再升回 1.2.0 不重复弹同意。）
