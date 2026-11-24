import { MdInline, MdInlineType } from '@ohos/domain';
import { TagRules } from './TagRules';

/** 行内解析结果（节点 + 解析结束位置）。 */
export class InlineParseResult {
  node: MdInline = new MdInline();
  next: number = 0;
}

/**
 * 行内解析器：处理强调、删除线、行内代码、wiki 链接、嵌入、标签、
 * markdown 链接、图片、行内数学与 HTML。
 */
export class InlineParser {
  /** 解析一段文本为行内节点列表。 */
  public parse(text: string): MdInline[] {
    return this.parseRange(text, 0, text.length, 0);
  }

  private parseRange(text: string, start: number, end: number, depth: number): MdInline[] {
    if (depth > 32) {
      const capped: MdInline[] = [];
      if (end > start) {
        const node: MdInline = new MdInline();
        node.type = MdInlineType.TEXT;
        node.text = text.substring(start, end);
        capped.push(node);
      }
      return capped;
    }
    const nodes: MdInline[] = [];
    let buffer: string = '';
    let index: number = start;

    while (index < end) {
      const ch: string = text.charAt(index);

      if (ch === '\\' && index + 1 < end) {
        // 仅 ASCII 标点可被转义（CommonMark 规定）；
        // `\d`、`C:\Users` 等「反斜杠+字母」不是转义，反斜杠原样保留。
        const nextCh: string = text.charAt(index + 1);
        if (this.isEscapablePunctuation(nextCh)) {
          buffer += nextCh;
          index += 2;
          continue;
        }
        buffer += ch;
        index += 1;
        continue;
      }

      if (ch === '`') {
        let openRun: number = 0;
        while (index + openRun < end && text.charAt(index + openRun) === '`') {
          openRun++;
        }
        const close: number = this.findCodeEnd(text, index, end);
        if (close > index) {
          this.flush(nodes, buffer);
          buffer = '';
          const node: MdInline = new MdInline();
          node.type = MdInlineType.INLINE_CODE;
          node.text = text.substring(index + openRun, close);
          nodes.push(node);
          index = close + openRun;
          continue;
        }
      }

      if (ch === '!' && index + 1 < end && text.charAt(index + 1) === '[') {
        const embedded: InlineParseResult | null = this.parseWiki(text, index + 1, end);
        if (embedded !== null) {
          this.flush(nodes, buffer);
          buffer = '';
          nodes.push(embedded.node);
          index = embedded.next;
          continue;
        }
        const image: InlineParseResult | null = this.parseBracket(text, index, end, true, depth);
        if (image !== null) {
          this.flush(nodes, buffer);
          buffer = '';
          nodes.push(image.node);
          index = image.next;
          continue;
        }
      }

      if (ch === '[' && index + 1 < end && text.charAt(index + 1) === '[') {
        const wiki: InlineParseResult | null = this.parseWiki(text, index, end);
        if (wiki !== null) {
          this.flush(nodes, buffer);
          buffer = '';
          nodes.push(wiki.node);
          index = wiki.next;
          continue;
        }
      }

      if (ch === '[') {
        const link: InlineParseResult | null = this.parseBracket(text, index, end, false, depth);
        if (link !== null) {
          this.flush(nodes, buffer);
          buffer = '';
          nodes.push(link.node);
          index = link.next;
          continue;
        }
      }

      if (ch === '*' || ch === '_') {
        const emphasis: InlineParseResult | null = this.parseEmphasis(text, index, end, ch, depth);
        if (emphasis !== null) {
          this.flush(nodes, buffer);
          buffer = '';
          nodes.push(emphasis.node);
          index = emphasis.next;
          continue;
        }
      }

      if (ch === '~' && index + 1 < end && text.charAt(index + 1) === '~') {
        // 删除线：~~文本~~（内容不得为空，避免 "~~~~" 被整体吞掉）
        const close: number = text.indexOf('~~', index + 2);
        if (close > index + 2 && close < end) {
          this.flush(nodes, buffer);
          buffer = '';
          const node: MdInline = new MdInline();
          node.type = MdInlineType.STRIKETHROUGH;
          node.children = this.parseRange(text, index + 2, close, depth + 1);
          nodes.push(node);
          index = close + 2;
          continue;
        }
      }

      if (ch === '=' && index + 1 < end && text.charAt(index + 1) === '=') {
        // 高亮：==文本==（内容不得为空，避免 "====" 被整体吞掉）
        const close: number = text.indexOf('==', index + 2);
        if (close >= index + 3 && close < end) {
          this.flush(nodes, buffer);
          buffer = '';
          const node: MdInline = new MdInline();
          node.type = MdInlineType.HIGHLIGHT;
          node.children = this.parseRange(text, index + 2, close, depth + 1);
          nodes.push(node);
          index = close + 2;
          continue;
        }
      }

      if (ch === '$') {
        const close: number = text.indexOf('$', index + 1);
        if (close > index + 1 && close < end) {
          const body: string = text.substring(index + 1, close);
          if (body.trim().length > 0 && !body.startsWith(' ') && !body.endsWith(' ')) {
            this.flush(nodes, buffer);
            buffer = '';
            const node: MdInline = new MdInline();
            node.type = MdInlineType.MATH;
            node.text = body;
            nodes.push(node);
            index = close + 1;
            continue;
          }
        }
      }

      if (ch === '#' && this.isTagStart(text, index, end)) {
        const tagEnd: number = this.findTagEnd(text, index, end);
        if (tagEnd > index + 1 && this.isTagBody(text.substring(index + 1, tagEnd))) {
          this.flush(nodes, buffer);
          buffer = '';
          const node: MdInline = new MdInline();
          node.type = MdInlineType.TAG;
          node.text = text.substring(index + 1, tagEnd);
          nodes.push(node);
          index = tagEnd;
          continue;
        }
      }

      buffer += ch;
      index += 1;
    }

    this.flush(nodes, buffer);
    return nodes;
  }

  private flush(nodes: MdInline[], buffer: string): void {
    if (buffer.length === 0) {
      return;
    }
    const node: MdInline = new MdInline();
    node.type = MdInlineType.TEXT;
    node.text = buffer;
    nodes.push(node);
  }

  /** 解析 [[目标|别名#标题^块]] 与 ![[嵌入]]。 */
  private parseWiki(text: string, start: number, end: number): InlineParseResult | null {
    const close: number = text.indexOf(']]', start + 2);
    if (close < 0 || close + 2 > end) {
      return null;
    }
    const content: string = text.substring(start + 2, close);
    if (content.length === 0) {
      return null;
    }
    const result: InlineParseResult = new InlineParseResult();
    const node: MdInline = new MdInline();
    // 前置 `!` 须是真实未转义的 `!`：`\![[x]]` 的 `!` 来自转义（字面量），
    // 后随 `[[x]]` 应按 wiki 链接解析而非嵌入（序列化侧 escapePlainRun 依赖此语义）。
    const isEmbed: boolean = start > 0 && text.charAt(start - 1) === '!' &&
      !this.isCharEscaped(text, start - 1);
    node.type = isEmbed ? MdInlineType.EMBED : MdInlineType.WIKI_LINK;

    const pipe: number = content.indexOf('|');
    let targetPart: string = content;
    if (pipe >= 0) {
      targetPart = content.substring(0, pipe);
      node.alias = content.substring(pipe + 1).trim();
    }

    const hash: number = targetPart.indexOf('#');
    if (hash >= 0) {
      node.heading = targetPart.substring(hash + 1).trim();
      targetPart = targetPart.substring(0, hash);
    }
    const caret: number = targetPart.indexOf('^');
    if (caret >= 0) {
      node.blockRef = targetPart.substring(caret + 1).trim();
      targetPart = targetPart.substring(0, caret);
    }
    node.target = targetPart.trim();
    // 本页锚点 [[#标题]] 的 target 为空，此时以标题文本作为显示名。
    node.text = node.alias.length > 0 ? node.alias
      : (node.target.length > 0 ? node.target : node.heading);

    result.node = node;
    result.next = close + 2;
    return result;
  }

  /** 解析 [文本](链接) 与 ![说明](图片)。 */
  private parseBracket(text: string, start: number, end: number, isImage: boolean,
    depth: number): InlineParseResult | null {
    let bracketDepth: number = 0;
    let close: number = -1;
    let index: number = start;
    while (index < end) {
      const ch: string = text.charAt(index);
      if (ch === '\\') {
        index += 2;
        continue;
      }
      if (ch === '[') {
        bracketDepth++;
      } else if (ch === ']') {
        bracketDepth--;
        if (bracketDepth === 0) {
          close = index;
          break;
        }
      }
      index++;
    }
    if (close < 0 || close + 1 >= end || text.charAt(close + 1) !== '(') {
      return null;
    }
    // URL 结尾按括号深度扫描：URL 内成对的括号（维基百科链接常见）
    // 不能在第一个 ')' 处截断。
    const urlEnd: number = this.findUrlEnd(text, close + 2, end);
    if (urlEnd < 0) {
      return null;
    }
    const result: InlineParseResult = new InlineParseResult();
    const node: MdInline = new MdInline();
    // IMAGE 时 start 指向 '!'，label 应从其后第 2 位起（否则 alt 会带上多余的 '['）。
    const label: string = text.substring(start + (isImage ? 2 : 1), close);
    if (isImage) {
      node.type = MdInlineType.IMAGE;
      node.text = label;
      node.url = text.substring(close + 2, urlEnd).trim();
    } else {
      node.type = MdInlineType.LINK;
      // label 原文存入 text：flattener（阅读视图）与 WysiwygCodec（编辑器往返）都读它。
      node.text = label;
      node.url = text.substring(close + 2, urlEnd).trim();
      node.children = this.parseRange(text, start + 1, close, depth + 1);
    }
    result.node = node;
    result.next = urlEnd + 1;
    return result;
  }

  /** 解析 *斜体* / **粗体** / ***粗斜体*** / _斜体_ / __粗体__。 */
  private parseEmphasis(text: string, start: number, end: number, marker: string,
    depth: number): InlineParseResult | null {
    if (marker === '_') {
      const previous: string = start > 0 ? text.charAt(start - 1) : ' ';
      if (this.isWordChar(previous)) {
        return null;
      }
    }
    let runLength: number = 0;
    while (start + runLength < end && text.charAt(start + runLength) === marker) {
      runLength++;
    }
    if (runLength > 3) {
      return null;
    }
    const contentStart: number = start + runLength;
    if (contentStart >= end || text.charAt(contentStart) === ' ' || text.charAt(contentStart) === '\n') {
      return null;
    }
    const close: number = this.findMarkerEnd(text, contentStart, end, marker, runLength, depth);
    if (close <= contentStart || close > end) {
      return null;
    }
    if (text.charAt(close - 1) === ' ' || text.charAt(close - 1) === '\n') {
      return null;
    }
    const result: InlineParseResult = new InlineParseResult();
    const node: MdInline = new MdInline();
    if (runLength === 3) {
      node.type = MdInlineType.STRONG;
      const inner: MdInline = new MdInline();
      inner.type = MdInlineType.EMPHASIS;
      inner.children = this.parseRange(text, contentStart, close, depth + 1);
      node.children.push(inner);
    } else {
      node.type = runLength === 2 ? MdInlineType.STRONG : MdInlineType.EMPHASIS;
      node.children = this.parseRange(text, contentStart, close, depth + 1);
    }
    result.node = node;
    result.next = close + runLength;
    return result;
  }

  /**
   * 查找成对强调标记的结束位置。
   * 候选闭合需满足：run 长度 >= 开串长度、前字符非空白（右侧翼）；
   * '_' 额外要求后继非字母数字（CommonMark 词内下划线 _snake_case_ 不成强调）。
   * 不可闭合时尝试按嵌套强调解析内层（如 *a **b** c*），成功则跳过继续找外层闭合。
   */
  private findMarkerEnd(text: string, start: number, end: number, marker: string,
    markerLength: number, depth: number): number {
    let index: number = start;
    while (index < end) {
      const ch: string = text.charAt(index);
      if (ch === '\\') {
        index += 2;
        continue;
      }
      if (ch === '`') {
        let run: number = 0;
        while (index + run < end && text.charAt(index + run) === '`') {
          run++;
        }
        const codeEnd: number = this.findCodeEnd(text, index, end);
        if (codeEnd > index) {
          index = codeEnd + run;
          continue;
        }
        index += run;
        continue;
      }
      if (ch === marker) {
        let run: number = 0;
        while (index + run < end && text.charAt(index + run) === marker) {
          run++;
        }
        const prev: string = index > 0 ? text.charAt(index - 1) : ' ';
        const next: string = index + run < end ? text.charAt(index + run) : '';
        const intrawordUnderscore: boolean = marker === '_' && this.isWordChar(next);
        if (run >= markerLength && prev !== ' ' && prev !== '\n' && prev !== '\t' && !intrawordUnderscore) {
          return index;
        }
        if (depth < 16) {
          const inner: InlineParseResult | null = this.parseEmphasis(text, index, end, marker, depth + 1);
          if (inner !== null) {
            index = inner.next;
            continue;
          }
        }
        index += run;
        continue;
      }
      index++;
    }
    return -1;
  }

  /** 查找行内代码结束位置（返回结束反引号索引）。 */
  private findCodeEnd(text: string, start: number, end: number): number {
    let runLength: number = 0;
    let index: number = start;
    while (index < end && text.charAt(index) === '`') {
      runLength++;
      index++;
    }
    let scan: number = index;
    while (scan < end) {
      if (text.charAt(scan) === '`') {
        let count: number = 0;
        while (scan < end && text.charAt(scan) === '`') {
          count++;
          scan++;
        }
        if (count === runLength) {
          return scan - runLength;
        }
      } else {
        scan++;
      }
    }
    return -1;
  }

  private isTagStart(text: string, index: number, end: number): boolean {
    if (index > 0) {
      const previous: string = text.charAt(index - 1);
      if (this.isWordChar(previous)) {
        return false;
      }
    }
    if (index + 1 >= end) {
      return false;
    }
    const next: string = text.charAt(index + 1);
    if (next === ' ' || next === '#') {
      return false;
    }
    return true;
  }

  private findTagEnd(text: string, index: number, end: number): number {
    let scan: number = index + 1;
    while (scan < end) {
      const ch: string = text.charAt(scan);
      if (this.isTagChar(ch)) {
        scan++;
        continue;
      }
      break;
    }
    return scan;
  }

  private isTagChar(ch: string): boolean {
    return TagRules.isTagChar(ch);
  }

  /**
   * 标签体合法性（TagRules 单源）：纯数字（#2026）与十六进制色值（#FFF、#1A1A2E、#FFFFFF80）
   * 不是标签——设计文档令牌表里的颜色值是最常见的误报来源。
   */
  private isTagBody(body: string): boolean {
    return TagRules.isTagBody(body);
  }

  private isWordChar(ch: string): boolean {
    if (ch.length === 0) {
      return false;
    }
    const code: number = ch.charCodeAt(0);
    return (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }

  /** 是否为可转义的 ASCII 标点（CommonMark 转义仅对标点生效）。 */
  private isEscapablePunctuation(ch: string): boolean {
    if (ch.length === 0) {
      return false;
    }
    const code: number = ch.charCodeAt(0);
    return (code >= 33 && code <= 47) || (code >= 58 && code <= 64) ||
      (code >= 91 && code <= 96) || (code >= 123 && code <= 126);
  }

  /**
   * index 处字符是否被转义：紧邻前导反斜杠为奇数个（\! 的 ! 已转义；
   * \\! 的 ! 未转义——前两个反斜杠互相抵消）。按奇偶计数而非只看前一位，
   * 否则 `\\\!` 这类「转义反斜杠 + 转义感叹号」会被误判。
   */
  private isCharEscaped(text: string, index: number): boolean {
    let count: number = 0;
    let scan: number = index - 1;
    while (scan >= 0 && text.charAt(scan) === '\\') {
      count++;
      scan--;
    }
    return count % 2 === 1;
  }

  /** URL 结尾位置：括号深度计数，容忍 URL 内成对括号，遇未配对 ')' 收尾。 */
  private findUrlEnd(text: string, start: number, end: number): number {
    let depth: number = 0;
    let index: number = start;
    while (index < end) {
      const ch: string = text.charAt(index);
      if (ch === '(') {
        depth++;
      } else if (ch === ')') {
        if (depth === 0) {
          return index;
        }
        depth--;
      } else if (ch === ' ' || ch === '\n' || ch === '\t') {
        // URL 不允许包含空白：视为未闭合，不按链接解析。
        return -1;
      }
      index++;
    }
    return -1;
  }
}
