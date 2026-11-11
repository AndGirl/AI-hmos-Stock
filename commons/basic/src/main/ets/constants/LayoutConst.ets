/** 跨模块共享的布局常量（非视觉 token 的几何/时长值）。 */
export class LayoutConst {
  /** 悬浮底栏高度 */
  static readonly TAB_BAR_HEIGHT: number = 60;
  /** 页面底部为悬浮底栏预留的安全高度：底栏 + 下边距 + 呼吸位 */
  static readonly TAB_BAR_RESERVED: number = 96;
  /** 占位 toast 时长（附录 A：1.8s） */
  static readonly TOAST_DURATION_MS: number = 1800;
}
