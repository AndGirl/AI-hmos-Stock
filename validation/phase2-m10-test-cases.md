# M10 模拟交易 验收用例（AC-112~118）

> 版本：v1.0 · 2026-11-14 · 状态：**代码落地中（批次 A/B/C 核心已完成，UI 部分待补）**
> 口径变更：本项目**没有真实券商**（个人学习项目，无牌照、无通道）。
> 原「真实交易」改为「**模拟交易**」：本地假撮合 + 落盘委托/持仓，不产生任何真实委托。
> 契约见 [api-contract-v1.md](../docs/api-contract-v1.md)，撮合规则见 `commons/data/rules/MatchingRules.ets`。
> 设备：Mate 60 Pro（`23E0224222002707`）；证据目录 `shots/phase2/m10/`。

---

## 0. AC 口径改写

| AC | 原口径（真实券商） | 现口径（模拟交易） |
|---|---|---|
| AC-112 | 未开户走引导（说明/去开户/稍后）；无权限禁用+原因 | 委托页「未开通模拟账户」引导卡 + 「开通模拟账户」按钮；无权限码 → 文案 |
| AC-113 | `clientOrderId` 去重；超时不重发，可查询补偿 | **不变**；本地 `order_journal_v1` 承担补偿 |
| AC-114 | 业务错误码→可读文案（6 类）+ 未知兜底 | **不变**；码表 10 个（含 `suspended/delisted/busy`） |
| AC-115 | 当日委托、7 状态、分页 20、空态 | **不变**（`trade_orders_v1`） |
| AC-116 | 仅可撤状态显示撤单 + 二次确认 + 回执 | **不变**（本地撤单幂等） |
| AC-117 | 成交后持仓与可买刷新，可买按最新可用资金重算 | **不变**（`trade_account_v1`：现金/冻结/持仓） |
| AC-118 | 风控原因原样展示，不自造规则文案 | **不变**；文案法务复核留 M13 |

---

## 1. AC-112 开户引导与权限

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 112-1 | 未开通账户（`MockFaults.tradeNoAccount` 或本地 opened=false）进入委托页 | 整页引导卡：「未开通模拟账户」+ 说明 + 「开通模拟账户」 | 代码 + 文案（待补截图） |
| 112-2 | 点「开通模拟账户」 | `LocalTradeProvider.openAccount()` → `trade_account_v1.opened=true` → 立即切到列表（空态） | 单测 `open_account_sets_opened` |
| 112-3 | 未登录/无权限下单 | 拒单 `no_permission`，文案「未登录或未开通账户」 | 单测 `reject_without_login_or_account` + `OrderText.reasonText` |

---

## 2. AC-113 幂等与补偿

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 113-1 | 同 `clientOrderId` 连点两次「确认买入」 | 只产生 1 笔委托，返回同一 `orderId` | 单测 `idempotent_same_client_order_id` |
| 113-2 | 提交超时（2s 无回执） | 弹窗进「结果未知」，**不自动重发** | `TradeVM` 既有逻辑（M3 语义保持） |
| 113-3 | 杀进程后重进 | `order_journal_v1` 仍可查到该键，可 `query` 补偿 | 单测 `persists_across_instances` |

---

## 3. AC-114 错误码与文案

| # | 码 | 文案 | 来源 |
|---|---|---|---|
| 114-1 | `fund_short` | 可用资金不足 | `precheck` 资金校验 |
| 114-2 | `qty_short` | 可卖数量不足 | 卖出校验 |
| 114-3 | `price_limit` | 超出涨跌停价格 | 与 M9 `LimitRules` 同源 |
| 114-4 | `closed` | 当前非交易时段 | `TradingSession` 状态 |
| 114-5 | `suspended` / `delisted` | 标的停牌 / 已退市 | 快照状态 |
| 114-6 | `no_permission` | 未登录或未开通账户 | 账户/登录态 |
| 114-7 | `risk` / `busy` | 风险控制拒绝 / 系统繁忙 | 校验失败/异常 |
| 114-8 | 未知码 | 「未知原因（已上报）」兜底 | `OrderText.reasonText` 默认分支 |

**单测**：`MatchingRules` 14 例覆盖以上拒单分支；码表覆盖由 `reasonText` 分支保证。

---

## 4. AC-115 委托列表

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 115-1 | 自选页标题「当日委托」进入 | 列表页：标题 + 「模拟交易 · 不产生真实委托」+ 状态筛选 | [01-orders-empty.png](../shots/phase2/m10/01-orders-empty.png) |
| 115-2 | 无委托 | 空态「暂无委托」+ 引导文案 | 同上 |
| 115-3 | 下单后回列表 | 出现一行：买入/卖出 + 名称 + 状态 + `代码 · 价格 × 数量` | [02-orders-list.png](../shots/phase2/m10/02-orders-list.png) |
| 115-4 | 7 状态枚举 | 待报/已报/部成/已成/已撤/废单/未知 均有文案与筛选项 | 截图 chip 行 + `ORDER_STATES` |
| 115-5 | 分页 20 | 超过 20 条出现「加载更多」，滚动到底自动加载 | 单测 `paging_and_filter` |
| 115-6 | 下拉刷新 | 下拉触发重新加载第 0 页 | 已实现（`Refresh`），未逐帧取证 |

---

## 5. AC-116 撤单

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 116-1 | 可撤态（待报/已报/部成）行 | 行尾出现「撤单」；终态不出现（不是禁用） | 代码 `cancelable` + 单测 `cancel_rules` |
| 116-2 | 点「撤单」 | 二次确认弹窗（取消 / 确认撤单） | 代码 |
| 116-3 | 确认撤单 | 行变「撤单中」→ 回执后「已撤」；Toast「已撤单」 | 单测 `cancel_pending_releases_freeze` |
| 116-4 | 撤单失败 | Toast「撤单失败：<原因>」，行状态不变 | `cancel_failed:<reason>` 分支 |
| 116-5 | 已成单再撤 | 幂等返回 `ok=false` + 当前状态，不报错 | 单测 `cancel_filled_is_rejected_idempotently` |

---

## 6. AC-117 持仓与可买

| # | 步骤 | 期望 | 证据 |
|---|---|---|---|
| 117-1 | 买入成交 | 现金扣减、持仓增加（加权成本） | 单测 `buy_cross_fills_and_books_cash` / `weighted_cost_on_second_buy` |
| 117-2 | 卖出成交 | 现金增加、持仓减少（清零则移除） | 单测 `sell_reduces_holding_and_adds_cash` |
| 117-3 | 挂单冻结 | 可买 = 现金 − 冻结；撤单/成交释放 | 单测 `freeze_reduces_available` / `cancel_pending_releases_freeze` |
| 117-4 | 成交后不轮询 | 回执驱动刷新（本地即时）；持仓页展示留 M11 | 代码 |
| 117-5 | 详情/弹窗「已持有」 | 待 M11 持仓页与详情联动 | **未做** |

---

## 7. AC-118 风控文案

| # | 项 | 状态 |
|---|---|---|
| 118-1 | 风控原因原样展示（不自造规则文案） | 🟡 拒单原因码 → 文案映射就位；`risk` 仅占位 |
| 118-2 | 首笔风险揭示 / 非投资建议 | ⬜ 待 M13 合规文案（法务口径） |
| 118-3 | 「模拟交易，不产生真实委托」常显 | ✅ 委托列表顶部常显 |

---

## 8. 已知缺口（本批次未完成）

| # | 缺口 | 说明 |
|---|---|---|
| 1 | **卖出入口 UI** | provider/撮合/记账已支持卖出并有单测；`TradeSheet` 仍只有买入 |
| 2 | 回执「查看委托」跳转 | 下单成功 Toast 有委托号，但未加跳转按钮 |
| 3 | 撤单真机点验 | ✅ 已补：限价 1500（低于现价）挂单 → 已报 → 撤单 → 已撤（见 §10） |
| 4 | 未开户引导真机截图 | ✅ 已补：委托页长按标题 → 模拟未开户 → 引导卡 → 开通模拟账户回列表 |
| 5 | 分页真机 | ✅ 已补：调试「生成测试委托 25 笔」→ 首屏 20 条 + 滚动到底自动加载余下 5 条（见 §10-6） |
| 6 | 首笔风险揭示 | 归 M13（合规文案） |

---

## 10. 剩余取证（2026-11-14，Mate 60 Pro）

| # | 场景 | 步骤 | 证据 |
|---|---|---|---|
| 10-1 | 挂单可撤 | 详情「去交易」→ 价格改 1500（低于现价）→ 买入 → 确认 → 已报（行尾「撤单」） | [06-order-pending-cancelable.png](../shots/phase2/m10/06-order-pending-cancelable.png) |
| 10-2 | 撤单二次确认 | 点「撤单」→ 弹窗「确认撤回这笔委托？撤单后不可恢复。」 | [07-cancel-confirm.png](../shots/phase2/m10/07-cancel-confirm.png) |
| 10-3 | 撤单回执 | 确认撤单 → 行状态就地变「已撤」、按钮消失、Toast「已撤单」 | [08-order-canceled.png](../shots/phase2/m10/08-order-canceled.png) |
| 10-4 | 未开户引导 | 委托页长按标题 → 调试菜单 → 模拟未开户 → 整页引导卡 | [09-no-account-guide.png](../shots/phase2/m10/09-no-account-guide.png) |
| 10-5 | 下拉刷新 | 列表下拉 → 重新加载第 0 页 | [10-pull-refresh.png](../shots/phase2/m10/10-pull-refresh.png) |
| 10-6 | 分页与 7 状态 | 调试「生成测试委托 25 笔」（只写委托、不记账）→ 首屏 20 条，滚动到底自动加载余下 5 条 | [11-orders-paging.png](../shots/phase2/m10/11-orders-paging.png)、[12-orders-load-more.png](../shots/phase2/m10/12-orders-load-more.png) |
| 10-7 | 状态筛选 | 点「废单」→ 只剩废单行，行内显示原因「可用资金不足」 | [13-orders-filter-rejected.png](../shots/phase2/m10/13-orders-filter-rejected.png) |

> 调试造数（`OrderListVM.debugSeedOrders(25)`）：循环覆盖 7 种状态（待报/已报/部成/已成/已撤/废单/未知），`clientOrderId` 以 `DBG` 前缀避免与真实下单撞键；**只写 `trade_orders_v1`，不动账户资金与持仓**；用「清空委托」清理。入口：委托页长按标题 → 生成测试委托 25 笔（`DEBUG` 关闭时不可用）。

> 撤单取证过程中发现并修复 1 个 P1 级缺陷：撤单成功后 `load()` 重建行对象，而 `ForEach` 以 `clientOrderId` 为 key 复用旧组件 → 界面卡在「撤单中」、按钮不再消失。改为**就地更新该行**（`state/cancelable/canceling`）后再取证。

---

## 9. 收尾补充（卖出 / 回执 / 调试入口）

| # | 项 | 实现 | 证据 |
|---|---|---|---|
| 9-1 | 买入/卖出分段 | `TradeEditView.sideSwitch()` + `TradeVM.setSide()`；切换后上限（可买/可卖）、默认数量、主按钮与确认页标题/按钮同步；无持仓时提示「无可卖持仓」 | [03-trade-sell-mode.png](../shots/phase2/m10/03-trade-sell-mode.png) |
| 9-2 | 卖出全链路 | 详情「去交易」→ 卖出 → 确认卖出 → 已有持仓 100 股 / 可卖 100 股 → 委托列表出现「卖出」行 | [05-orders-with-sell.png](../shots/phase2/m10/05-orders-with-sell.png) |
| 9-3 | 回执「查看委托」 | 下单成功弹结果框（委托号 + 查看委托/知道了），点「查看委托」直达委托列表；**不改** `TradePhase` 状态机 | [04-receipt-dialog.png](../shots/phase2/m10/04-receipt-dialog.png) |
| 9-4 | 委托页调试入口 | 长按标题 → 模拟未开户 / 恢复开户 / 重置账户与委托 / 清空委托（`DEBUG` 关闭时不可用） | 代码（待截图） |
| 9-5 | 卖出方向默认值 | 每次打开弹窗重置为「买入」，上次方向不残留（`TradeVM.reset()`） | 代码 + 真机复验 |
