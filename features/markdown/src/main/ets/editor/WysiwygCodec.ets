import { MdInline, MdInlineType } from '@ohos/domain';
import { InlineParser } from '../parser/InlineParser';
import {
  WysiwygBlockKind,
  WysiwygDocument,
  WysiwygInline,
  WysiwygParagraph,
  WysiwygSpanKind
} from './WysiwygModel';
import { WysiwygTableCodec } from './WysiwygTableCodec';
import { WysiwygTriggers } from './WysiwygTriggers';

/**
 * Markdown <-> WysiwygDocument 双向无损编解码器。
 * 保留 YAML Frontmatter、Dataview/Mermaid 代码块、Callout、任务元数据、图片与双链别名。
 */
export class WysiwygCodec {
  private static readonly INLINE_PARSER: InlineParser = new InlineParser();
  private static nextGroupId: number = 1;

  /** 把原始 Markdown 文本解析为 WYSIWYG 段落模型。 */
  public static parse(markdown: string): WysiwygDocument {
    const doc: WysiwygDocument = new WysiwygDocument();
    const normalized: string = markdown.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    const lines: string[] = normalized.split('\n');

    let bodyStart: number = 0;
    if (lines.length > 0 && lines[0].trim() === '---') {
      let fmEnd: number = -1;
      for (let i: number = 1; i < lines.length; i++) {
        if (lines[i].trim() === '---') {
          fmEnd = i;
          break;
        }
      }
      if (fmEnd > 0) {
        doc.hasFrontmatter = true;
        doc.frontmatterRaw = lines.slice(1, fmEnd).join('\n');
        bodyStart = fmEnd + 1;
        if (bodyStart < lines.length && lines[bodyStart].trim().length === 0) {
          doc.frontmatterBlankAfter = true;
          bodyStart++;
        } else {
          doc.frontmatterBlankAfter = false;
        }
      }
    }

    const bodyLines: string[] = lines.slice(bodyStart);
    WysiwygCodec.parseBodyLines(bodyLines, doc);
    if (doc.paragraphs.length === 0) {
      doc.paragraphs.push(new WysiwygParagraph());
    }
    return doc;
  }

  /** 把 WYSIWYG 模型序列化回标准 Markdown 文本。 */
  public static serialize(doc: WysiwygDocument): string {
    const parts: string[] = [];
    if (doc.hasFrontmatter || doc.frontmatterRaw.trim().length > 0) {
      parts.push(`---\n${doc.frontmatterRaw}\n---`);
    }

    const bodyStr: string = WysiwygCodec.serializeParagraphs(doc.paragraphs);
    if (parts.length === 0) {
      return bodyStr;
    }
    if (bodyStr.length === 0) {
      return doc.frontmatterBlankAfter ? `${parts[0]}\n` : parts[0];
    }
    const fmGap: string = doc.frontmatterBlankAfter ? '\n\n' : '\n';
    return `${parts[0]}${fmGap}${bodyStr}`;
  }

  /** 仅序列化正文段落序列（不含 Frontmatter）。 */
  public static serializeParagraphs(paragraphs: WysiwygParagraph[]): string {
    if (paragraphs.length === 0) {
      return '';
    }
    const chunks: string[] = [];
    let i: number = 0;
    while (i < paragraphs.length) {
      const p: WysiwygParagraph = paragraphs[i];
      if (p.kind === WysiwygBlockKind.CODE) {
        const end: number = WysiwygCodec.collectSameKindRun(paragraphs, i, WysiwygBlockKind.CODE);
        const codeLines: string[] = [];
        for (let k: number = i; k < end; k++) {
          codeLines.push(WysiwygCodec.plainParagraphText(paragraphs[k]));
        }
        chunks.push(`\`\`\`${p.lang}\n${codeLines.join('\n')}\n\`\`\``);
        chunks.push(paragraphs[end - 1].tightBreakAfter ? '\n' : '\n\n');
        i = end;
        continue;
      }
      if (p.kind === WysiwygBlockKind.MATH) {
        const end: number = WysiwygCodec.collectSameKindRun(paragraphs, i, WysiwygBlockKind.MATH);
        const mathLines: string[] = [];
        for (let k: number = i; k < end; k++) {
          mathLines.push(WysiwygCodec.plainParagraphText(paragraphs[k]));
        }
        chunks.push(`$$\n${mathLines.join('\n')}\n$$`);
        chunks.push(paragraphs[end - 1].tightBreakAfter ? '\n' : '\n\n');
        i = end;
        continue;
      }
      if (p.kind === WysiwygBlockKind.HTML) {
        const end: number = WysiwygCodec.collectSameKindRun(paragraphs, i, p.kind);
        const lines: string[] = [];
        for (let k: number = i; k < end; k++) {
          lines.push(WysiwygCodec.plainParagraphText(paragraphs[k]));
        }
        chunks.push(lines.join('\n'));
        chunks.push(paragraphs[end - 1].tightBreakAfter ? '\n' : '\n\n');
        i = end;
        continue;
      }
      if (WysiwygCodec.isListKind(p.kind)) {
        const lines: string[] = [];
        let end: number = i;
        while (end < paragraphs.length && WysiwygCodec.isListKind(paragraphs[end].kind)) {
          lines.push(WysiwygCodec.serializeListLine(paragraphs[end]));
          end++;
        }
        chunks.push(lines.join('\n'));
        chunks.push(paragraphs[end - 1].tightBreakAfter ? '\n' : '\n\n');
        i = end;
        continue;
      }
      if (p.kind === WysiwygBlockKind.QUOTE || p.kind === WysiwygBlockKind.CALLOUT) {
        const kind: WysiwygBlockKind = p.kind;
        const lines: string[] = [];
        let end: number = i;
        while (end < paragraphs.length && paragraphs[end].kind === kind) {
          lines.push(WysiwygCodec.serializeQuoteOrCalloutLine(paragraphs[end], end === i));
          end++;
        }
        chunks.push(lines.join('\n'));
        chunks.push(paragraphs[end - 1].tightBreakAfter ? '\n' : '\n\n');
        i = end;
        continue;
      }
      chunks.push(WysiwygCodec.serializeSingleBlock(p));
      chunks.push(p.tightBreakAfter ? '\n' : '\n\n');
      i++;
    }

    if (chunks.length > 0) {
      chunks.pop();
    }
    return chunks.join('');
  }

  /** 把一段 Markdown 行内源码解析为 WysiwygInline 数组。 */
  public static parseInlines(text: string): WysiwygInline[] {
    if (text.length === 0) {
      return [];
    }
    const mdInlines: MdInline[] = WysiwygCodec.INLINE_PARSER.parse(text);
    const out: WysiwygInline[] = [];
    WysiwygCodec.walkMdInlines(mdInlines, false, false, false, false, out);
    return out;
  }

  /** 把 WysiwygInline 数组无损序列化回 Markdown 行内文本。 */
  public static serializeInlines(inlines: WysiwygInline[]): string {
    let out: string = '';
    let i: number = 0;
    while (i < inlines.length) {
      const cur: WysiwygInline = inlines[i];
      if (cur.isImage) {
        out += WysiwygCodec.serializeImageInline(cur);
        i++;
        continue;
      }
      if (cur.kind !== WysiwygSpanKind.PLAIN || cur.code) {
        out += WysiwygCodec.serializeSpecialInline(cur);
        i++;
        continue;
      }
      // 合并相邻具有相同加粗/斜体/删除线/高亮样式的普通片段，避免输出 **a****b**。
      let text: string = cur.text;
      let j: number = i + 1;
      while (j < inlines.length && WysiwygCodec.canMergePlainStyle(cur, inlines[j])) {
        text += inlines[j].text;
        j++;
      }
      out += WysiwygCodec.wrapInlineStyle(text, cur.bold, cur.italic, cur.strike, cur.highlight);
      i = j;
    }
    return out;
  }

  /** 把目标文字的可见文本长度计为 WYSIWYG 字符偏移。 */
  public static wysiwygParagraphPlainText(p: WysiwygParagraph): string {
    let text: string = '';
    for (const inline of p.inlines) {
      text += inline.isImage ? ' ' : inline.text;
    }
    return text;
  }

  /**
   * 由 WYSIWYG 段落序号及段内可见列偏移映射回完整 Markdown 源码中的字符偏移。
   * 用于「所见 -> 源码」切换时保持光标在同一行/同一词附近。
   */
  public static sourceOffsetFromWysiwyg(doc: WysiwygDocument, paraIdx: number, colInPara: number): number {
    let prefixOffset: number = 0;
    if (doc.hasFrontmatter || doc.frontmatterRaw.trim().length > 0) {
      const fmHeader: string = `---\n${doc.frontmatterRaw}\n---`;
      const fmGap: string = doc.frontmatterBlankAfter ? '\n\n' : '\n';
      prefixOffset = fmHeader.length + fmGap.length;
    }
    const paragraphs: WysiwygParagraph[] = doc.paragraphs;
    if (paragraphs.length === 0) {
      return prefixOffset;
    }
    const clampedIdx: number = Math.max(0, Math.min(paragraphs.length - 1, paraIdx));
    let offset: number = prefixOffset;
    let i: number = 0;
    while (i < clampedIdx) {
      const p: WysiwygParagraph = paragraphs[i];
      if (p.kind === WysiwygBlockKind.CODE) {
        const end: number = WysiwygCodec.collectSameKindRun(paragraphs, i, WysiwygBlockKind.CODE);
        if (clampedIdx < end) {
          offset += `\`\`\`${p.lang}\n`.length;
          for (let k: number = i; k < clampedIdx; k++) {
            offset += WysiwygCodec.plainParagraphText(paragraphs[k]).length + 1;
          }
          return offset + Math.max(0, colInPara);
        }
        const codeLines: string[] = [];
        for (let k: number = i; k < end; k++) {
          codeLines.push(WysiwygCodec.plainParagraphText(paragraphs[k]));
        }
        const blockStr: string = `\`\`\`${p.lang}\n${codeLines.join('\n')}\n\`\`\``;
        offset += blockStr.length + (paragraphs[end - 1].tightBreakAfter ? 1 : 2);
        i = end;
        continue;
      }
      if (p.kind === WysiwygBlockKind.MATH) {
        const end: number = WysiwygCodec.collectSameKindRun(paragraphs, i, WysiwygBlockKind.MATH);
        if (clampedIdx < end) {
          offset += 3;
          for (let k: number = i; k < clampedIdx; k++) {
            offset += WysiwygCodec.plainParagraphText(paragraphs[k]).length + 1;
          }
          return offset + Math.max(0, colInPara);
        }
        const mathLines: string[] = [];
        for (let k: number = i; k < end; k++) {
          mathLines.push(WysiwygCodec.plainParagraphText(paragraphs[k]));
        }
        offset += `$$\n${mathLines.join('\n')}\n$$`.length + (paragraphs[end - 1].tightBreakAfter ? 1 : 2);
        i = end;
        continue;
      }
      if (p.kind === WysiwygBlockKind.HTML) {
        const end: number = WysiwygCodec.collectSameKindRun(paragraphs, i, p.kind);
        if (clampedIdx < end) {
          for (let k: number = i; k < clampedIdx; k++) {
            offset += WysiwygCodec.plainParagraphText(paragraphs[k]).length + 1;
          }
          return offset + Math.max(0, colInPara);
        }
        const lines: string[] = [];
        for (let k: number = i; k < end; k++) {
          lines.push(WysiwygCodec.plainParagraphText(paragraphs[k]));
        }
        offset += lines.join('\n').length + (paragraphs[end - 1].tightBreakAfter ? 1 : 2);
        i = end;
        continue;
      }
      if (WysiwygCodec.isListKind(p.kind)) {
        const lineStr: string = WysiwygCodec.serializeListLine(p);
        const nextIsList: boolean = i + 1 < paragraphs.length && WysiwygCodec.isListKind(paragraphs[i + 1].kind);
        offset += lineStr.length + (nextIsList ? 1 : (p.tightBreakAfter ? 1 : 2));
        i++;
        continue;
      }
      if (p.kind === WysiwygBlockKind.QUOTE || p.kind === WysiwygBlockKind.CALLOUT) {
        const sameNext: boolean = i + 1 < paragraphs.length && paragraphs[i + 1].kind === p.kind;
        const isFirst: boolean = i === 0 || paragraphs[i - 1].kind !== p.kind;
        const lineStr: string = WysiwygCodec.serializeQuoteOrCalloutLine(p, isFirst);
        offset += lineStr.length + (sameNext ? 1 : (p.tightBreakAfter ? 1 : 2));
        i++;
        continue;
      }
      offset += WysiwygCodec.serializeSingleBlock(p).length + (p.tightBreakAfter ? 1 : 2);
      i++;
    }

    const target: WysiwygParagraph = paragraphs[clampedIdx];
    const isHeaderQuote: boolean = clampedIdx === 0 || paragraphs[clampedIdx - 1].kind !== target.kind;
    offset += WysiwygCodec.blockPrefixLengthInSource(target, isHeaderQuote);
    offset += WysiwygCodec.inlineSourceOffset(target.inlines, Math.max(0, colInPara));
    return offset;
  }

  /**
   * 由完整 Markdown 源码字符偏移映射回 WYSIWYG RichEditor 字符偏移。
   * 用于「源码 -> 所见」切换时保持光标位置一致。
   */
  public static wysiwygOffsetFromSource(markdown: string, sourceCaret: number): number {
    const doc: WysiwygDocument = WysiwygCodec.parse(markdown);
    if (doc.paragraphs.length === 0) {
      return 0;
    }
    const clampedSrc: number = Math.max(0, Math.min(markdown.length, sourceCaret));
    let bestPara: number = 0;
    let bestParaSrcStart: number = 0;
    for (let i: number = 0; i < doc.paragraphs.length; i++) {
      const pSrcStart: number = WysiwygCodec.sourceOffsetFromWysiwyg(doc, i, 0);
      const lineStartOffset: number = pSrcStart - WysiwygCodec.blockPrefixLengthInSource(
        doc.paragraphs[i], i === 0 || doc.paragraphs[i - 1].kind !== doc.paragraphs[i].kind);
      if (lineStartOffset <= clampedSrc) {
        bestPara = i;
        bestParaSrcStart = pSrcStart;
      } else {
        break;
      }
    }
    let wysiwygStart: number = 0;
    for (let i: number = 0; i < bestPara; i++) {
      wysiwygStart += WysiwygCodec.wysiwygParagraphPlainText(doc.paragraphs[i]).length + 1;
    }
    const p: WysiwygParagraph = doc.paragraphs[bestPara];
    if (clampedSrc <= bestParaSrcStart) {
      return wysiwygStart;
    }
    const colInPara: number = WysiwygCodec.inlineWysiwygOffset(p.inlines, clampedSrc - bestParaSrcStart);
    return wysiwygStart + colInPara;
  }

  private static blockPrefixLengthInSource(p: WysiwygParagraph, isHeaderQuote: boolean): number {
    if (p.kind === WysiwygBlockKind.HEADING) {
      return Math.min(6, Math.max(1, p.level)) + 1;
    }
    if (p.kind === WysiwygBlockKind.BULLET) {
      return Math.max(0, p.indent) * 2 + p.bulletChar.length + 1;
    }
    if (p.kind === WysiwygBlockKind.ORDERED) {
      return Math.max(0, p.indent) * 2 + `${p.ordinal}${p.orderedDelimiter} `.length;
    }
    if (p.kind === WysiwygBlockKind.TASK) {
      return Math.max(0, p.indent) * 2 + p.bulletChar.length + 5;
    }
    if (p.kind === WysiwygBlockKind.QUOTE) {
      return 2;
    }
    if (p.kind === WysiwygBlockKind.CALLOUT) {
      if (isHeaderQuote && p.calloutType.length > 0) {
        const fold: number = p.calloutHasFoldMarker ? 1 : 0;
        return 2 + `[!${p.calloutType}]`.length + fold + (p.inlines.length > 0 ? 1 : 0);
      }
      return 2;
    }
    return 0;
  }

  private static inlineSourceOffset(inlines: WysiwygInline[], targetCol: number): number {
    let visLeft: number = targetCol;
    let srcAcc: number = 0;
    let i: number = 0;
    while (i < inlines.length) {
      if (visLeft <= 0) {
        return srcAcc;
      }
      const cur: WysiwygInline = inlines[i];
      if (cur.isImage || cur.kind !== WysiwygSpanKind.PLAIN || cur.code) {
        const visLen: number = cur.isImage ? 1 : cur.text.length;
        const serialized: string = cur.isImage ? WysiwygCodec.serializeImageInline(cur)
          : WysiwygCodec.serializeSpecialInline(cur);
        if (visLeft >= visLen) {
          srcAcc += serialized.length;
          visLeft -= visLen;
          i++;
          continue;
        }
        const openPad: number = Math.max(0, Math.floor((serialized.length - visLen) / 2));
        return srcAcc + Math.min(serialized.length, openPad + visLeft);
      }
      let mergedText: string = cur.text;
      let j: number = i + 1;
      while (j < inlines.length && WysiwygCodec.canMergePlainStyle(cur, inlines[j])) {
        mergedText += inlines[j].text;
        j++;
      }
      const serialized: string = WysiwygCodec.wrapInlineStyle(
        mergedText, cur.bold, cur.italic, cur.strike, cur.highlight);
      if (visLeft >= mergedText.length) {
        srcAcc += serialized.length;
        visLeft -= mergedText.length;
        i = j;
        continue;
      }
      const openPad: number = Math.max(0, Math.floor((serialized.length - mergedText.length) / 2));
      return srcAcc + Math.min(serialized.length, openPad + visLeft);
    }
    return srcAcc;
  }

  private static inlineWysiwygOffset(inlines: WysiwygInline[], targetSrcCol: number): number {
    let srcLeft: number = targetSrcCol;
    let visAcc: number = 0;
    let i: number = 0;
    while (i < inlines.length) {
      if (srcLeft <= 0) {
        return visAcc;
      }
      const cur: WysiwygInline = inlines[i];
      if (cur.isImage || cur.kind !== WysiwygSpanKind.PLAIN || cur.code) {
        const visLen: number = cur.isImage ? 1 : cur.text.length;
        const serialized: string = cur.isImage ? WysiwygCodec.serializeImageInline(cur)
          : WysiwygCodec.serializeSpecialInline(cur);
        if (srcLeft >= serialized.length) {
          srcLeft -= serialized.length;
          visAcc += visLen;
          i++;
          continue;
        }
        const openPad: number = Math.max(0, Math.floor((serialized.length - visLen) / 2));
        return visAcc + Math.max(0, Math.min(visLen, srcLeft - openPad));
      }
      let mergedText: string = cur.text;
      let j: number = i + 1;
      while (j < inlines.length && WysiwygCodec.canMergePlainStyle(cur, inlines[j])) {
        mergedText += inlines[j].text;
        j++;
      }
      const serialized: string = WysiwygCodec.wrapInlineStyle(
        mergedText, cur.bold, cur.italic, cur.strike, cur.highlight);
      if (srcLeft >= serialized.length) {
        srcLeft -= serialized.length;
        visAcc += mergedText.length;
        i = j;
        continue;
      }
      const openPad: number = Math.max(0, Math.floor((serialized.length - mergedText.length) / 2));
      return visAcc + Math.max(0, Math.min(mergedText.length, srcLeft - openPad));
    }
    return visAcc;
  }

  /** 按编辑后的展示文本更新 [[target|alias]] 内部字符串。 */
  public static updatedWikiInner(rawInner: string, editedDisplay: string): string {
    const clean: string = editedDisplay.trim();
    if (clean.length === 0) {
      return rawInner;
    }
    const pipe: number = rawInner.indexOf('|');
    if (pipe >= 0) {
      return `${rawInner.substring(0, pipe)}|${clean}`;
    }
    return clean;
  }

  /** 判断目标扩展名是否为图片资源。 */
  public static isImageTarget(target: string): boolean {
    const lower: string = target.toLowerCase();
    const dot: number = lower.lastIndexOf('.');
    if (dot < 0) {
      return false;
    }
    const ext: string = lower.substring(dot + 1);
    return ext === 'png' || ext === 'jpg' || ext === 'jpeg' || ext === 'gif' ||
      ext === 'webp' || ext === 'bmp' || ext === 'svg';
  }

  private static parseBodyLines(lines: string[], doc: WysiwygDocument): void {
    let i: number = 0;
    while (i < lines.length) {
      const raw: string = lines[i];
      const trimmed: string = raw.trim();

      if (trimmed.length === 0) {
        // 连续空行（2 行及以上）保留显式空段落；单空行视为标准块间距。
        let blankRun: number = 1;
        while (i + blankRun < lines.length && lines[i + blankRun].trim().length === 0) {
          blankRun++;
        }
        if (i === 0 && blankRun >= 1) {
          for (let b: number = 0; b < blankRun; b++) {
            doc.paragraphs.push(new WysiwygParagraph());
          }
        } else {
          for (let b: number = 1; b < blankRun; b++) {
            doc.paragraphs.push(new WysiwygParagraph());
          }
        }
        i += blankRun;
        continue;
      }

      if (WysiwygCodec.isFence(trimmed)) {
        i = WysiwygCodec.consumeCodeBlock(lines, i, doc);
        continue;
      }

      if (trimmed.startsWith('$$')) {
        i = WysiwygCodec.consumeMathBlock(lines, i, doc);
        continue;
      }

      const wikiMedia: RegExpExecArray | null = /^!\[\[([^\]]+)\]\]$/.exec(trimmed);
      if (wikiMedia !== null) {
        WysiwygCodec.pushWikiMediaBlock(wikiMedia[1], doc, WysiwygCodec.hasTightNext(lines, i));
        i++;
        continue;
      }

      const mdImage: RegExpExecArray | null = /^!\[([^\]]*)\]\(([^)]+)\)$/.exec(trimmed);
      if (mdImage !== null) {
        WysiwygCodec.pushMdImageBlock(mdImage[1], mdImage[2], doc, WysiwygCodec.hasTightNext(lines, i));
        i++;
        continue;
      }

      const heading: RegExpExecArray | null = /^(#{1,6})\s+(.*)$/.exec(trimmed);
      if (heading !== null) {
        const p: WysiwygParagraph = new WysiwygParagraph();
        p.kind = WysiwygBlockKind.HEADING;
        p.level = heading[1].length;
        p.inlines = WysiwygCodec.parseInlines(heading[2].trimEnd());
        p.tightBreakAfter = WysiwygCodec.hasTightNext(lines, i);
        doc.paragraphs.push(p);
        i++;
        continue;
      }

      if (WysiwygCodec.isThematicBreak(trimmed)) {
        const p: WysiwygParagraph = new WysiwygParagraph();
        p.kind = WysiwygBlockKind.HR;
        p.inlines = [WysiwygInline.plain(WysiwygTriggers.HR_DISPLAY)];
        p.tightBreakAfter = WysiwygCodec.hasTightNext(lines, i);
        doc.paragraphs.push(p);
        i++;
        continue;
      }

      if (trimmed.startsWith('>')) {
        i = WysiwygCodec.consumeQuoteOrCallout(lines, i, doc);
        continue;
      }

      const listPara: WysiwygParagraph | null = WysiwygCodec.tryParseListLine(raw);
      if (listPara !== null) {
        doc.paragraphs.push(listPara);
        while (i + 1 < lines.length && WysiwygCodec.tryParseListLine(lines[i + 1]) !== null) {
          i++;
          const nextList: WysiwygParagraph | null = WysiwygCodec.tryParseListLine(lines[i]);
          if (nextList !== null) {
            doc.paragraphs.push(nextList);
          }
        }
        doc.paragraphs[doc.paragraphs.length - 1].tightBreakAfter = WysiwygCodec.hasTightNext(lines, i);
        i++;
        continue;
      }

      if (trimmed.includes('|') && i + 1 < lines.length && WysiwygCodec.isTableDelimiter(lines[i + 1].trim())) {
        i = WysiwygCodec.consumeTable(lines, i, doc);
        continue;
      }

      if (trimmed.startsWith('<') && (/^<\/?[A-Za-z]/.test(trimmed) || trimmed.startsWith('<!--') ||
        /^<!DOCTYPE/i.test(trimmed))) {
        i = WysiwygCodec.consumeHtml(lines, i, doc);
        continue;
      }

      // Setext H1/H2（下一行 === 或 ---）。
      if (i + 1 < lines.length && (lines[i + 1].trim() === '===' || lines[i + 1].trim() === '---')) {
        const p: WysiwygParagraph = new WysiwygParagraph();
        p.kind = WysiwygBlockKind.HEADING;
        p.level = lines[i + 1].trim() === '===' ? 1 : 2;
        p.inlines = WysiwygCodec.parseInlines(raw.trim());
        p.tightBreakAfter = WysiwygCodec.hasTightNext(lines, i + 1);
        doc.paragraphs.push(p);
        i += 2;
        continue;
      }

      const para: WysiwygParagraph = new WysiwygParagraph();
      para.kind = WysiwygBlockKind.PARAGRAPH;
      para.inlines = WysiwygCodec.parseInlines(raw);
      para.tightBreakAfter = WysiwygCodec.hasTightNext(lines, i);
      doc.paragraphs.push(para);
      i++;
    }
  }

  private static hasTightNext(lines: string[], index: number): boolean {
    return index + 1 < lines.length && lines[index + 1].trim().length > 0;
  }

  private static isFence(trimmed: string): boolean {
    return trimmed.startsWith('```') || trimmed.startsWith('~~~');
  }

  private static consumeCodeBlock(lines: string[], start: number, doc: WysiwygDocument): number {
    const fenceLine: string = lines[start].trim();
    const fenceChar: string = fenceLine.charAt(0);
    let len: number = 0;
    while (len < fenceLine.length && fenceLine.charAt(len) === fenceChar) {
      len++;
    }
    const lang: string = fenceLine.substring(len).trim();
    const body: string[] = [];
    let i: number = start + 1;
    while (i < lines.length) {
      const cur: string = lines[i].trim();
      if (cur.startsWith(fenceChar) && cur.length >= len && cur.split(fenceChar).join('').length === 0) {
        i++;
        break;
      }
      body.push(lines[i]);
      i++;
    }
    if (body.length === 0) {
      body.push('');
    }
    const groupId: number = WysiwygCodec.nextGroupId++;
    for (let k: number = 0; k < body.length; k++) {
      const p: WysiwygParagraph = new WysiwygParagraph();
      p.kind = WysiwygBlockKind.CODE;
      p.lang = lang;
      p.blockGroupId = groupId;
      if (body[k].length > 0) {
        p.inlines = [WysiwygInline.plain(body[k])];
      }
      if (k === body.length - 1) {
        p.tightBreakAfter = i < lines.length && lines[i].trim().length > 0;
      }
      doc.paragraphs.push(p);
    }
    return i;
  }

  private static consumeMathBlock(lines: string[], start: number, doc: WysiwygDocument): number {
    const first: string = lines[start].trim();
    const body: string[] = [];
    let i: number = start + 1;
    if (first.length > 2 && first.endsWith('$$')) {
      body.push(first.substring(2, first.length - 2).trim());
    } else {
      while (i < lines.length) {
        const cur: string = lines[i].trim();
        if (cur.endsWith('$$')) {
          const tail: string = cur.substring(0, cur.length - 2).trim();
          if (tail.length > 0) {
            body.push(tail);
          }
          i++;
          break;
        }
        body.push(lines[i]);
        i++;
      }
    }
    if (body.length === 0) {
      body.push('');
    }
    const groupId: number = WysiwygCodec.nextGroupId++;
    for (let k: number = 0; k < body.length; k++) {
      const p: WysiwygParagraph = new WysiwygParagraph();
      p.kind = WysiwygBlockKind.MATH;
      p.blockGroupId = groupId;
      if (body[k].length > 0) {
        p.inlines = [WysiwygInline.plain(body[k])];
      }
      if (k === body.length - 1) {
        p.tightBreakAfter = i < lines.length && lines[i].trim().length > 0;
      }
      doc.paragraphs.push(p);
    }
    return i;
  }

  private static pushWikiMediaBlock(inner: string, doc: WysiwygDocument, tightAfter: boolean): void {
    const pipe: number = inner.indexOf('|');
    const target: string = (pipe >= 0 ? inner.substring(0, pipe) : inner).trim();
    const alias: string = (pipe >= 0 ? inner.substring(pipe + 1) : '').trim();
    if (!WysiwygCodec.isImageTarget(target)) {
      const embed: WysiwygParagraph = new WysiwygParagraph();
      embed.kind = WysiwygBlockKind.EMBED;
      embed.inlines = [WysiwygInline.plain(`![[${inner}]]`)];
      embed.tightBreakAfter = tightAfter;
      doc.paragraphs.push(embed);
      return;
    }
    const imgPara: WysiwygParagraph = new WysiwygParagraph();
    imgPara.kind = WysiwygBlockKind.IMAGE;
    const inline: WysiwygInline = new WysiwygInline();
    inline.isImage = true;
    inline.imageTarget = target;
    inline.imageRawMd = `![[${inner}]]`;
    const width: number = Number(alias);
    if (alias.length > 0 && !Number.isNaN(width) && width > 0) {
      inline.imageWidth = width;
    } else {
      inline.imageAlt = alias;
    }
    imgPara.inlines = [inline];
    imgPara.tightBreakAfter = tightAfter;
    doc.paragraphs.push(imgPara);
  }

  private static pushMdImageBlock(alt: string, url: string, doc: WysiwygDocument, tightAfter: boolean): void {
    const imgPara: WysiwygParagraph = new WysiwygParagraph();
    imgPara.kind = WysiwygBlockKind.IMAGE;
    const inline: WysiwygInline = new WysiwygInline();
    inline.isImage = true;
    inline.imageTarget = url.trim();
    inline.imageAlt = alt;
    inline.imageRawMd = `![${alt}](${url})`;
    imgPara.inlines = [inline];
    imgPara.tightBreakAfter = tightAfter;
    doc.paragraphs.push(imgPara);
  }

  private static consumeQuoteOrCallout(lines: string[], start: number, doc: WysiwygDocument): number {
    const body: string[] = [];
    let i: number = start;
    while (i < lines.length && lines[i].trim().startsWith('>')) {
      const stripped: string = lines[i].trim().substring(1);
      body.push(stripped.startsWith(' ') ? stripped.substring(1) : stripped.trimStart());
      i++;
    }
    const first: string = body.length > 0 ? body[0] : '';
    const callout: RegExpExecArray | null = /^\[!([A-Za-z]+)\]([+-]?)\s*(.*)$/.exec(first);
    const isCallout: boolean = callout !== null;
    const groupId: number = WysiwygCodec.nextGroupId++;
    for (let k: number = 0; k < body.length; k++) {
      const p: WysiwygParagraph = new WysiwygParagraph();
      p.kind = isCallout ? WysiwygBlockKind.CALLOUT : WysiwygBlockKind.QUOTE;
      p.blockGroupId = groupId;
      if (isCallout && callout !== null) {
        p.calloutType = callout[1].toUpperCase();
        p.calloutHasFoldMarker = callout[2].length > 0;
        p.calloutFolded = callout[2] === '-';
        if (k === 0) {
          const title: string = callout[3].trim();
          p.inlines = title.length > 0 ? WysiwygCodec.parseInlines(title) : [];
        } else {
          p.inlines = WysiwygCodec.parseInlines(body[k]);
        }
      } else {
        p.inlines = WysiwygCodec.parseInlines(body[k]);
      }
      if (k === body.length - 1) {
        p.tightBreakAfter = i < lines.length && lines[i].trim().length > 0;
      }
      doc.paragraphs.push(p);
    }
    return i;
  }

  private static tryParseListLine(raw: string): WysiwygParagraph | null {
    const indentMatch: RegExpExecArray | null = /^([ \t]*)(.*)$/.exec(raw);
    const spaces: number = indentMatch !== null ? indentMatch[1].replace(/\t/g, '  ').length : 0;
    const trimmed: string = indentMatch !== null ? indentMatch[2].trimEnd() : raw.trim();
    const indent: number = Math.min(4, Math.floor(spaces / 2));

    const taskMatch: RegExpExecArray | null = /^([-*+])\s+\[([ xX])\](?:\s+(.*))?$/.exec(trimmed);
    if (taskMatch !== null) {
      const p: WysiwygParagraph = new WysiwygParagraph();
      p.kind = WysiwygBlockKind.TASK;
      p.indent = indent;
      p.bulletChar = taskMatch[1];
      p.checked = taskMatch[2].toLowerCase() === 'x';
      const body: string = taskMatch[3] !== undefined ? taskMatch[3] : '';
      p.inlines = WysiwygCodec.parseInlines(body);
      return p;
    }

    const ulMatch: RegExpExecArray | null = /^([-*+])\s+(.*)$/.exec(trimmed);
    if (ulMatch !== null) {
      const p: WysiwygParagraph = new WysiwygParagraph();
      p.kind = WysiwygBlockKind.BULLET;
      p.indent = indent;
      p.bulletChar = ulMatch[1];
      p.inlines = WysiwygCodec.parseInlines(ulMatch[2]);
      return p;
    }

    const olMatch: RegExpExecArray | null = /^(\d+)([.)])\s+(.*)$/.exec(trimmed);
    if (olMatch !== null) {
      const p: WysiwygParagraph = new WysiwygParagraph();
      p.kind = WysiwygBlockKind.ORDERED;
      p.indent = indent;
      const ord: number = Number(olMatch[1]);
      p.ordinal = Number.isNaN(ord) ? 1 : ord;
      p.orderedDelimiter = olMatch[2];
      p.inlines = WysiwygCodec.parseInlines(olMatch[3]);
      return p;
    }
    return null;
  }

  /** 构造单段可视化表格段落（以 1 个图片占位 span 对应整块 Markdown 表格）。 */
  public static buildTableParagraph(rawMd: string, tightBreakAfter: boolean = false): WysiwygParagraph {
    const p: WysiwygParagraph = new WysiwygParagraph();
    p.kind = WysiwygBlockKind.TABLE;
    p.tableRawMd = rawMd.trim();
    p.tightBreakAfter = tightBreakAfter;
    const inline: WysiwygInline = WysiwygInline.plain('');
    inline.isImage = true;
    inline.imageTarget = 'table';
    inline.imageRawMd = p.tableRawMd;
    p.inlines = [inline];
    return p;
  }

  private static consumeTable(lines: string[], start: number, doc: WysiwygDocument): number {
    let i: number = start;
    const tableLines: string[] = [];
    while (i < lines.length) {
      const t: string = lines[i].trim();
      if (t.length === 0 || !t.includes('|')) {
        break;
      }
      tableLines.push(lines[i]);
      i++;
    }
    const p: WysiwygParagraph = WysiwygCodec.buildTableParagraph(
      tableLines.join('\n'),
      i < lines.length && lines[i].trim().length > 0
    );
    doc.paragraphs.push(p);
    return i;
  }

  private static consumeHtml(lines: string[], start: number, doc: WysiwygDocument): number {
    let i: number = start;
    const htmlLines: string[] = [];
    while (i < lines.length && lines[i].trim().length > 0) {
      htmlLines.push(lines[i]);
      i++;
    }
    for (let k: number = 0; k < htmlLines.length; k++) {
      const p: WysiwygParagraph = new WysiwygParagraph();
      p.kind = WysiwygBlockKind.HTML;
      p.inlines = [WysiwygInline.plain(htmlLines[k])];
      if (k === htmlLines.length - 1) {
        p.tightBreakAfter = i < lines.length && lines[i].trim().length > 0;
      }
      doc.paragraphs.push(p);
    }
    return i;
  }

  private static isThematicBreak(trimmed: string): boolean {
    if (trimmed.length < 3) {
      return false;
    }
    return /^(-\s*){3,}$/.test(trimmed) || /^(\*\s*){3,}$/.test(trimmed) || /^(_\s*){3,}$/.test(trimmed);
  }

  private static isTableDelimiter(trimmed: string): boolean {
    return WysiwygTableCodec.isDelimiterLine(trimmed);
  }

  private static walkMdInlines(nodes: MdInline[], bold: boolean, italic: boolean, strike: boolean,
    highlight: boolean, out: WysiwygInline[]): void {
    for (const node of nodes) {
      if (node.type === MdInlineType.STRONG) {
        WysiwygCodec.walkMdInlines(node.children, true, italic, strike, highlight, out);
        continue;
      }
      if (node.type === MdInlineType.EMPHASIS) {
        WysiwygCodec.walkMdInlines(node.children, bold, true, strike, highlight, out);
        continue;
      }
      if (node.type === MdInlineType.STRIKETHROUGH) {
        WysiwygCodec.walkMdInlines(node.children, bold, italic, true, highlight, out);
        continue;
      }
      if (node.type === MdInlineType.HIGHLIGHT) {
        WysiwygCodec.walkMdInlines(node.children, bold, italic, strike, true, out);
        continue;
      }
      const item: WysiwygInline = new WysiwygInline();
      item.bold = bold;
      item.italic = italic;
      item.strike = strike;
      item.highlight = highlight;
      if (node.type === MdInlineType.INLINE_CODE) {
        item.code = true;
        item.text = node.text;
      } else if (node.type === MdInlineType.WIKI_LINK) {
        item.kind = WysiwygSpanKind.WIKI_LINK;
        let inner: string = node.target;
        if (node.heading.length > 0) {
          inner += `#${node.heading}`;
        }
        if (node.blockRef.length > 0) {
          inner += `^${node.blockRef}`;
        }
        if (node.alias.length > 0) {
          inner += `|${node.alias}`;
        }
        item.target = inner;
        item.text = node.text;
        item.originalDisplay = node.text;
      } else if (node.type === MdInlineType.LINK) {
        item.kind = WysiwygSpanKind.MD_LINK;
        item.target = node.url;
        item.text = node.text;
        item.originalDisplay = node.text;
      } else if (node.type === MdInlineType.TAG) {
        item.kind = WysiwygSpanKind.TAG;
        item.target = node.text;
        item.text = `#${node.text}`;
      } else if (node.type === MdInlineType.MATH) {
        item.kind = WysiwygSpanKind.MATH_INLINE;
        item.target = node.text;
        item.text = `$${node.text}$`;
      } else if (node.type === MdInlineType.EMBED) {
        if (WysiwygCodec.isImageTarget(node.target)) {
          item.isImage = true;
          item.imageTarget = node.target;
          item.imageAlt = node.alias;
          const rawInner: string = node.alias.length > 0 ? `${node.target}|${node.alias}` : node.target;
          item.imageRawMd = `![[${rawInner}]]`;
        } else {
          item.text = node.alias.length > 0 ? `![[${node.target}|${node.alias}]]` : `![[${node.target}]]`;
        }
      } else if (node.type === MdInlineType.IMAGE) {
        item.isImage = true;
        item.imageTarget = node.url;
        item.imageAlt = node.text;
        item.imageRawMd = `![${node.text}](${node.url})`;
      } else {
        item.text = node.text;
      }
      out.push(item);
    }
  }

  private static collectSameKindRun(paragraphs: WysiwygParagraph[], start: number,
    kind: WysiwygBlockKind): number {
    const groupId: number = paragraphs[start].blockGroupId;
    let i: number = start + 1;
    while (i < paragraphs.length && paragraphs[i].kind === kind) {
      if (groupId !== 0 && paragraphs[i].blockGroupId !== 0 && paragraphs[i].blockGroupId !== groupId) {
        break;
      }
      i++;
    }
    return i;
  }

  private static isListKind(kind: WysiwygBlockKind): boolean {
    return kind === WysiwygBlockKind.BULLET || kind === WysiwygBlockKind.ORDERED ||
      kind === WysiwygBlockKind.TASK;
  }

  private static serializeListLine(p: WysiwygParagraph): string {
    const pad: string = '  '.repeat(Math.max(0, p.indent));
    const text: string = WysiwygCodec.serializeInlines(p.inlines);
    if (p.kind === WysiwygBlockKind.TASK) {
      const box: string = p.checked ? 'x' : ' ';
      return `${pad}${p.bulletChar} [${box}] ${text}`;
    }
    if (p.kind === WysiwygBlockKind.ORDERED) {
      return `${pad}${p.ordinal}${p.orderedDelimiter} ${text}`;
    }
    return `${pad}${p.bulletChar} ${text}`;
  }

  private static serializeQuoteOrCalloutLine(p: WysiwygParagraph, isHeader: boolean): string {
    const text: string = WysiwygCodec.serializeInlines(p.inlines);
    if (p.kind === WysiwygBlockKind.CALLOUT && isHeader && p.calloutType.length > 0) {
      const fold: string = p.calloutHasFoldMarker ? (p.calloutFolded ? '-' : '+') : '';
      return text.length > 0 ? `> [!${p.calloutType}]${fold} ${text}` : `> [!${p.calloutType}]${fold}`;
    }
    return text.length > 0 ? `> ${text}` : '>';
  }

  private static serializeSingleBlock(p: WysiwygParagraph): string {
    if (p.kind === WysiwygBlockKind.TABLE) {
      const rawTable: string = p.tableRawMd.trim();
      return rawTable.length > 0 ? rawTable : WysiwygCodec.plainParagraphText(p);
    }
    if (p.kind === WysiwygBlockKind.HR) {
      return '---';
    }
    if (p.kind === WysiwygBlockKind.HEADING) {
      const hashes: string = '#'.repeat(Math.min(6, Math.max(1, p.level)));
      return `${hashes} ${WysiwygCodec.serializeInlines(p.inlines)}`;
    }
    if (p.kind === WysiwygBlockKind.IMAGE || p.kind === WysiwygBlockKind.EMBED) {
      return WysiwygCodec.serializeInlines(p.inlines);
    }
    return WysiwygCodec.serializeInlines(p.inlines);
  }

  private static plainParagraphText(p: WysiwygParagraph): string {
    let text: string = '';
    for (const inline of p.inlines) {
      text += inline.text;
    }
    return text;
  }

  private static canMergePlainStyle(a: WysiwygInline, b: WysiwygInline): boolean {
    return !b.isImage && b.kind === WysiwygSpanKind.PLAIN && !b.code &&
      a.bold === b.bold && a.italic === b.italic && a.strike === b.strike && a.highlight === b.highlight;
  }

  private static serializeImageInline(inline: WysiwygInline): string {
    if (inline.imageRawMd.length > 0) {
      return inline.imageRawMd;
    }
    if (inline.imageWidth > 0) {
      return `![[${inline.imageTarget}|${inline.imageWidth}]]`;
    }
    if (inline.imageAlt.length > 0) {
      return `![${inline.imageAlt}](${inline.imageTarget})`;
    }
    return `![[${inline.imageTarget}]]`;
  }

  private static serializeSpecialInline(inline: WysiwygInline): string {
    if (inline.code) {
      const text: string = inline.text;
      if (text.includes('`')) {
        return `\`\` ${text} \`\``;
      }
      return `\`${text}\``;
    }
    if (inline.kind === WysiwygSpanKind.WIKI_LINK) {
      const inner: string = inline.text === inline.originalDisplay || inline.originalDisplay.length === 0
        ? inline.target
        : WysiwygCodec.updatedWikiInner(inline.target, inline.text);
      return `[[${inner}]]`;
    }
    if (inline.kind === WysiwygSpanKind.MD_LINK) {
      return `[${inline.text}](${inline.target})`;
    }
    if (inline.kind === WysiwygSpanKind.TAG) {
      const clean: string = inline.text.trim();
      return clean.startsWith('#') ? clean : `#${clean}`;
    }
    if (inline.kind === WysiwygSpanKind.MATH_INLINE) {
      const trimmed: string = inline.text.trim();
      if (trimmed.startsWith('$') && trimmed.endsWith('$')) {
        return trimmed;
      }
      return `$${inline.target.length > 0 ? inline.target : trimmed}$`;
    }
    return inline.text;
  }

  private static wrapInlineStyle(raw: string, bold: boolean, italic: boolean,
    strike: boolean, highlight: boolean): string {
    if (raw.length === 0 || (!bold && !italic && !strike && !highlight)) {
      return raw;
    }
    const leadMatch: RegExpExecArray | null = /^(\s*)(.*?)(\s*)$/.exec(raw);
    const leading: string = leadMatch !== null ? leadMatch[1] : '';
    const core: string = leadMatch !== null ? leadMatch[2] : raw;
    const trailing: string = leadMatch !== null ? leadMatch[3] : '';
    if (core.length === 0) {
      return raw;
    }
    let out: string = core;
    if (highlight) {
      out = `==${out}==`;
    }
    if (strike) {
      out = `~~${out}~~`;
    }
    if (bold && italic) {
      out = `***${out}***`;
    } else if (bold) {
      out = `**${out}**`;
    } else if (italic) {
      out = `*${out}*`;
    }
    return `${leading}${out}${trailing}`;
  }
}
