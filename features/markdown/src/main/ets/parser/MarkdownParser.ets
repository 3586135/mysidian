import { MdBlockType, MdDocument, MdInline } from '@ohos/domain';
import { BlockParser } from './BlockParser';
import { FrontmatterParser, FrontmatterResult } from './FrontmatterParser';

/**
 * Markdown 解析入口：frontmatter + 块级结构。
 */
export class MarkdownParser {
  /** 解析整篇 Markdown 文本。 */
  public static parse(text: string): MdDocument {
    const normalized: string = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    const lines: string[] = normalized.split('\n');
    const frontmatter: FrontmatterResult = FrontmatterParser.parse(lines);
    // startLine 传入 frontmatter 行数，使列表项记录的行号与原文对齐。
    const blocks = new BlockParser().parse(lines.slice(frontmatter.consumed), frontmatter.consumed);
    const document: MdDocument = new MdDocument();
    document.frontmatter = frontmatter.frontmatter;
    document.blocks = blocks;
    document.title = MarkdownParser.resolveTitle(document);
    return document;
  }

  private static resolveTitle(document: MdDocument): string {
    for (const property of document.frontmatter.properties) {
      if (property.key.toLowerCase() === 'title' && property.value.length > 0) {
        return property.value;
      }
    }
    for (const block of document.blocks) {
      if (block.type === MdBlockType.HEADING && block.inlines.length > 0) {
        return MarkdownParser.plainText(block.inlines);
      }
    }
    return '';
  }

  private static plainText(inlines: MdInline[]): string {
    let result: string = '';
    for (const inline of inlines) {
      if (inline.children.length > 0) {
        result += MarkdownParser.plainText(inline.children);
      } else {
        result += inline.text;
      }
    }
    return result.trim();
  }
}
