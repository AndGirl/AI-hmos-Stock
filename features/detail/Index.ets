/**
 * 个股详情（M2 实现）。对外唯一入口：跨模块只允许 import from 'detail'（R-06）。
 */
export { DetailContent } from './src/main/ets/view/DetailContent';
export { showDetailActionMenu } from './src/main/ets/view/DetailActions';
export { DetailAction, DetailMode } from './src/main/ets/viewmodel/DetailVM';
