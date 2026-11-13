/**
 * 自选视图形态（M8-4）：列表 / 卡片。
 * 为什么放 commons_basic：`commons_data` 的 `ViewPrefStore`（落盘）与本层 `ConfigService`
 * （首帧预热）都要用它，而 `commons_data → commons_basic` 是允许方向，反向禁止（R-03）。
 */
export type ViewMode = 'list' | 'card';

export const VIEW_MODE_LIST: ViewMode = 'list';
export const VIEW_MODE_CARD: ViewMode = 'card';

/** 磁盘/入参值归一化：未知值一律退回列表（旧版本或损坏磁盘兜底）。 */
export function normalizeViewMode(value: string): ViewMode {
  return value === VIEW_MODE_CARD ? VIEW_MODE_CARD : VIEW_MODE_LIST;
}

/** 切换目标形态（列表 ↔ 卡片）。 */
export function nextViewMode(mode: ViewMode): ViewMode {
  return mode === VIEW_MODE_CARD ? VIEW_MODE_LIST : VIEW_MODE_CARD;
}
