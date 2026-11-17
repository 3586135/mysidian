import { resourceManager } from '@kit.LocalizationKit';
import {
  CodeHighlighter,
  CodeToken,
  CodeTokenKind,
  WysiwygBlockKind,
  WysiwygInline,
  WysiwygParagraph,
  WysiwygSpanKind
} from '@ohos/markdown';
import { DesignPalette } from '../../viewmodel/DesignPalette';
import { WysiwygMarginCache } from './WysiwygMarginCache';

/** 主题感知运行时调色板（供给 RichEditor 样式与高亮背景）。 */
export class WysiwygThemeColors {
  isDark: boolean = false;
  highlightBg: string = 'rgba(255,193,7,0.22)';
  codeBg: string = 'rgba(0,0,0,0.05)';
  kwColor: string = '#7C3AED';
  strColor: string = '#15803D';
  cmtColor: string = '#78716C';
  numColor: string = '#C2410C';
  typeColor: string = '#0369A1';
}

/** 从 RichEditor 导出的单个图片映射记录。 */
export class WysiwygImageRecord {
  target: string = '';
  alt: string = '';
  width: number = 0;
  rawMd: string = '';
}

/** 内部按段落切分后的 span 切片。 */
class ExtractedSpan {
  value: string = '';
  isImage: boolean = false;
  imageUri: string = '';
  textStyle?: RichEditorTextStyleResult;
  url?: string;
}

/** 解码后的 urlStyle 语义载荷。 */
export class DecodedSpanUrl {
  kind: WysiwygSpanKind = WysiwygSpanKind.PLAIN;
  target: string = '';
  originalDisplay: string = '';
}

/**
 * RichEditor Span 样式构造与反向提取/序列化辅助类。
 * 保持纯方法、单职责，严格区分标题粗体/已完成任务划线与正文中手动加粗/删除线。
 */
export class WysiwygStyleHelper {
  public static resolveThemeColors(mgr: resourceManager.ResourceManager | null): WysiwygThemeColors {
    const c: WysiwygThemeColors = new WysiwygThemeColors();
    if (mgr === null) {
      return c;
    }
    c.isDark = DesignPalette.isDarkMode(mgr);
    c.highlightBg = c.isDark ? 'rgba(255,193,7,0.28)' : 'rgba(255,193,7,0.22)';
    c.codeBg = c.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)';
    c.kwColor = WysiwygStyleHelper.pick(mgr, 'md_code_keyword', c.isDark ? '#A78BFA' : '#7C3AED');
    c.strColor = WysiwygStyleHelper.pick(mgr, 'md_code_string', c.isDark ? '#4ADE80' : '#15803D');
    c.cmtColor = WysiwygStyleHelper.pick(mgr, 'md_code_comment', c.isDark ? '#9CA3AF' : '#78716C');
    c.numColor = WysiwygStyleHelper.pick(mgr, 'md_code_number', c.isDark ? '#FB923C' : '#C2410C');
    c.typeColor = WysiwygStyleHelper.pick(mgr, 'md_code_type', c.isDark ? '#38BDF8' : '#0369A1');
    return c;
  }

  private static pick(mgr: resourceManager.ResourceManager, name: string, fallback: string): string {
    const val: string = DesignPalette.color(mgr, name);
    return val === DesignPalette.FALLBACK ? fallback : val;
  }

  /** 判断 RichEditor 返回的 span 结果是否为图片 span（集中隔离 union 收窄）。 */
  public static isImageSpanResult(span: RichEditorImageSpanResult | RichEditorTextSpanResult): boolean {
    return (span as RichEditorImageSpanResult).imageStyle !== undefined;
  }

  /** 读取文本 span 的字符串值。 */
  public static asTextSpan(span: RichEditorImageSpanResult | RichEditorTextSpanResult): RichEditorTextSpanResult {
    return span as RichEditorTextSpanResult;
  }

  /** 读取图片 span 的结构化数据。 */
  public static asImageSpan(span: RichEditorImageSpanResult | RichEditorTextSpanResult): RichEditorImageSpanResult {
    return span as RichEditorImageSpanResult;
  }

  /** 标题字号（与纯阅读态 MdBlockView 保持视觉阶梯一致）。 */
  public static headingFontSize(level: number, baseFontSize: number): number {
    if (level <= 1) {
      return baseFontSize + 10;
    }
    if (level === 2) {
      return baseFontSize + 7;
    }
    if (level === 3) {
      return baseFontSize + 5;
    }
    if (level === 4) {
      return baseFontSize + 3;
    }
    if (level === 5) {
      return baseFontSize + 2;
    }
    return baseFontSize + 1;
  }

  /** 按段落元数据生成默认段落样式（前导图形边距 + 段落间距）。 */
  public static buildParagraphStyle(meta: WysiwygParagraph, margins: WysiwygMarginCache,
    mgr: resourceManager.ResourceManager | null, baseFontSize: number,
    spacingOverride: number = -1): RichEditorParagraphStyle {
    const placeholder: LeadingMarginPlaceholder | undefined = margins.getPlaceholder(
      mgr, meta.kind, meta.indent, meta.ordinal, meta.orderedDelimiter, meta.checked, baseFontSize);
    const compact: boolean = meta.kind === WysiwygBlockKind.CODE ||
      meta.kind === WysiwygBlockKind.MATH ||
      meta.kind === WysiwygBlockKind.HTML;
    const isListOrQuote: boolean = meta.kind === WysiwygBlockKind.BULLET ||
      meta.kind === WysiwygBlockKind.ORDERED ||
      meta.kind === WysiwygBlockKind.TASK ||
      meta.kind === WysiwygBlockKind.QUOTE ||
      meta.kind === WysiwygBlockKind.CALLOUT;
    let spacing: number = 8;
    if (spacingOverride >= 0) {
      spacing = spacingOverride;
    } else if (compact) {
      spacing = 2;
    } else if (isListOrQuote) {
      spacing = 4;
    } else if (meta.kind === WysiwygBlockKind.HEADING) {
      spacing = 10;
    } else if (meta.kind === WysiwygBlockKind.HR) {
      spacing = 10;
    }
    return {
      textAlign: meta.kind === WysiwygBlockKind.HR ? TextAlign.Center : TextAlign.Start,
      leadingMargin: placeholder !== undefined ? placeholder
        : (meta.kind === WysiwygBlockKind.HTML ? 8 : 0),
      paragraphSpacing: spacing
    };
  }

  /** 构造某个段落在新输入时的默认 RichEditorTextStyle。 */
  public static buildDefaultTextStyle(meta: WysiwygParagraph, baseFontSize: number,
    colors: WysiwygThemeColors): RichEditorTextStyle {
    if (meta.kind === WysiwygBlockKind.HEADING) {
      return {
        fontSize: WysiwygStyleHelper.headingFontSize(meta.level, baseFontSize),
        fontWeight: FontWeight.Bold,
        fontStyle: FontStyle.Normal,
        fontFamily: 'HarmonyOS Sans',
        fontColor: meta.level >= 6
          ? $r('app.color.design_text_secondary')
          : $r('app.color.design_text_primary'),
        decoration: { type: TextDecorationType.None }
      };
    }
    if (meta.kind === WysiwygBlockKind.CODE ||
      meta.kind === WysiwygBlockKind.MATH || meta.kind === WysiwygBlockKind.HTML) {
      return {
        fontSize: Math.max(12, baseFontSize - 1),
        fontWeight: FontWeight.Normal,
        fontStyle: FontStyle.Normal,
        fontFamily: 'monospace',
        fontColor: meta.kind === WysiwygBlockKind.MATH
          ? $r('app.color.design_accent') : $r('app.color.design_text_primary'),
        textBackgroundStyle: meta.kind === WysiwygBlockKind.CODE
          ? { color: colors.codeBg, radius: 4 } : undefined,
        decoration: { type: TextDecorationType.None }
      };
    }
    if (meta.kind === WysiwygBlockKind.HR) {
      return {
        fontSize: baseFontSize,
        fontWeight: FontWeight.Normal,
        fontStyle: FontStyle.Normal,
        fontFamily: 'HarmonyOS Sans',
        fontColor: $r('app.color.design_divider'),
        decoration: { type: TextDecorationType.None }
      };
    }
    if (meta.kind === WysiwygBlockKind.EMBED) {
      return {
        fontSize: Math.max(13, baseFontSize - 1),
        fontWeight: FontWeight.Medium,
        fontStyle: FontStyle.Normal,
        fontFamily: 'HarmonyOS Sans',
        fontColor: $r('app.color.design_accent'),
        textBackgroundStyle: { color: $r('app.color.design_accent_weak'), radius: 6 },
        decoration: { type: TextDecorationType.None }
      };
    }
    if (meta.kind === WysiwygBlockKind.TASK && meta.checked) {
      return {
        fontSize: baseFontSize,
        fontWeight: FontWeight.Normal,
        fontStyle: FontStyle.Normal,
        fontFamily: 'HarmonyOS Sans',
        fontColor: $r('app.color.design_text_secondary'),
        decoration: { type: TextDecorationType.LineThrough, color: $r('app.color.design_text_secondary') }
      };
    }
    if (meta.kind === WysiwygBlockKind.QUOTE || meta.kind === WysiwygBlockKind.CALLOUT) {
      return {
        fontSize: baseFontSize,
        fontWeight: meta.kind === WysiwygBlockKind.CALLOUT ? FontWeight.Medium : FontWeight.Normal,
        fontStyle: FontStyle.Normal,
        fontFamily: 'HarmonyOS Sans',
        fontColor: meta.kind === WysiwygBlockKind.CALLOUT
          ? $r('app.color.design_text_primary') : $r('app.color.design_text_secondary'),
        decoration: { type: TextDecorationType.None }
      };
    }
    return {
      fontSize: baseFontSize,
      fontWeight: FontWeight.Normal,
      fontStyle: FontStyle.Normal,
      fontFamily: 'HarmonyOS Sans',
      fontColor: $r('app.color.design_text_primary'),
      decoration: { type: TextDecorationType.None }
    };
  }

  /** 为单个 WysiwygInline 生成写入 RichEditor 的文本样式。 */
  public static buildInlineTextStyle(meta: WysiwygParagraph, inline: WysiwygInline,
    baseFontSize: number, colors: WysiwygThemeColors): RichEditorTextStyle {
    const isHeading: boolean = meta.kind === WysiwygBlockKind.HEADING;
    const isCheckedTask: boolean = meta.kind === WysiwygBlockKind.TASK && meta.checked;
    const baseSize: number = isHeading
      ? WysiwygStyleHelper.headingFontSize(meta.level, baseFontSize) : baseFontSize;
    const isSemanticLink: boolean = inline.kind === WysiwygSpanKind.WIKI_LINK ||
      inline.kind === WysiwygSpanKind.MD_LINK;
    const isTag: boolean = inline.kind === WysiwygSpanKind.TAG;
    const isMath: boolean = inline.kind === WysiwygSpanKind.MATH_INLINE;

    let fontColor: ResourceColor = $r('app.color.design_text_primary');
    if (isCheckedTask) {
      fontColor = $r('app.color.design_text_secondary');
    } else if (isSemanticLink || isTag || isMath) {
      fontColor = $r('app.color.design_accent');
    } else if (inline.code) {
      fontColor = $r('app.color.design_text_secondary');
    } else if (meta.kind === WysiwygBlockKind.QUOTE) {
      fontColor = $r('app.color.design_text_secondary');
    } else if (meta.kind === WysiwygBlockKind.HEADING && meta.level >= 6) {
      fontColor = $r('app.color.design_text_secondary');
    } else if (meta.kind === WysiwygBlockKind.HR) {
      fontColor = $r('app.color.design_divider');
    }

    let bg: TextBackgroundStyle | undefined = undefined;
    if (inline.code) {
      bg = { color: colors.codeBg, radius: 4 };
    } else if (inline.highlight) {
      bg = { color: colors.highlightBg, radius: 4 };
    }

    let decType: TextDecorationType = TextDecorationType.None;
    let decColor: ResourceColor = fontColor;
    if (inline.strike || isCheckedTask) {
      decType = TextDecorationType.LineThrough;
      decColor = isCheckedTask ? $r('app.color.design_text_secondary') : $r('app.color.design_text_primary');
    } else if (isSemanticLink) {
      decType = TextDecorationType.Underline;
      decColor = $r('app.color.design_accent');
    }

    return {
      fontSize: (inline.code || isMath) && !isHeading ? Math.max(12, baseSize - 1) : baseSize,
      fontWeight: isHeading || inline.bold ? FontWeight.Bold : FontWeight.Normal,
      fontStyle: inline.italic ? FontStyle.Italic : FontStyle.Normal,
      fontFamily: inline.code || isMath ? 'monospace' : 'HarmonyOS Sans',
      fontColor: fontColor,
      textBackgroundStyle: bg,
      decoration: { type: decType, color: decColor }
    };
  }

  /** 把语法高亮 Token 转为代码块行样式。 */
  public static buildCodeTokenStyle(token: CodeToken, baseFontSize: number,
    colors: WysiwygThemeColors): RichEditorTextStyle {
    let color: ResourceColor = $r('app.color.design_text_primary');
    if (token.kind === CodeTokenKind.KEYWORD) {
      color = colors.kwColor;
    } else if (token.kind === CodeTokenKind.STRING) {
      color = colors.strColor;
    } else if (token.kind === CodeTokenKind.COMMENT) {
      color = colors.cmtColor;
    } else if (token.kind === CodeTokenKind.NUMBER) {
      color = colors.numColor;
    } else if (token.kind === CodeTokenKind.TYPE) {
      color = colors.typeColor;
    }
    return {
      fontSize: Math.max(12, baseFontSize - 1),
      fontWeight: FontWeight.Normal,
      fontStyle: FontStyle.Normal,
      fontFamily: 'monospace',
      fontColor: color,
      textBackgroundStyle: { color: colors.codeBg, radius: 3 },
      decoration: { type: TextDecorationType.None }
    };
  }

  /** 把语义元数据编码为 RichEditorUrlStyle。 */
  public static encodeSpanUrl(kind: WysiwygSpanKind, target: string,
    originalDisplay: string = ''): RichEditorUrlStyle | undefined {
    if (kind === WysiwygSpanKind.WIKI_LINK) {
      return { url: `w:${encodeURIComponent(target)}|${encodeURIComponent(originalDisplay)}` };
    }
    if (kind === WysiwygSpanKind.MD_LINK) {
      return { url: `l:${encodeURIComponent(target)}` };
    }
    if (kind === WysiwygSpanKind.TAG) {
      return { url: `t:${encodeURIComponent(target)}` };
    }
    if (kind === WysiwygSpanKind.MATH_INLINE) {
      return { url: `m:${encodeURIComponent(target)}` };
    }
    return undefined;
  }

  /** 从 urlStyle.url 解码语义元数据。 */
  public static decodeSpanUrl(url: string | undefined): DecodedSpanUrl {
    const out: DecodedSpanUrl = new DecodedSpanUrl();
    if (url === undefined || url.length < 2) {
      return out;
    }
    if (url.startsWith('w:')) {
      out.kind = WysiwygSpanKind.WIKI_LINK;
      const body: string = url.substring(2);
      const sep: number = body.indexOf('|');
      try {
        if (sep >= 0) {
          out.target = decodeURIComponent(body.substring(0, sep));
          out.originalDisplay = decodeURIComponent(body.substring(sep + 1));
        } else {
          out.target = decodeURIComponent(body);
        }
      } catch (error) {
        out.target = body;
      }
      return out;
    }
    if (url.startsWith('l:')) {
      out.kind = WysiwygSpanKind.MD_LINK;
      try {
        out.target = decodeURIComponent(url.substring(2));
      } catch (error) {
        out.target = url.substring(2);
      }
      return out;
    }
    if (url.startsWith('t:')) {
      out.kind = WysiwygSpanKind.TAG;
      try {
        out.target = decodeURIComponent(url.substring(2));
      } catch (error) {
        out.target = url.substring(2);
      }
      return out;
    }
    if (url.startsWith('m:')) {
      out.kind = WysiwygSpanKind.MATH_INLINE;
      try {
        out.target = decodeURIComponent(url.substring(2));
      } catch (error) {
        out.target = url.substring(2);
      }
    }
    return out;
  }

  /** 从局部范围 getSpans({ start, end }) 精确提取插入片段纯文本，避免扫描整篇。 */
  public static collectRangePlainText(spans: Array<RichEditorImageSpanResult | RichEditorTextSpanResult>): string {
    let text: string = '';
    for (const span of spans) {
      if (WysiwygStyleHelper.isImageSpanResult(span)) {
        text += ' ';
      } else {
        const ts: RichEditorTextSpanResult = WysiwygStyleHelper.asTextSpan(span);
        const raw: string = ts.value;
        const s0: number = ts.offsetInSpan !== undefined ? Math.max(0, ts.offsetInSpan[0]) : 0;
        const s1: number = ts.offsetInSpan !== undefined ? Math.min(raw.length, ts.offsetInSpan[1]) : raw.length;
        if (s1 > s0) {
          text += raw.substring(s0, s1);
        }
      }
    }
    return text;
  }

  /** 从 getSpans() 收集纯文本（每个图片 span 占位 1 个字符，严格对齐 RichEditor 偏移空间）。 */
  public static collectPlainText(spans: Array<RichEditorImageSpanResult | RichEditorTextSpanResult>): string {
    let text: string = '';
    for (const span of spans) {
      if (WysiwygStyleHelper.isImageSpanResult(span)) {
        text += ' ';
      } else {
        text += WysiwygStyleHelper.asTextSpan(span).value;
      }
    }
    return text;
  }

  /** 把 RichEditor 的实时 spans 与段落元数据合并为可无损序列化的 WysiwygParagraph[]。 */
  public static extractParagraphs(
    spans: Array<RichEditorImageSpanResult | RichEditorTextSpanResult>,
    metas: WysiwygParagraph[],
    imageMap: Map<string, WysiwygImageRecord>
  ): WysiwygParagraph[] {
    const linesSpans: Array<Array<ExtractedSpan>> = [[]];
    for (const span of spans) {
      if (WysiwygStyleHelper.isImageSpanResult(span)) {
        const imgSpan: RichEditorImageSpanResult = WysiwygStyleHelper.asImageSpan(span);
        const rec: ExtractedSpan = new ExtractedSpan();
        rec.isImage = true;
        rec.imageUri = imgSpan.valueResourceStr !== undefined ? String(imgSpan.valueResourceStr) : '';
        linesSpans[linesSpans.length - 1].push(rec);
        continue;
      }
      const txtSpan: RichEditorTextSpanResult = WysiwygStyleHelper.asTextSpan(span);
      const urlVal: string | undefined = txtSpan.urlStyle !== undefined && txtSpan.urlStyle.url !== undefined
        ? String(txtSpan.urlStyle.url) : undefined;
      const parts: string[] = txtSpan.value.split('\n');
      for (let p: number = 0; p < parts.length; p++) {
        if (parts[p].length > 0) {
          const piece: ExtractedSpan = new ExtractedSpan();
          piece.value = parts[p];
          piece.textStyle = txtSpan.textStyle;
          piece.url = urlVal;
          linesSpans[linesSpans.length - 1].push(piece);
        }
        if (p + 1 < parts.length) {
          linesSpans.push([]);
        }
      }
    }

    const result: WysiwygParagraph[] = [];
    for (let i: number = 0; i < linesSpans.length; i++) {
      const baseMeta: WysiwygParagraph = i < metas.length ? metas[i].clone() : new WysiwygParagraph();
      baseMeta.inlines = [];
      const rowSpans: ExtractedSpan[] = linesSpans[i];
      if (baseMeta.kind === WysiwygBlockKind.IMAGE && rowSpans.length === 1 && rowSpans[0].isImage) {
        baseMeta.inlines.push(WysiwygStyleHelper.buildExtractedImageInline(rowSpans[0].imageUri, imageMap));
        result.push(baseMeta);
        continue;
      }
      if (baseMeta.kind === WysiwygBlockKind.IMAGE && rowSpans.length === 0) {
        // 图片被删光：退化为空普通段落。
        baseMeta.kind = WysiwygBlockKind.PARAGRAPH;
        result.push(baseMeta);
        continue;
      }
      if (baseMeta.kind === WysiwygBlockKind.IMAGE && !rowSpans.some((s: ExtractedSpan): boolean => s.isImage)) {
        baseMeta.kind = WysiwygBlockKind.PARAGRAPH;
      }
      if (baseMeta.kind === WysiwygBlockKind.TABLE) {
        if (rowSpans.some((s: ExtractedSpan): boolean => s.isImage)) {
          const tblInline: WysiwygInline = WysiwygInline.plain('');
          tblInline.isImage = true;
          tblInline.imageTarget = 'table';
          tblInline.imageRawMd = baseMeta.tableRawMd;
          baseMeta.inlines.push(tblInline);
          result.push(baseMeta);
          continue;
        }
        baseMeta.kind = WysiwygBlockKind.PARAGRAPH;
        baseMeta.tableRawMd = '';
        baseMeta.blockGroupId = 0;
      }

      const rawBlockKind: boolean = baseMeta.kind === WysiwygBlockKind.CODE ||
        baseMeta.kind === WysiwygBlockKind.MATH ||
        baseMeta.kind === WysiwygBlockKind.HTML || baseMeta.kind === WysiwygBlockKind.HR ||
        baseMeta.kind === WysiwygBlockKind.EMBED;

      for (const s of rowSpans) {
        if (s.isImage) {
          baseMeta.inlines.push(WysiwygStyleHelper.buildExtractedImageInline(s.imageUri, imageMap));
          continue;
        }
        if (rawBlockKind) {
          baseMeta.inlines.push(WysiwygInline.plain(s.value));
          continue;
        }
        baseMeta.inlines.push(WysiwygStyleHelper.buildExtractedTextInline(baseMeta, s));
      }
      result.push(baseMeta);
    }
    return result;
  }

  /** 将指定段落用当前元数据 + 代码高亮整段写入 RichEditor（用于初次加载与撤销恢复）。 */
  public static tokenizeCodeLine(lineText: string, lang: string): CodeToken[] {
    return CodeHighlighter.tokenize(lineText, lang);
  }

  private static buildExtractedImageInline(uri: string, imageMap: Map<string, WysiwygImageRecord>): WysiwygInline {
    const inline: WysiwygInline = new WysiwygInline();
    inline.isImage = true;
    const hit: WysiwygImageRecord | undefined = imageMap.get(uri);
    if (hit !== undefined) {
      inline.imageTarget = hit.target;
      inline.imageAlt = hit.alt;
      inline.imageWidth = hit.width;
      inline.imageRawMd = hit.rawMd;
    } else {
      inline.imageTarget = uri;
      inline.imageRawMd = `![[${uri}]]`;
    }
    return inline;
  }

  private static buildExtractedTextInline(meta: WysiwygParagraph, s: ExtractedSpan): WysiwygInline {
    const inline: WysiwygInline = new WysiwygInline();
    inline.text = s.value;
    const decoded: DecodedSpanUrl = WysiwygStyleHelper.decodeSpanUrl(s.url);
    if (decoded.kind !== WysiwygSpanKind.PLAIN) {
      inline.kind = decoded.kind;
      inline.target = decoded.target;
      inline.originalDisplay = decoded.originalDisplay;
      return inline;
    }
    const ts: RichEditorTextStyleResult | undefined = s.textStyle;
    if (ts === undefined) {
      return inline;
    }
    const family: string = ts.fontFamily !== undefined ? ts.fontFamily.toLowerCase() : '';
    const isMono: boolean = family.includes('monospace');
    if (isMono) {
      inline.code = true;
      return inline;
    }
    const isHeading: boolean = meta.kind === WysiwygBlockKind.HEADING;
    const isCheckedTask: boolean = meta.kind === WysiwygBlockKind.TASK && meta.checked;
    const isCalloutHeader: boolean = meta.kind === WysiwygBlockKind.CALLOUT;
    if (!isHeading && !isCalloutHeader) {
      inline.bold = WysiwygStyleHelper.isBoldWeight(ts.fontWeight);
    }
    inline.italic = ts.fontStyle === FontStyle.Italic;
    if (!isCheckedTask && ts.decoration !== undefined && ts.decoration.type === TextDecorationType.LineThrough) {
      inline.strike = true;
    }
    if (WysiwygStyleHelper.hasVisibleBackground(ts.textBackgroundStyle)) {
      inline.highlight = true;
    }
    return inline;
  }

  /** 判断字重是否为粗体：兼容 OpenHarmony C++ 枚举（W600..W900=5..8, BOLD=9, BOLDER=11）、数值(>=600)与枚举字符串。 */
  public static isBoldWeight(weight: number | FontWeight | string | undefined): boolean {
    if (weight === undefined) {
      return false;
    }
    if (typeof weight === 'string') {
      const lower: string = weight.toLowerCase();
      return lower === 'bold' || lower === 'bolder' || lower === '600' || lower === '700' ||
        lower === '800' || lower === '900';
    }
    return weight === 9 || weight === 11 || (weight >= 5 && weight <= 8) || weight >= 600 ||
      weight === FontWeight.Bold || weight === FontWeight.Bolder;
  }

  private static hasVisibleBackground(bg: TextBackgroundStyle | undefined): boolean {
    if (bg === undefined || bg.color === undefined) {
      return false;
    }
    const c: string = String(bg.color).trim().toLowerCase();
    return c.length > 0 && c !== '0' && c !== '#00000000' && c !== 'rgba(0,0,0,0)' &&
      c !== 'rgba(0, 0, 0, 0)' && bg.color !== Color.Transparent;
  }
}
