# 小杨股票 1.1.0（2a 内测包）发布说明

> 版本：1.1.0 / versionCode `1001000` · 构建：2026-11-14 · 构建机 HarmomyOS SDK 26.0.0.105（target/compatible API 20）
> 发布方式：**内部侧载 + 团队真机灰测**（不提交 AGC）；2a 不引入隐私同意页。

## 1. 产物

| 项 | 值 |
|---|---|
| 文件 | `entry-default-signed.hap` |
| 大小 | **1,981,981 bytes ≈ 1.9 MB** |
| SHA256 | `c39b44e96cb8044ec85b41a041b7fc574d67629a06457d280de294b0cd9e714f` |
| 签名 | DevEco 自动生成**调试证书**（`debugKey`，`type: HarmonyOS`） |
| 包内版本 | `pack.info`：`version.name=1.1.0`、`version.code=1001000`；`module.json` 同 |
| 设备类型 | `phone` / `tablet` |

## 2. 2a 交付内容

- **M6 搜索**：本地索引、六级（L0~L6）匹配、空词全部股票、历史/热搜、分栏、深链、就地加/撤自选。
- **M7 添加自选与分组**：添加页复用搜索、多选、目标分组、重复/上限/部分成功、离线 pending、编辑模式 + 5s 撤销、分组管理（≤7/≤8 字）。
- **M8 卡片视图**：`CardMetrics` 2/3/4/5 列、6 项指标、视图切换/锚定/150ms 淡入、`view_pref_v1` 持久化、排序 chip、200 卡压测。
- **M12 横屏与深色**：30 键深色色板 + 跟随系统、深色/对比度门禁、涨跌 ▲/▼、详情 62/38 横屏（指标 6×2、右盘口、底部读数条）、折叠↔展开状态保持、图表视口保持。

## 3. 构建与验证

| 项 | 结果 |
|---|---|
| `devecocli build`（debug） | ✅ |
| `devecocli build --build-mode release` | ✅ |
| `scripts/gate.ps1` 6 步 | ✅（版本 / 2 条占位 / R-01~R-09 150 文件 / 深色 token 166 文件 / 对比度 / lint 0 error 4 warning） |
| Local Test | **69/69**（search 48 + watchlist 21） |
| UiTest | **19/19**（M6 8 + M7 6 + M8 4 + M12 1，Mate 60 Pro 真机） |
| 设备冒烟 | 直板 Mate 60 Pro / 折叠 460vp / 阔折叠 940vp / 平板 1280vp 四形态；主链路、交易、PK 3 窗、深色、横屏、断网、1.45×、深链/404 |

## 4. 安装

```powershell
# 真机（示例序列号）
hdc -t 23E0224222002707 install -r dist\phase2-1.1.0\entry-default-signed.hap
# 或
devecocli run --module entry --device 23E0224222002707 --skip-build
```

## 5. 已知限制

1. 数据全 Mock，无真实行情/交易网关。
2. 交易为演示流程（无开户/KYC/真实风控）。
3. `WindowHost` 系统多实例未实现，仅应用内 PkHost 窗格。
4. 系统深色冷启未真机取证（热切/深色页面已验）。
5. 4 形态 × 深色 × 字号三档为抽样，未全量截图。
6. 读屏语音未听测；图表 pinch 缩放保留未实测。
7. 签名使用调试证书，仅内部侧载；上架 AGC 前必须替换发布证书 + Profile（M13）。
8. 首页/资讯仍为占位（2 条「下阶段开放」）。

## 6. 证据索引

- 集成联调：[validation/phase2-integration-acceptance.md](../../validation/phase2-integration-acceptance.md)
- 验收记录：[validation/phase2-acceptance.md](../../validation/phase2-acceptance.md)
- 发版清单：[docs/release-checklist-phase2.md](../../docs/release-checklist-phase2.md)
- 进度文档：[docs/阶段二进度文档.md](../../docs/阶段二进度文档.md)
- 截图：`shots/phase2/acceptance/`（39 张）、`shots/phase2/m12/`（25 张）
