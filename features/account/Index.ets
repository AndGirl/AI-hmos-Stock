/**
 * 账户域（M11）：持仓与收益。
 * 对外唯一入口：跨模块只允许 import from 'account'（R-06）。
 * 约束：本模块只依赖 commons，不 import watchlist/detail/trade（持仓行点击与加自选均用 @Event 上抛）。
 */
export { PositionsView } from './src/main/ets/view/PositionsView';
export {
  PositionAddOutcome,
  PositionSortDir,
  PositionSortKey,
  PositionState,
  PositionVM
} from './src/main/ets/viewmodel/PositionVM';
export { PositionRowVM } from './src/main/ets/viewmodel/PositionRowVM';
