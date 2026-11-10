import { MdBlock, MdBlockType, MdInline, MdListItem } from '@ohos/domain';
import { InlineParser } from './InlineParser';
import { TaskMetadata } from './TaskMetadata';

/** 块解析结果（块 + 消费到的行号）。 */
export class BlockParseResult {
  block: MdBlock = new MdBlock();
  next: number = 0;
}

/**
 * 块级 Markdown 解析器：标题、段落、列表、代码块、引用、Callout、
 * 表格、分隔线、HTML 块与数学块。
 */
export class BlockParser {
  private readonly inlineParser: InlineParser = new InlineParser();

  public parse(lines: string[]): MdBlock[] {
    const blocks: MdBlock[] = [];
    let index: number = 0;
    while (index < lines.length) {
      const raw: string = lines[index];
      const trimmed: string = raw.trim();
      if (trimmed.length === 0) {
        index++;
        continue;
      }
      if (this.isFence(trimmed)) {
        const result: BlockParseResult = this.parseFencedCode(lines, index);
        blocks.push(result.block);
        index = result.next;
        continue;
      }
      const media: RegExpExecArray | null = /^!\[\[([^\]]+)\]\]$/.exec(trimmed);
      if (media !== null) {
        blocks.push(BlockParser.parseMediaBlock(media[1]));
        index++;
        continue;
      }
      const mdImage: RegExpExecArray | null = /^!\[[^\]]*\]\(([^)]+)\)$/.exec(trimmed);
      if (mdImage !== null) {
        blocks.push(BlockParser.parseMediaBlock(mdImage[1]));
        index++;
        continue;
      }
      const heading: RegExpExecArray | null = /^#{1,6}\s+(.*)$/.exec(trimmed);
      if (heading !== null) {
        const block: MdBlock = new MdBlock();
        block.type = MdBlockType.HEADING;
        block.level = trimmed.substring(0, trimmed.indexOf(' ')).length;
        block.inlines = this.inlineParser.parse(heading[1].trim());
        blocks.push(block);
        index++;
        continue;
      }
      if (this.isThematicBreak(trimmed)) {
        const block: MdBlock = new MdBlock();
        block.type = MdBlockType.THEMATIC_BREAK;
        blocks.push(block);
        index++;
        continue;
      }
      if (trimmed.startsWith('>')) {
        const result: BlockParseResult = this.parseQuote(lines, index);
        blocks.push(result.block);
        index = result.next;
        continue;
      }
      if (this.isListItem(trimmed)) {
        const result: BlockParseResult = this.parseList(lines, index);
        blocks.push(result.block);
        index = result.next;
        continue;
      }
      if (trimmed.startsWith('$$')) {
        const result: BlockParseResult = this.parseMath(lines, index);
        blocks.push(result.block);
        index = result.next;
        continue;
      }
      if (trimmed.startsWith('<')) {
        const result: BlockParseResult = this.parseHtml(lines, index);
        blocks.push(result.block);
        index = result.next;
        continue;
      }
      if (trimmed.includes('|') && this.isTableDelimiter(this.nextNonEmptyLine(lines, index + 1))) {
        const result: BlockParseResult = this.parseTable(lines, index);
        blocks.push(result.block);
        index = result.next;
        continue;
      }
      const result: BlockParseResult = this.parseParagraph(lines, index);
      blocks.push(result.block);
      index = result.next;
    }
    return blocks;
  }

  /** 围栏代码块（``` 或 ~~~）。 */
  private parseFencedCode(lines: string[], start: number): BlockParseResult {
    const result: BlockParseResult = new BlockParseResult();
    const block: MdBlock = new MdBlock();
    block.type = MdBlockType.CODE;
    const fence: string = lines[start].trim();
    const fenceChar: string = fence.charAt(0);
    let infoStart: number = 0;
    while (infoStart < fence.length && fence.charAt(infoStart) === fenceChar) {
      infoStart++;
    }
    const fenceLength: number = infoStart;
    const info: string = fence.substring(infoStart).trim();
    block.lang = info.split(' ')[0];
    const body: string[] = [];
    let index: number = start + 1;
    while (index < lines.length) {
      const current: string = lines[index].trim();
      if (current.startsWith(fenceChar) && this.countFenceChars(current, fenceChar) >= fenceLength) {
        index++;
        break;
      }
      body.push(lines[index]);
      index++;
    }
    block.rawContent = body.join('\n');
    result.block = block;
    result.next = index;
    return result;
  }

  /** 引用块与 Callout。 */
  private parseQuote(lines: string[], start: number): BlockParseResult {
    const result: BlockParseResult = new BlockParseResult();
    const block: MdBlock = new MdBlock();
    const body: string[] = [];
    let index: number = start;
    while (index < lines.length) {
      const raw: string = lines[index];
      const trimmed: string = raw.trim();
      if (!trimmed.startsWith('>')) {
        break;
      }
      body.push(trimmed.substring(1).trim());
      index++;
    }
    let content: string = body.join('\n');
    const callout: RegExpExecArray | null =
      /^\[!([A-Za-z]+)\]([+-]?)\s*(.*)$/.exec(body.length > 0 ? body[0] : '');
    if (callout !== null) {
      block.type = MdBlockType.CALLOUT;
      block.calloutType = callout[1].toUpperCase();
      // Obsidian 折叠语法：`> [!NOTE]-` 折叠、`> [!NOTE]+` 展开。
      block.calloutFolded = callout[2] === '-';
      block.calloutTitle = callout[3].trim();
      const rest: string[] = [];
      if (block.calloutTitle.length > 0) {
        rest.push(block.calloutTitle);
      }
      for (let i: number = 1; i < body.length; i++) {
        rest.push(body[i]);
      }
      content = rest.join('\n');
    } else {
      block.type = MdBlockType.QUOTE;
    }
    block.rawContent = content;
    block.inlines = this.inlineParser.parse(content);
    result.block = block;
    result.next = index;
    return result;
  }

  /** 列表（有序 / 无序 / 任务列表）。 */
  private parseList(lines: string[], start: number): BlockParseResult {
    const result: BlockParseResult = new BlockParseResult();
    const block: MdBlock = new MdBlock();
    block.type = MdBlockType.LIST;
    let index: number = start;
    let baseIndent: number = -1;
    while (index < lines.length) {
      const raw: string = lines[index];
      const trimmed: string = raw.trim();
      if (trimmed.length === 0) {
        const peek: number = this.nextNonEmptyIndex(lines, index + 1);
        if (peek >= 0 && this.isListItem(lines[peek].trim())) {
          index = peek;
          continue;
        }
        break;
      }
      const match: RegExpExecArray | null = /^([-*+]|\d+[.)])\s+(.*)$/.exec(trimmed);
      if (match === null) {
        break;
      }
      const indent: number = raw.length - raw.trimStart().length;
      if (baseIndent < 0) {
        baseIndent = indent;
        block.ordered = /\d/.test(match[1]);
      }
      if (indent > baseIndent) {
        const nested: BlockParseResult = this.parseList(lines, index);
        if (block.items.length > 0) {
          const parent: MdListItem = block.items[block.items.length - 1];
          for (const child of nested.block.items) {
            parent.children.push(child);
          }
        }
        index = nested.next;
        continue;
      }
      if (indent < baseIndent) {
        break;
      }
      const item: MdListItem = new MdListItem();
      item.ordinal = block.items.length + 1;
      item.rawLine = raw;
      let content: string = match[2];
      if (content.startsWith('[ ] ') || content.startsWith('[x] ') || content.startsWith('[X] ')) {
        item.isTask = true;
        item.checked = content.charAt(1) === 'x' || content.charAt(1) === 'X';
        content = content.substring(4);
        content = TaskMetadata.apply(item, content);
      }
      item.inlines = this.inlineParser.parse(content);
      block.items.push(item);
      index++;
    }
    result.block = block;
    result.next = index;
    return result;
  }

  /** 数学块 $$ ... $$。 */
  private parseMath(lines: string[], start: number): BlockParseResult {
    const result: BlockParseResult = new BlockParseResult();
    const block: MdBlock = new MdBlock();
    block.type = MdBlockType.MATH;
    const body: string[] = [];
    let index: number = start;
    const first: string = lines[start].trim();
    if (first.length > 2 && first.endsWith('$$')) {
      block.rawContent = first.substring(2, first.length - 2).trim();
      result.block = block;
      result.next = index + 1;
      return result;
    }
    index++;
    while (index < lines.length) {
      const current: string = lines[index].trim();
      if (current.endsWith('$$')) {
        body.push(current.substring(0, current.length - 2));
        index++;
        break;
      }
      body.push(lines[index]);
      index++;
    }
    block.rawContent = body.join('\n').trim();
    result.block = block;
    result.next = index;
    return result;
  }

  /** HTML 块。 */
  private parseHtml(lines: string[], start: number): BlockParseResult {
    const result: BlockParseResult = new BlockParseResult();
    const block: MdBlock = new MdBlock();
    block.type = MdBlockType.HTML;
    const body: string[] = [];
    let index: number = start;
    while (index < lines.length && lines[index].trim().length > 0) {
      body.push(lines[index]);
      index++;
    }
    block.rawContent = body.join('\n');
    result.block = block;
    result.next = index;
    return result;
  }

  /** GFM 表格。 */
  private parseTable(lines: string[], start: number): BlockParseResult {
    const result: BlockParseResult = new BlockParseResult();
    const block: MdBlock = new MdBlock();
    block.type = MdBlockType.TABLE;
    block.headers = this.splitTableRow(lines[start].trim());
    const delimiterIndex: number = this.nextNonEmptyIndex(lines, start + 1);
    block.aligns = this.parseTableAligns(delimiterIndex >= 0 ? lines[delimiterIndex].trim() : '');
    let index: number = delimiterIndex + 1;
    while (index < lines.length) {
      const trimmed: string = lines[index].trim();
      if (trimmed.length === 0 || !trimmed.includes('|')) {
        break;
      }
      block.rows.push(this.splitTableRow(trimmed));
      index++;
    }
    result.block = block;
    result.next = index;
    return result;
  }

  /** 段落（含 Setext 标题识别）。 */
  private parseParagraph(lines: string[], start: number): BlockParseResult {
    const result: BlockParseResult = new BlockParseResult();
    const block: MdBlock = new MdBlock();
    const body: string[] = [];
    let index: number = start;
    while (index < lines.length) {
      const trimmed: string = lines[index].trim();
      if (trimmed.length === 0) {
        break;
      }
      if (body.length > 0 && (trimmed === '===' || trimmed === '---')) {
        const heading: MdBlock = new MdBlock();
        heading.type = MdBlockType.HEADING;
        heading.level = trimmed === '===' ? 1 : 2;
        heading.inlines = this.inlineParser.parse(body.join(' '));
        result.block = heading;
        result.next = index + 1;
        return result;
      }
      if (body.length > 0 && this.isBlockStart(trimmed)) {
        break;
      }
      body.push(trimmed);
      index++;
    }
    block.type = MdBlockType.PARAGRAPH;
    block.inlines = this.inlineParser.parse(body.join('\n'));
    block.rawContent = body.join('\n');
    result.block = block;
    result.next = index;
    return result;
  }

  private isBlockStart(trimmed: string): boolean {
    if (this.isFence(trimmed) || this.isThematicBreak(trimmed)) {
      return true;
    }
    if (trimmed.startsWith('>') || trimmed.startsWith('#') || trimmed.startsWith('$$')) {
      return true;
    }
    if (trimmed.startsWith('<')) {
      return true;
    }
    if (this.isListItem(trimmed)) {
      return true;
    }
    if (trimmed.startsWith('!')) {
      return BlockParser.isMediaLine(trimmed);
    }
    return false;
  }

  /** 是否为独占一行的图片 / 嵌入写法。 */
  private static isMediaLine(trimmed: string): boolean {
    return /^!\[\[[^\]]+\]\]$/.test(trimmed) || /^!\[[^\]]*\]\([^)]+\)$/.test(trimmed);
  }

  /**
   * 解析独占一行的图片 / 嵌入块：![[x.png]] / ![[笔记]] / ![说明](路径)。
   * 图片按扩展名判定；其余 wiki 目标视为笔记嵌入。
   */
  private static parseMediaBlock(spec: string): MdBlock {
    const block: MdBlock = new MdBlock();
    let target: string = spec.trim();
    let alias: string = '';
    const pipe: number = target.indexOf('|');
    if (pipe >= 0) {
      alias = target.substring(pipe + 1).trim();
      target = target.substring(0, pipe).trim();
    }
    block.target = target;
    block.alt = alias;
    if (!BlockParser.isImageTarget(target)) {
      block.type = MdBlockType.EMBED;
      return block;
    }
    block.type = MdBlockType.IMAGE;
    // Obsidian 风格 ![[x.png|300]] 中的数字为像素宽度。
    if (alias.length > 0) {
      const width: number = Number(alias);
      if (!Number.isNaN(width) && width > 0) {
        block.imageWidth = width;
        block.alt = '';
      }
    }
    return block;
  }

  /** 目标是否为图片（按扩展名判定）。 */
  private static isImageTarget(target: string): boolean {
    const lower: string = target.toLowerCase();
    const index: number = lower.lastIndexOf('.');
    if (index < 0) {
      return false;
    }
    const ext: string = lower.substring(index + 1);
    return ext === 'png' || ext === 'jpg' || ext === 'jpeg' || ext === 'gif' ||
      ext === 'webp' || ext === 'bmp' || ext === 'svg';
  }

  private countFenceChars(text: string, fenceChar: string): number {
    let count: number = 0;
    while (count < text.length && text.charAt(count) === fenceChar) {
      count++;
    }
    return count;
  }

  private isFence(trimmed: string): boolean {
    return trimmed.startsWith('```') || trimmed.startsWith('~~~');
  }

  private isThematicBreak(trimmed: string): boolean {
    if (trimmed.length < 3) {
      return false;
    }
    return /^(-\s*){3,}$/.test(trimmed) || /^(\*\s*){3,}$/.test(trimmed) || /^(_\s*){3,}$/.test(trimmed);
  }

  private isListItem(trimmed: string): boolean {
    return /^([-*+]|\d+[.)])\s+/.test(trimmed);
  }

  private isTableDelimiter(trimmed: string): boolean {
    if (trimmed.length === 0 || !trimmed.includes('-')) {
      return false;
    }
    return /^\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?$/.test(trimmed);
  }

  private splitTableRow(line: string): string[] {
    let trimmed: string = line.trim();
    if (trimmed.startsWith('|')) {
      trimmed = trimmed.substring(1);
    }
    if (trimmed.endsWith('|')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    const cells: string[] = [];
    for (const cell of trimmed.split('|')) {
      cells.push(cell.trim());
    }
    return cells;
  }

  private parseTableAligns(delimiter: string): string[] {
    const aligns: string[] = [];
    for (const cell of this.splitTableRow(delimiter)) {
      const left: boolean = cell.startsWith(':');
      const right: boolean = cell.endsWith(':');
      if (left && right) {
        aligns.push('center');
      } else if (right) {
        aligns.push('right');
      } else {
        aligns.push('left');
      }
    }
    return aligns;
  }

  private nextNonEmptyLine(lines: string[], from: number): string {
    const index: number = this.nextNonEmptyIndex(lines, from);
    return index < 0 ? '' : lines[index].trim();
  }

  private nextNonEmptyIndex(lines: string[], from: number): number {
    for (let index: number = from; index < lines.length; index++) {
      if (lines[index].trim().length > 0) {
        return index;
      }
    }
    return -1;
  }
}
