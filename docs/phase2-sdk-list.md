# 阶段二 SDK 与权限清单（M13-1 / AC-125）

> 版本：v1.0 · 日期：2026-11-14 · 适用：小杨股票 **2b / 1.2.0**
> 用途：AGC 上架材料的「第三方 SDK 清单」与「权限使用说明」**唯一事实来源**。
> 门禁：[scripts/check-compliance.mjs](../scripts/check-compliance.mjs) 的 X-01/X-02 会**双向**比对本文与工程实际，
> 多登记或少登记都会失败——改依赖必须同步改本文，反之亦然。

## 1. 结论（先看这个）

- **运行期第三方 SDK：1 个**，为开源图表库（本地渲染、不联网、不采集）；
- **广告 / 统计 / 推送 / 崩溃上报类 SDK：0 个**（埋点只写本机 hilog，见 `commons/basic/services/Analytics.ets`）；
- **系统权限：0 个**（`module.json5` 无 `requestPermissions`）；
- **网络能力：0 处**（全工程无 `@kit.NetworkKit` / `http` / `fetch` / `WebSocket` 调用，M9 行情与 M10 交易均为本地模拟）。

## 2. 第三方 SDK 清单

<!-- SDK-LIST:BEGIN -->
| 名称 | 版本 | 许可 | 引入模块 | 用途 | 是否采集个人信息 | 是否联网 |
|---|---|---|---|---|---|---|
| `@ohos/mpchart@3.0.31` | 3.0.31 | Apache License 2.0 | `commons/data`（`chart/ChartEngine.ets`）、`features/detail`（`view/ChartArea.ets`） | K 线 / 分时 / 柱状图**本地绘制** | 否 | 否 |
<!-- SDK-LIST:END -->

> 说明：
> 1. `@ohos/mpchart` 为 OpenHarmony TPC 开源库（[gitcode](https://gitcode.com/openharmony-tpc/ohos_mpchart)），
>    仅使用其 `LineChart` / `CandleStickChart` / `BarChart` 组件，不调用任何网络或统计接口。
> 2. 测试期依赖 `@ohos/hypium`、`@ohos/hamock` 只在 `devDependencies`，不打包进 HAP，不计入上架清单。
> 3. 本地 HAR（`watchlist` / `detail` / `trade` / `pk` / `search` / `account` / `commons_*`）为本项目自有代码，不是三方 SDK。

## 3. 系统权限清单

<!-- PERMISSIONS:BEGIN -->
| 权限 | 是否申请 | 用途 | 拒绝后的影响 |
|---|---|---|---|
| （无） | 否 | 本应用无任何需要授权的系统能力 | 无 |
<!-- PERMISSIONS:END -->

> **权限最小化口径（AC-125）**：当前**不申请任何权限**——不申请网络（`ohos.permission.INTERNET`）、
> 不申请网络信息（`ohos.permission.GET_NETWORK_INFO`）、不申请位置/通讯录/相机/麦克风/存储。
> 连接状态（`ConnectionHub` 的 online/weak/offline）是**本地模拟**的，不读真实网络。
>
> 允许的白名单只有 `ohos.permission.INTERNET` 与 `ohos.permission.GET_NETWORK_INFO`（为「本地后端」接入预留）；
> 一旦声明，必须同时：①在本表登记用途；②在隐私政策「三、权限说明」改写；③`check-compliance` X-02 通过。

## 4. 数据出境与共享

- 不采集、不出境、不共享：应用内无账号体系、无设备标识上报、无第三方统计；
- 全部业务数据（自选/分组/搜索历史/视图偏好/行情缓存/模拟账户/委托/幂等流水/隐私同意记录）只落本机应用沙箱，
  卸载即删除；键名清单见 [privacy-policy.md](privacy-policy.md) §2。

## 5. 维护规则

1. 新增/升级依赖 → 改 `oh-package.json5` **并**改本文第 2 节表格（版本号必须一致）；
2. 新增权限 → 先确认「非申请不可」，再改 `module.json5` + 本文第 3 节 + 隐私政策第三节；
3. 每次发版前跑 `node scripts/check-compliance.mjs`（已并入 `scripts/gate.ps1` 第 8 步）。
