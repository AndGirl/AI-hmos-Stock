/**
 * 买入委托（M3 实现）。对外唯一入口：跨模块只允许 import from 'trade'（R-06）。
 */
export { TradeSheet } from './src/main/ets/view/TradeSheet';
export { TradeFaultKind, TradeVM } from './src/main/ets/viewmodel/TradeVM';
