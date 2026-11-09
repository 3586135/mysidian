import { MdInlineSegment } from '@ohos/domain';

/**
 * 行内内容渲染：把拍平后的片段渲染为带样式的 Span 序列。
 */
@ComponentV2
export struct MdInlineText {
  @Param segments: MdInlineSegment[] = [];
  @Param fontSize: number = 16;
  @Param textAlignment: TextAlign = TextAlign.Start;
  @Param forceBold: boolean = false;
  @Event onOpenLink: (target: string, kind: string) => void =
    (target: string, kind: string): void => {};
  @Event onOpenTag: (tag: string) => void = (tag: string): void => {};

  build() {
    Text() {
      ForEach(this.segments, (segment: MdInlineSegment, index: number) => {
        Span(segment.text)
          .fontSize(segment.code ? this.fontSize - 1 : this.fontSize)
          .fontWeight(segment.bold || this.forceBold ? FontWeight.Bold : FontWeight.Normal)
          .fontStyle(segment.italic ? FontStyle.Italic : FontStyle.Normal)
          .fontColor(this.segmentColor(segment))
          .fontFamily(segment.code ? 'monospace' : 'HarmonyOS Sans')
          .decoration({
            type: segment.strike ? TextDecorationType.LineThrough : TextDecorationType.None,
            color: $r('sys.color.ohos_id_color_text_primary')
          })
          .onClick(() => {
            this.handleClick(segment);
          })
      }, (segment: MdInlineSegment, index: number): string => `${index}_${segment.text}`)
    }
    .width('100%')
    .fontSize(this.fontSize)
    .textAlign(this.textAlignment)
    .fontColor($r('sys.color.ohos_id_color_text_primary'))
  }

  private segmentColor(segment: MdInlineSegment): ResourceColor {
    if (segment.linkKind.length > 0) {
      return $r('sys.color.ohos_id_color_emphasize');
    }
    if (segment.tag.length > 0) {
      return $r('sys.color.ohos_id_color_emphasize');
    }
    if (segment.code) {
      return $r('sys.color.ohos_id_color_text_secondary');
    }
    return $r('sys.color.ohos_id_color_text_primary');
  }

  private handleClick(segment: MdInlineSegment): void {
    if (segment.tag.length > 0) {
      this.onOpenTag(segment.tag);
      return;
    }
    if (segment.linkKind.length > 0) {
      this.onOpenLink(segment.linkTarget, segment.linkKind);
    }
  }
}
