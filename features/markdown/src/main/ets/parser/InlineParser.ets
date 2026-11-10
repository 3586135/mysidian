import { MdInline, MdInlineType } from '@ohos/domain';

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
    return this.parseRange(text, 0, text.length);
  }

  private parseRange(text: string, start: number, end: number): MdInline[] {
    const nodes: MdInline[] = [];
    let buffer: string = '';
    let index: number = start;

    while (index < end) {
      const ch: string = text.charAt(index);

      if (ch === '\\' && index + 1 < end) {
        buffer += text.charAt(index + 1);
        index += 2;
        continue;
      }

      if (ch === '`') {
        const close: number = this.findCodeEnd(text, index, end);
        if (close > index) {
          this.flush(nodes, buffer);
          buffer = '';
          const node: MdInline = new MdInline();
          node.type = MdInlineType.INLINE_CODE;
          node.text = text.substring(index + 1, close);
          nodes.push(node);
          index = close + 1;
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
        const image: InlineParseResult | null = this.parseBracket(text, index, end, true);
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
        const link: InlineParseResult | null = this.parseBracket(text, index, end, false);
        if (link !== null) {
          this.flush(nodes, buffer);
          buffer = '';
          nodes.push(link.node);
          index = link.next;
          continue;
        }
      }

      if (ch === '*' || ch === '_') {
        const emphasis: InlineParseResult | null = this.parseEmphasis(text, index, end, ch);
        if (emphasis !== null) {
          this.flush(nodes, buffer);
          buffer = '';
          nodes.push(emphasis.node);
          index = emphasis.next;
          continue;
        }
      }

      if (ch === '~' && index + 1 < end && text.charAt(index + 1) === '~') {
        const close: number = text.indexOf('~~', index + 2);
        if (close > index && close < end) {
          this.flush(nodes, buffer);
          buffer = '';
          const node: MdInline = new MdInline();
          node.type = MdInlineType.STRIKETHROUGH;
          node.children = this.parseRange(text, index + 2, close);
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
        if (tagEnd > index + 1) {
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
    const isEmbed: boolean = start > 0 && text.charAt(start - 1) === '!';
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
  private parseBracket(text: string, start: number, end: number, isImage: boolean):
    InlineParseResult | null {
    let depth: number = 0;
    let close: number = -1;
    let index: number = start;
    while (index < end) {
      const ch: string = text.charAt(index);
      if (ch === '\\') {
        index += 2;
        continue;
      }
      if (ch === '[') {
        depth++;
      } else if (ch === ']') {
        depth--;
        if (depth === 0) {
          close = index;
          break;
        }
      }
      index++;
    }
    if (close < 0 || close + 1 >= end || text.charAt(close + 1) !== '(') {
      return null;
    }
    const urlEnd: number = text.indexOf(')', close + 2);
    if (urlEnd < 0 || urlEnd >= end) {
      return null;
    }
    const result: InlineParseResult = new InlineParseResult();
    const node: MdInline = new MdInline();
    const label: string = text.substring(start + 1, close);
    if (isImage) {
      node.type = MdInlineType.IMAGE;
      node.text = label;
      node.url = text.substring(close + 2, urlEnd).trim();
    } else {
      node.type = MdInlineType.LINK;
      node.url = text.substring(close + 2, urlEnd).trim();
      node.children = this.parseRange(text, start + 1, close);
    }
    result.node = node;
    result.next = urlEnd + 1;
    return result;
  }

  /** 解析 *斜体* / **粗体** / ***粗斜体*** / _斜体_ / __粗体__。 */
  private parseEmphasis(text: string, start: number, end: number, marker: string):
    InlineParseResult | null {
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
    const close: number = this.findMarkerEnd(text, contentStart, end, marker, runLength);
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
      inner.children = this.parseRange(text, contentStart, close);
      node.children.push(inner);
    } else {
      node.type = runLength === 2 ? MdInlineType.STRONG : MdInlineType.EMPHASIS;
      node.children = this.parseRange(text, contentStart, close);
    }
    result.node = node;
    result.next = close + runLength;
    return result;
  }

  /** 查找成对强调标记的结束位置。 */
  private findMarkerEnd(text: string, start: number, end: number, marker: string,
    markerLength: number): number {
    let index: number = start;
    while (index < end) {
      const ch: string = text.charAt(index);
      if (ch === '\\') {
        index += 2;
        continue;
      }
      if (ch === '`') {
        const codeEnd: number = this.findCodeEnd(text, index, end);
        if (codeEnd > index) {
          index = codeEnd + 1;
          continue;
        }
      }
      if (ch === marker && this.markerMatches(text, index, end, marker, markerLength)) {
        return index;
      }
      index++;
    }
    return -1;
  }

  private markerMatches(text: string, index: number, end: number, marker: string,
    markerLength: number): boolean {
    if (index + markerLength > end) {
      return false;
    }
    for (let offset: number = 0; offset < markerLength; offset++) {
      if (text.charAt(index + offset) !== marker) {
        return false;
      }
    }
    return true;
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
    if (ch.length === 0) {
      return false;
    }
    const code: number = ch.charCodeAt(0);
    if (code > 0x2E80) {
      return true;
    }
    return this.isWordChar(ch) || ch === '-' || ch === '/';
  }

  private isWordChar(ch: string): boolean {
    if (ch.length === 0) {
      return false;
    }
    const code: number = ch.charCodeAt(0);
    return (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }
}
