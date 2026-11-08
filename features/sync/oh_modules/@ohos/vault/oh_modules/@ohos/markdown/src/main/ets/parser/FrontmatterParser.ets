import { MdFrontmatter, MdProperty, MdPropType } from '@ohos/domain';

/**
 * YAML frontmatter 解析（Obsidian 常用子集）：
 * 支持 key: value、列表（- item 或 [a, b]）、嵌套 map（以原始文本保留）。
 */
export class FrontmatterParser {
  private static readonly DELIMITER: string = '---';

  /**
   * 解析 frontmatter。
   * @param lines 整篇文档的行
   * @returns frontmatter 与已消费的行数（含分隔行）
   */
  public static parse(lines: string[]): FrontmatterResult {
    const result: FrontmatterResult = new FrontmatterResult();
    if (lines.length === 0 || lines[0].trim() !== FrontmatterParser.DELIMITER) {
      return result;
    }
    let end: number = -1;
    for (let index: number = 1; index < lines.length; index++) {
      if (lines[index].trim() === FrontmatterParser.DELIMITER) {
        end = index;
        break;
      }
    }
    if (end < 0) {
      return result;
    }
    result.consumed = end + 1;
    result.frontmatter = FrontmatterParser.parseBody(lines.slice(1, end));
    return result;
  }

  private static parseBody(lines: string[]): MdFrontmatter {
    const frontmatter: MdFrontmatter = new MdFrontmatter();
    const rawLines: string[] = [];
    let index: number = 0;
    while (index < lines.length) {
      const raw: string = lines[index];
      rawLines.push(raw);
      const trimmed: string = raw.trim();
      if (trimmed.length === 0 || trimmed.startsWith('#')) {
        index++;
        continue;
      }
      if (trimmed.startsWith('- ') || raw.startsWith(' ') || raw.startsWith('\t')) {
        index++;
        continue;
      }
      const separator: number = trimmed.indexOf(':');
      if (separator <= 0) {
        index++;
        continue;
      }
      const key: string = trimmed.substring(0, separator).trim();
      const value: string = trimmed.substring(separator + 1).trim();
      const property: MdProperty = new MdProperty();
      property.key = key;
      if (value.length === 0) {
        property.type = MdPropType.LIST;
        property.listValue = FrontmatterParser.collectListItems(lines, index + 1);
        index = FrontmatterParser.skipListItems(lines, index + 1);
      } else if (value.startsWith('[') && value.endsWith(']')) {
        property.type = MdPropType.LIST;
        property.listValue = FrontmatterParser.splitInlineList(value);
      } else {
        property.type = FrontmatterParser.detectType(value);
        property.value = value;
      }
      frontmatter.properties.push(property);
      if (key.toLowerCase() === 'tags') {
        if (property.type === MdPropType.LIST) {
          for (const tag of property.listValue) {
            frontmatter.tags.push(tag);
          }
        } else if (property.value.length > 0) {
          frontmatter.tags.push(property.value);
        }
      }
      index++;
    }
    frontmatter.raw = rawLines.join('\n');
    return frontmatter;
  }

  private static collectListItems(lines: string[], start: number): string[] {
    const items: string[] = [];
    let index: number = start;
    while (index < lines.length) {
      const raw: string = lines[index];
      const trimmed: string = raw.trim();
      if (trimmed.length === 0) {
        break;
      }
      if (!trimmed.startsWith('- ')) {
        break;
      }
      items.push(trimmed.substring(2).trim());
      index++;
    }
    return items;
  }

  private static skipListItems(lines: string[], start: number): number {
    let index: number = start;
    while (index < lines.length) {
      const trimmed: string = lines[index].trim();
      if (trimmed.length === 0 || !trimmed.startsWith('- ')) {
        break;
      }
      index++;
    }
    return index;
  }

  private static splitInlineList(value: string): string[] {
    const body: string = value.substring(1, value.length - 1);
    const items: string[] = [];
    for (const part of body.split(',')) {
      const trimmed: string = part.trim().replace(/^["']|["']$/g, '');
      if (trimmed.length > 0) {
        items.push(trimmed);
      }
    }
    return items;
  }

  private static detectType(value: string): MdPropType {
    if (value === 'true' || value === 'false') {
      return MdPropType.BOOLEAN;
    }
    if (/^-?\d+(\.\d+)?$/.test(value)) {
      return MdPropType.NUMBER;
    }
    return MdPropType.STRING;
  }
}

/** frontmatter 解析结果。 */
export class FrontmatterResult {
  frontmatter: MdFrontmatter = new MdFrontmatter();
  /** 已消费的行数（包含前后分隔行） */
  consumed: number = 0;
}
