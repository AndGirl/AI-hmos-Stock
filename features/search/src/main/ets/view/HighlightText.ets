import { AppColor } from 'commons_ui';
import { HitRange } from '../viewmodel/SearchVM';

/** 高亮片段：纯文本 + 是否命中。 */
class HighlightSegment {
  text: string;
  highlighted: boolean;

  constructor(text: string, highlighted: boolean) {
    this.text = text;
    this.highlighted = highlighted;
  }
}

/** 把半开区间落到文本上：区间合并 + 越界裁剪，输出不重叠片段。 */
function buildSegments(text: string, ranges: HitRange[]): HighlightSegment[] {
  const segments: HighlightSegment[] = [];
  if (text.length === 0) {
    return segments;
  }
  const starts: number[] = [];
  const ends: number[] = [];
  for (let i = 0; i < ranges.length; i++) {
    const start: number = Math.max(0, Math.min(ranges[i].start, text.length));
    const end: number = Math.max(start, Math.min(ranges[i].end, text.length));
    if (end > start) {
      starts.push(start);
      ends.push(end);
    }
  }
  // 按起点插入排序（区间很少，量级 ≤ 命中次数）。
  for (let i = 1; i < starts.length; i++) {
    let j: number = i;
    while (j > 0 && starts[j - 1] > starts[j]) {
      const tmpStart: number = starts[j - 1];
      starts[j - 1] = starts[j];
      starts[j] = tmpStart;
      const tmpEnd: number = ends[j - 1];
      ends[j - 1] = ends[j];
      ends[j] = tmpEnd;
      j--;
    }
  }
  let cursor: number = 0;
  for (let i = 0; i < starts.length; i++) {
    const start: number = Math.max(starts[i], cursor);
    if (start > cursor) {
      segments.push(new HighlightSegment(text.substring(cursor, start), false));
    }
    if (ends[i] > start) {
      segments.push(new HighlightSegment(text.substring(start, ends[i]), true));
      cursor = ends[i];
    }
  }
  if (cursor < text.length) {
    segments.push(new HighlightSegment(text.substring(cursor), false));
  }
  return segments;
}

/**
 * 命中高亮（M6-4 / FR-05.6）：
 * - 用 Text + Span 渲染，命中片段加粗 + accent 色；
 * - `copyOption(LocalDevice)` 保证长按复制拿到完整原文；
 * - `accessibilityText` 传完整原文，读屏不念高亮标记（AC-89）。
 */
@ComponentV2
export struct HighlightText {
  @Param text: string = '';
  @Param ranges: HitRange[] = [];
  @Param textSize: number = 16;
  @Param weight: FontWeight = FontWeight.Medium;
  @Param color: ResourceColor = AppColor.textPrimary;
  @Param maxLines: number = 1;
  @Param a11yText: string = '';

  private segments(): HighlightSegment[] {
    return buildSegments(this.text, this.ranges);
  }

  build() {
    Text() {
      ForEach(this.segments(), (segment: HighlightSegment, index: number) => {
        Span(segment.text)
          .fontSize(this.textSize)
          .fontWeight(segment.highlighted ? FontWeight.Bold : this.weight)
          .fontColor(segment.highlighted ? AppColor.accent : this.color)
      }, (segment: HighlightSegment, index: number) => `${index}-${segment.highlighted}-${segment.text.length}`)
    }
    .maxLines(this.maxLines)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
    .copyOption(CopyOptions.LocalDevice)
    .accessibilityText(this.a11yText.length > 0 ? this.a11yText : this.text)
  }
}
