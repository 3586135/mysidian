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
  @Event onSelectionChange: (active: boolean) => void = (_active: boolean): void => {};

  build() {
    Text() {
      ForEach(this.segments, (segment: MdInlineSegment, index: number) => {
        if (segment.linkKind.length > 0 || segment.tag.length > 0) {
          Span(segment.text)
            .fontSize(segment.code ? this.fontSize - 1 : this.fontSize)
            .fontWeight(segment.bold || this.forceBold ? FontWeight.Bold : FontWeight.Normal)
            .fontStyle(segment.italic ? FontStyle.Italic : FontStyle.Normal)
            .fontColor(this.segmentColor(segment))
            .fontFamily(segment.code ? 'monospace' : 'HarmonyOS Sans')
            .textBackgroundStyle(segment.highlight
              ? { color: $r('app.color.md_highlight_bg'), radius: 4 }
              : { color: Color.Transparent, radius: 0 })
            .decoration({
              type: segment.strike ? TextDecorationType.LineThrough : TextDecorationType.None,
              color: $r('app.color.md_text_primary')
            })
            .onClick(() => {
              this.handleClick(segment);
            })
        } else {
          Span(segment.text)
            .fontSize(segment.code ? this.fontSize - 1 : this.fontSize)
            .fontWeight(segment.bold || this.forceBold ? FontWeight.Bold : FontWeight.Normal)
            .fontStyle(segment.italic ? FontStyle.Italic : FontStyle.Normal)
            .fontColor(this.segmentColor(segment))
            .fontFamily(segment.code ? 'monospace' : 'HarmonyOS Sans')
            .textBackgroundStyle(segment.highlight
              ? { color: $r('app.color.md_highlight_bg'), radius: 4 }
              : { color: Color.Transparent, radius: 0 })
            .decoration({
              type: segment.strike ? TextDecorationType.LineThrough : TextDecorationType.None,
              color: $r('app.color.md_text_primary')
            })
        }
      }, (segment: MdInlineSegment, index: number): string => `${index}_${segment.text}`)
    }
    .width('100%')
    .fontSize(this.fontSize)
    .textAlign(this.textAlignment)
    .fontColor($r('app.color.md_text_primary'))
    .copyOption(CopyOptions.LocalDevice)
    .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
      this.onSelectionChange(selectionEnd > selectionStart);
    })
  }

  private segmentColor(segment: MdInlineSegment): ResourceColor {
    if (segment.linkKind.length > 0) {
      return $r('app.color.md_accent');
    }
    if (segment.tag.length > 0) {
      return $r('app.color.md_accent');
    }
    if (segment.code) {
      return $r('app.color.md_text_secondary');
    }
    return $r('app.color.md_text_primary');
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
