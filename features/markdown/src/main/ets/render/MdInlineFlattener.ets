import { MdInline, MdInlineSegment, MdInlineType } from '@ohos/domain';
import { MathRenderer } from './MathRenderer';

/**
 * 把行内节点树拍平为带样式的片段列表。
 * ArkUI 的 Span 不支持嵌套，因此渲染前统一拍平。
 */
export class MdInlineFlattener {
  /** 拍平行内节点。 */
  public static flatten(inlines: MdInline[]): MdInlineSegment[] {
    const segments: MdInlineSegment[] = [];
    MdInlineFlattener.walk(inlines, false, false, false, segments);
    return segments;
  }

  private static walk(inlines: MdInline[], bold: boolean, italic: boolean, strike: boolean,
    output: MdInlineSegment[]): void {
    for (const inline of inlines) {
      if (inline.type === MdInlineType.STRONG) {
        MdInlineFlattener.walk(inline.children, true, italic, strike, output);
        continue;
      }
      if (inline.type === MdInlineType.EMPHASIS) {
        MdInlineFlattener.walk(inline.children, bold, true, strike, output);
        continue;
      }
      if (inline.type === MdInlineType.STRIKETHROUGH) {
        MdInlineFlattener.walk(inline.children, bold, italic, true, output);
        continue;
      }
      if (inline.type === MdInlineType.HIGHLIGHT) {
        const highlighted: MdInlineSegment[] = [];
        MdInlineFlattener.walk(inline.children, bold, italic, strike, highlighted);
        for (const item of highlighted) {
          item.highlight = true;
          output.push(item);
        }
        continue;
      }
      const segment: MdInlineSegment = new MdInlineSegment();
      segment.text = inline.type === MdInlineType.MATH
        ? MathRenderer.toPlain(inline.text) : inline.text;
      segment.bold = bold;
      segment.italic = italic;
      segment.strike = strike;
      segment.code = inline.type === MdInlineType.INLINE_CODE;
      if (inline.type === MdInlineType.LINK) {
        segment.linkTarget = inline.url;
        segment.linkKind = 'url';
      } else if (inline.type === MdInlineType.WIKI_LINK) {
        // 锚点拼回目标串：[[笔记#标题]] → linkTarget = "笔记#标题"，
        // 由上层拆分解析，渲染层的事件签名保持不变。
        segment.linkTarget = inline.heading.length > 0
          ? `${inline.target}#${inline.heading}` : inline.target;
        segment.linkKind = 'wiki';
      } else if (inline.type === MdInlineType.EMBED) {
        segment.linkTarget = inline.target;
        segment.linkKind = 'embed';
      } else if (inline.type === MdInlineType.TAG) {
        segment.tag = inline.text;
      }
      output.push(segment);
    }
  }
}
