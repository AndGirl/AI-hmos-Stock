/**
 * 多窗布局计算（设计 §5.5.2，纯函数、零中文）。
 * 约束（基线 C8）：所有窗 `x + width ≤ viewport`，关闭按钮不被裁切。
 */

export type PkLayoutKind = 'single' | 'split' | 'deck';

/** PK 上限 3 窗（DEC-08-02）。 */
export const PK_MAX_WINDOWS: number = 3;

/** 双窗中缝 8vp（露出浅灰底，不额外画线）。 */
export const PK_GAP: number = 8;

/** 三窗相邻重叠 12vp。 */
export const PK_DECK_OVERLAP: number = 12;

/** 窗宽 <360vp 切 FR-06.11 紧凑版。 */
export const PK_COMPACT_WIDTH: number = 360;

export class SlotLayout {
  index: number;
  x: number;
  width: number;
  zIndex: number;
  compact: boolean;

  constructor(index: number, x: number, width: number, zIndex: number, compact: boolean) {
    this.index = index;
    this.x = x;
    this.width = width;
    this.zIndex = zIndex;
    this.compact = compact;
  }
}

export function layoutKind(count: number): PkLayoutKind {
  if (count <= 1) {
    return 'single';
  }
  if (count === 2) {
    return 'split';
  }
  return 'deck';
}

/** 窗圆角：1/2 窗 14vp、3 窗 16vp（设计 §5.5.2）。 */
export function windowRadius(count: number): number {
  return count >= 3 ? 16 : 14;
}

/**
 * 计算窗位：1 窗铺满；2 窗左右 1:1 + 8vp 中缝；3 窗卡片叠放（重叠 12vp，焦点窗置顶）。
 * 三窗公式 `w = floor(viewport/3 + 6)` 与 `x = i*(w-12)` 保证整体不溢出。
 */
export function computeLayout(count: number, viewport: number): SlotLayout[] {
  // 下限保证三窗 `x = i*(w-12)` 不会落到负坐标（vp 极小只可能来自异常尺寸）。
  const safeViewport: number = Math.max(viewport > 0 ? viewport : 360, PK_MAX_WINDOWS * PK_DECK_OVERLAP);
  if (count <= 0) {
    return [];
  }
  if (count === 1) {
    return [new SlotLayout(0, 0, safeViewport, 0, safeViewport < PK_COMPACT_WIDTH)];
  }
  if (count === 2) {
    const w: number = Math.floor((safeViewport - PK_GAP) / 2);
    return [
      new SlotLayout(0, 0, w, 0, w < PK_COMPACT_WIDTH),
      new SlotLayout(1, w + PK_GAP, w, 0, w < PK_COMPACT_WIDTH)
    ];
  }
  const w: number = Math.floor(safeViewport / 3 + 6);
  const slots: SlotLayout[] = [];
  for (let i = 0; i < 3; i++) {
    slots.push(new SlotLayout(i, i * (w - PK_DECK_OVERLAP), w, i, w < PK_COMPACT_WIDTH));
  }
  return slots;
}

/**
 * 布局自检（debug 断言，设计 §5.5.2 的「x + width ≤ viewport 由单测断言」）。
 * 本项目无 UT 运行器，改由 debug 首次布局时打印违规项；正常返回空数组。
 */
export function layoutViolations(count: number, viewport: number): string[] {
  const slots: SlotLayout[] = computeLayout(count, viewport);
  const issues: string[] = [];
  if (slots.length !== count) {
    issues.push(`slot_count ${slots.length} != ${count}`);
  }
  for (let i = 0; i < slots.length; i++) {
    const slot: SlotLayout = slots[i];
    if (slot.x + slot.width > viewport + 0.5) {
      issues.push(`overflow i=${i} x=${slot.x} w=${slot.width} vp=${viewport}`);
    }
    if (slot.x < 0) {
      issues.push(`negative_x i=${i} x=${slot.x}`);
    }
    if (slot.width <= 0) {
      issues.push(`zero_width i=${i}`);
    }
  }
  if (count >= 2) {
    const last: SlotLayout = slots[slots.length - 1];
    if (last.x + last.width > viewport + 0.5) {
      issues.push(`last_edge overflow`);
    }
  }
  return issues;
}
