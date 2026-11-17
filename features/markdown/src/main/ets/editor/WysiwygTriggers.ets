import { WysiwygBlockKind, WysiwygSpanKind } from './WysiwygModel';

/** 行首 Markdown 块级触发结果。 */
export class BlockTriggerResult {
  kind: WysiwygBlockKind = WysiwygBlockKind.PARAGRAPH;
  level: number = 0;
  indent: number = 0;
  ordinal: number = 1;
  orderedDelimiter: string = '.';
  bulletChar: string = '-';
  checked: boolean = false;
  lang: string = '';
  /** 需要从段首删除的前缀字符长度。 */
  stripLength: number = 0;
}

/** 行内 Markdown 实时转换触发结果。 */
export class InlineTriggerResult {
  /** 段内替换起始偏移（含起始语法标记）。 */
  startOffset: number = 0;
  /** 段内替换结束偏移（含闭合语法标记及可选触发空白）。 */
  endOffset: number = 0;
  text: string = '';
  bold: boolean = false;
  italic: boolean = false;
  strike: boolean = false;
  highlight: boolean = false;
  code: boolean = false;
  kind: WysiwygSpanKind = WysiwygSpanKind.PLAIN;
  target: string = '';
  /** 若由末尾空白/换行触发（如 #tag 后敲空格），保留尾部字符。 */
  trailingChar: string = '';
}

/**
 * 所见即所得编辑器的实时 Markdown 语法识别器与段落行索引工具。
 * 无 ArkUI 依赖，所有边界均可直接单元测试。
 */
export class WysiwygTriggers {
  /** 视觉水平分割线文本。 */
  public static readonly HR_DISPLAY: string = '────────────────────';

  /**
   * 识别当前段首刚输入的块级快捷前缀（通常在用户输入空格时调用）。
   * 支持：`# `..`###### `、`- `/`+ `、`1. `/`1) `、`- [ ] `/`[ ] `/`[] `、`- [x] `、`> `、`--- `。
   */
  public static matchBlockPrefix(linePrefix: string): BlockTriggerResult | null {
    const headingMatch: RegExpExecArray | null = /^(#{1,6})\s$/.exec(linePrefix);
    if (headingMatch !== null) {
      const res: BlockTriggerResult = new BlockTriggerResult();
      res.kind = WysiwygBlockKind.HEADING;
      res.level = headingMatch[1].length;
      res.stripLength = linePrefix.length;
      return res;
    }

    const taskMatch: RegExpExecArray | null = /^([-*+])\s+\[([ xX]?)\]\s$/.exec(linePrefix);
    if (taskMatch !== null) {
      const res: BlockTriggerResult = new BlockTriggerResult();
      res.kind = WysiwygBlockKind.TASK;
      res.bulletChar = taskMatch[1];
      res.checked = taskMatch[2].toLowerCase() === 'x';
      res.stripLength = linePrefix.length;
      return res;
    }

    const shortTaskMatch: RegExpExecArray | null = /^\[([ xX]?)\]\s$/.exec(linePrefix);
    if (shortTaskMatch !== null) {
      const res: BlockTriggerResult = new BlockTriggerResult();
      res.kind = WysiwygBlockKind.TASK;
      res.bulletChar = '-';
      res.checked = shortTaskMatch[1].toLowerCase() === 'x';
      res.stripLength = linePrefix.length;
      return res;
    }

    const bulletMatch: RegExpExecArray | null = /^([-*+])\s$/.exec(linePrefix);
    if (bulletMatch !== null) {
      const res: BlockTriggerResult = new BlockTriggerResult();
      res.kind = WysiwygBlockKind.BULLET;
      res.bulletChar = bulletMatch[1];
      res.stripLength = linePrefix.length;
      return res;
    }

    const orderedMatch: RegExpExecArray | null = /^(\d+)([.)])\s$/.exec(linePrefix);
    if (orderedMatch !== null) {
      const parsed: number = Number(orderedMatch[1]);
      const res: BlockTriggerResult = new BlockTriggerResult();
      res.kind = WysiwygBlockKind.ORDERED;
      res.ordinal = Number.isNaN(parsed) || parsed < 1 ? 1 : parsed;
      res.orderedDelimiter = orderedMatch[2];
      res.stripLength = linePrefix.length;
      return res;
    }

    const quoteMatch: RegExpExecArray | null = /^>\s$/.exec(linePrefix);
    if (quoteMatch !== null) {
      const res: BlockTriggerResult = new BlockTriggerResult();
      res.kind = WysiwygBlockKind.QUOTE;
      res.stripLength = linePrefix.length;
      return res;
    }

    const hrMatch: RegExpExecArray | null = /^(?:---|\*\*\*|___)\s$/.exec(linePrefix);
    if (hrMatch !== null) {
      const res: BlockTriggerResult = new BlockTriggerResult();
      res.kind = WysiwygBlockKind.HR;
      res.stripLength = linePrefix.length;
      return res;
    }

    return null;
  }

  /**
   * 识别按 Enter 触发的块级转换：` ```lang `、`$$`、`---`。
   */
  public static matchEnterBlock(lineText: string): BlockTriggerResult | null {
    const trimmed: string = lineText.trim();
    const codeMatch: RegExpExecArray | null = /^```([A-Za-z0-9_+#.-]*)$/.exec(trimmed);
    if (codeMatch !== null) {
      const res: BlockTriggerResult = new BlockTriggerResult();
      res.kind = WysiwygBlockKind.CODE;
      res.lang = codeMatch[1];
      res.stripLength = lineText.length;
      return res;
    }
    if (trimmed === '$$') {
      const res: BlockTriggerResult = new BlockTriggerResult();
      res.kind = WysiwygBlockKind.MATH;
      res.stripLength = lineText.length;
      return res;
    }
    if (/^(?:---|\*\*\*|___)$/.test(trimmed)) {
      const res: BlockTriggerResult = new BlockTriggerResult();
      res.kind = WysiwygBlockKind.HR;
      res.stripLength = lineText.length;
      return res;
    }
    return null;
  }

  /**
   * 识别光标前刚闭合的行内 Markdown 语法：
   * `**加粗**`、`*斜体*`、`~~删除线~~`、`==高亮==`、`` `代码` ``、`[[双链]]`、`[链接](url)`、`#标签 `。
   */
  public static matchInlineSyntax(linePrefix: string): InlineTriggerResult | null {
    if (linePrefix.length < 3) {
      return null;
    }
    const lastCh: string = linePrefix.charAt(linePrefix.length - 1);

    if (lastCh === '*') {
      const boldRes: InlineTriggerResult | null = WysiwygTriggers.matchSymmetricPair(
        linePrefix, '**', false, true, false, false, false);
      if (boldRes !== null) {
        return boldRes;
      }
      return WysiwygTriggers.matchSingleAsteriskItalic(linePrefix);
    }
    if (lastCh === '~') {
      return WysiwygTriggers.matchSymmetricPair(linePrefix, '~~', false, false, false, true, false);
    }
    if (lastCh === '=') {
      return WysiwygTriggers.matchSymmetricPair(linePrefix, '==', false, false, false, false, true);
    }
    if (lastCh === '`') {
      return WysiwygTriggers.matchSingleBacktickCode(linePrefix);
    }
    if (lastCh === ']') {
      return WysiwygTriggers.matchWikiLinkSuffix(linePrefix);
    }
    if (lastCh === ')') {
      return WysiwygTriggers.matchMdLinkSuffix(linePrefix);
    }
    if (lastCh === ' ' || lastCh === '\u3000') {
      return WysiwygTriggers.matchTrailingTag(linePrefix);
    }
    return null;
  }

  /** 统计字符串区间内的换行数量。 */
  public static countNewlines(text: string, start: number, end: number): number {
    const safeStart: number = Math.max(0, start);
    const safeEnd: number = Math.min(text.length, end);
    let count: number = 0;
    for (let i: number = safeStart; i < safeEnd; i++) {
      if (text.charAt(i) === '\n') {
        count++;
      }
    }
    return count;
  }

  /** 获取第 lineIndex 行（0 起）的 `[start, end]` 闭开区间（不含 `\n`）。 */
  public static lineRange(text: string, lineIndex: number): [number, number] {
    let current: number = 0;
    let start: number = 0;
    const len: number = text.length;
    while (current < lineIndex && start <= len) {
      const nl: number = text.indexOf('\n', start);
      if (nl < 0) {
        return [len, len];
      }
      start = nl + 1;
      current++;
    }
    const nl: number = text.indexOf('\n', start);
    const end: number = nl < 0 ? len : nl;
    return [start, end];
  }

  private static matchSymmetricPair(text: string, marker: string, italic: boolean, bold: boolean,
    code: boolean, strike: boolean, highlight: boolean): InlineTriggerResult | null {
    const mLen: number = marker.length;
    if (!text.endsWith(marker) || text.length <= mLen * 2) {
      return null;
    }
    const closeStart: number = text.length - mLen;
    let searchFrom: number = closeStart - 1;
    while (searchFrom >= mLen - 1) {
      const openPos: number = text.lastIndexOf(marker, searchFrom - (mLen - 1));
      if (openPos < 0) {
        return null;
      }
      const inner: string = text.substring(openPos + mLen, closeStart);
      if (inner.length > 0 && !inner.includes('\n') && inner.trim().length > 0) {
        const res: InlineTriggerResult = new InlineTriggerResult();
        res.startOffset = openPos;
        res.endOffset = text.length;
        res.text = inner;
        res.bold = bold;
        res.italic = italic;
        res.strike = strike;
        res.highlight = highlight;
        res.code = code;
        return res;
      }
      searchFrom = openPos - 1;
    }
    return null;
  }

  /** 匹配单星号 `*斜体*`（严格避开 `**` 加粗前后缀）。 */
  private static matchSingleAsteriskItalic(text: string): InlineTriggerResult | null {
    if (text.length < 3 || !text.endsWith('*')) {
      return null;
    }
    if (text.charAt(text.length - 2) === '*') {
      return null;
    }
    const closePos: number = text.length - 1;
    for (let i: number = closePos - 1; i >= 0; i--) {
      if (text.charAt(i) !== '*') {
        continue;
      }
      const prevIsStar: boolean = i > 0 && text.charAt(i - 1) === '*';
      const nextIsStar: boolean = i + 1 < closePos && text.charAt(i + 1) === '*';
      if (prevIsStar || nextIsStar) {
        return null;
      }
      const inner: string = text.substring(i + 1, closePos);
      if (inner.length > 0 && inner.trim().length > 0 && !inner.startsWith(' ') && !inner.endsWith(' ')) {
        const res: InlineTriggerResult = new InlineTriggerResult();
        res.startOffset = i;
        res.endOffset = text.length;
        res.text = inner;
        res.italic = true;
        return res;
      }
      return null;
    }
    return null;
  }

  private static matchSingleBacktickCode(text: string): InlineTriggerResult | null {
    if (!text.endsWith('`') || text.endsWith('``')) {
      return null;
    }
    const closePos: number = text.length - 1;
    const openPos: number = text.lastIndexOf('`', closePos - 1);
    if (openPos < 0) {
      return null;
    }
    if (openPos > 0 && text.charAt(openPos - 1) === '`') {
      return null;
    }
    const inner: string = text.substring(openPos + 1, closePos);
    if (inner.length === 0 || inner.includes('\n')) {
      return null;
    }
    const res: InlineTriggerResult = new InlineTriggerResult();
    res.startOffset = openPos;
    res.endOffset = text.length;
    res.text = inner;
    res.code = true;
    return res;
  }

  private static matchWikiLinkSuffix(text: string): InlineTriggerResult | null {
    if (!text.endsWith(']]')) {
      return null;
    }
    const closePos: number = text.length - 2;
    const openPos: number = text.lastIndexOf('[[', closePos - 1);
    if (openPos < 0) {
      return null;
    }
    // `![[...]]` 嵌入保留原样，不转成普通双链。
    if (openPos > 0 && text.charAt(openPos - 1) === '!') {
      return null;
    }
    const inner: string = text.substring(openPos + 2, closePos).trim();
    if (inner.length === 0 || inner.includes('\n') || inner.includes(']]')) {
      return null;
    }
    const pipe: number = inner.indexOf('|');
    const display: string = pipe >= 0 && inner.substring(pipe + 1).trim().length > 0
      ? inner.substring(pipe + 1).trim()
      : inner;
    const res: InlineTriggerResult = new InlineTriggerResult();
    res.startOffset = openPos;
    res.endOffset = text.length;
    res.text = display;
    res.kind = WysiwygSpanKind.WIKI_LINK;
    res.target = inner;
    return res;
  }

  private static matchMdLinkSuffix(text: string): InlineTriggerResult | null {
    const match: RegExpExecArray | null = /\[([^\[\]]+)\]\(([^()\s]+)\)$/.exec(text);
    if (match === null) {
      return null;
    }
    const startOffset: number = text.length - match[0].length;
    if (startOffset > 0 && text.charAt(startOffset - 1) === '!') {
      return null;
    }
    const res: InlineTriggerResult = new InlineTriggerResult();
    res.startOffset = startOffset;
    res.endOffset = text.length;
    res.text = match[1];
    res.kind = WysiwygSpanKind.MD_LINK;
    res.target = match[2];
    return res;
  }

  private static matchTrailingTag(text: string): InlineTriggerResult | null {
    const match: RegExpExecArray | null = /(?:^|[\s\u3000])(#([^\s#]+))([\s\u3000])$/.exec(text);
    if (match === null) {
      return null;
    }
    const body: string = match[2];
    if (/^\d+$/.test(body) || /^[0-9A-Fa-f]{3}([0-9A-Fa-f]{3}|[0-9A-Fa-f]{5})?$/.test(body)) {
      return null;
    }
    const fullTag: string = match[1];
    const space: string = match[3];
    const tagStart: number = text.length - fullTag.length - space.length;
    const res: InlineTriggerResult = new InlineTriggerResult();
    res.startOffset = tagStart;
    res.endOffset = text.length;
    res.text = fullTag;
    res.kind = WysiwygSpanKind.TAG;
    res.target = body;
    res.trailingChar = space;
    return res;
  }
}
