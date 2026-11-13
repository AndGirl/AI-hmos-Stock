/**
 * 交易（M3 买入委托；M10 模拟交易：委托列表/撤单/开户引导）。
 * 对外唯一入口：跨模块只允许 import from 'trade'（R-06）。
 */
export { TradeSheet } from './src/main/ets/view/TradeSheet';
export { TradeFaultKind, TradeVM } from './src/main/ets/viewmodel/TradeVM';
export { OrdersView } from './src/main/ets/view/OrdersView';
export { OrderListVM, ORDER_FILTERS, ORDER_PAGE_SIZE, OrderRowVM } from './src/main/ets/viewmodel/OrderListVM';
