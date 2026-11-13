/** 跨模块共享的布局常量（非视觉 token 的几何/时长值）。 */
export class LayoutConst {
  /** 底部导航栏内容区高度（不含底部安全区，安全区由底栏 padding 吃掉） */
  static readonly TAB_BAR_HEIGHT: number = 60;
  /** 宽屏下四 Tab 内容区最大宽度，超出居中，避免平板把四项拉满整宽 */
  static readonly TAB_BAR_CONTENT_MAX_WIDTH: number = 640;
  /** 占位 toast 时长（附录 A：1.8s） */
  static readonly TOAST_DURATION_MS: number = 1800;
}
