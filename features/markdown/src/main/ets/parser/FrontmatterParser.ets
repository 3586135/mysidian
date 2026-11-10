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
      let listBranch: boolean = false;
      if (value.length === 0) {
        property.type = MdPropType.LIST;
        property.listValue = FrontmatterParser.collectListItems(lines, index + 1);
        // 列表分支把游标推进到下一个键所在行，循环末尾不能再自增，
        // 否则列表之后的属性会被整条跳过（属性丢失）。
        index = FrontmatterParser.skipListItems(lines, index + 1);
        listBranch = true;
      } else if (value.startsWith('[') && value.endsWith(']')) {
        property.type = MdPropType.LIST;
        property.listValue = FrontmatterParser.splitInlineList(value);
      } else {
        property.type = FrontmatterParser.detectType(value);
        property.value = value;
      }
      frontmatter.properties.push(property);
      if (key.toLowerCase() === 'tags') {
        const sources: string[] = property.type === MdPropType.LIST
          ? property.listValue
          : (property.value.length > 0 ? [property.value] : []);
        for (const source of sources) {
          for (const token of FrontmatterParser.splitTagTokens(source)) {
            FrontmatterParser.addNormalizedTag(frontmatter.tags, token);
          }
        }
      }
      if (!listBranch) {
        index++;
      }
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

  /**
   * 通用标签分词：一行（或列表项）中出现多个 # 即多个标签。
   * 以空白、半角/全角逗号、# 为分界，兼容 `[a, b]`、`- #a`、`#a #b`、`#a#b`、`a, b` 等写法。
   */
  private static splitTagTokens(value: string): string[] {
    const tokens: string[] = [];
    for (const part of value.split(/[\s,，#]+/)) {
      if (part.length > 0) {
        tokens.push(part);
      }
    }
    return tokens;
  }

  /** 归一化单个标签：去首部 # 与包裹引号，去重后压入。 */
  private static addNormalizedTag(tags: string[], tag: string): void {
    let normalized: string = tag.trim().replace(/^#/, '');
    normalized = normalized.replace(/^["']+/, '').replace(/["']+$/, '');
    if (normalized.length > 0 && !tags.includes(normalized)) {
      tags.push(normalized);
    }
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
