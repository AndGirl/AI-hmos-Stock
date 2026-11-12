import { PkCandidate, PkToastCode } from '../viewmodel/PkVM';

/** PK 文案映射（视图层唯一出口）：VM 只给 code，资源在这里组装（i18n 单一来源）。 */
export function pkToastText(code: PkToastCode | ''): ResourceStr {
  if (code === 'max_windows') {
    return $r('app.string.pk_toast_max');
  }
  if (code === 'already_open') {
    return $r('app.string.pk_toast_already');
  }
  if (code === 'swapped') {
    return $r('app.string.pk_toast_swapped');
  }
  if (code === 'degrade_throttle') {
    return $r('app.string.pk_toast_throttle');
  }
  if (code === 'degrade_close') {
    return $r('app.string.pk_toast_degrade_close');
  }
  if (code === 'restore_failed') {
    return $r('app.string.pk_toast_restore_failed');
  }
  if (code === 'restored') {
    return $r('app.string.pk_toast_restored');
  }
  if (code === 'sync_done') {
    return $r('app.string.pk_toast_sync_done');
  }
  if (code === 'single_window') {
    return $r('app.string.pk_toast_single');
  }
  return '';
}

/** 价格两位小数；空值 `--`（与详情/自选同口径）。 */
export function pkPriceText(value: number | null): string {
  if (value === null) {
    return '--';
  }
  return value.toFixed(2);
}

/** 涨跌幅带符号两位小数；空值 `--`。 */
export function pkPctText(value: number | null): string {
  if (value === null) {
    return '--';
  }
  const sign: string = value > 0 ? '+' : '';
  return sign + value.toFixed(2) + '%';
}

/** 候选行副标题：代码 + 最新价（名称与代码分行展示）。 */
export function candidateSubtitle(item: PkCandidate): string {
  return item.code + '  ' + pkPriceText(item.last);
}

/** 窗标题：窗序（1 起）。 */
export function windowLabel(index: number): string {
  return (index + 1).toString();
}
