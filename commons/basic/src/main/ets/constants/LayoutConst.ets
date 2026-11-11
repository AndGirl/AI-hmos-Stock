/** 跨模块共享的布局常量（非视觉 token 的几何/时长值）。 */
export class LayoutConst {
  /** 悬浮底栏高度 */
  static readonly TAB_BAR_HEIGHT: number = 60;
  /** 页面底部为悬浮底栏预留的安全高度：底栏 60 + 底边距 8 + 列表呼吸 24 */
  static readonly TAB_BAR_RESERVED: number = 92;
  /** 悬浮底栏与安全区之间的固定间距（设计 §5.1.2：avoidArea.bottom + 8vp） */
  static readonly TAB_BAR_BOTTOM_GAP: number = 8;
  /** 占位 toast 时长（附录 A：1.8s） */
  static readonly TOAST_DURATION_MS: number = 1800;
}
