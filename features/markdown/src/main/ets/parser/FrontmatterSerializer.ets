import { MdProperty, MdPropType } from '@ohos/domain';

/**
 * YAML frontmatter 反向序列化：把属性模型写回文档头部。
 *
 * 与 FrontmatterParser 互为逆运算，用于可视化属性编辑器的保存。
 */
export class FrontmatterSerializer {
  private static readonly DELIMITER: string = '---';

  /**
   * 序列化属性为 YAML 正文（不含分隔行）。
   */
  public static serialize(properties: MdProperty[]): string {
    const lines: string[] = [];
    for (const property of properties) {
      if (property.key.trim().length === 0) {
        continue;
      }
      if (property.type === MdPropType.LIST) {
        if (property.listValue.length === 0) {
          lines.push(`${property.key}: []`);
          continue;
        }
        lines.push(`${property.key}:`);
        for (const item of property.listValue) {
          lines.push(`  - ${FrontmatterSerializer.quoteIfNeeded(item)}`);
        }
        continue;
      }
      lines.push(`${property.key}: ${FrontmatterSerializer.quoteIfNeeded(property.value)}`);
    }
    return lines.join('\n');
  }

  /**
   * 用新的属性集合替换文档中的 frontmatter；文档原本没有 frontmatter 时补写。
   *
   * @param content 原文档
   * @param properties 新属性集合
   * @returns 替换后的整篇文档
   */
  public static rebuild(content: string, properties: MdProperty[]): string {
    const body: string = FrontmatterSerializer.serialize(properties);
    const lines: string[] = content.split('\n');
    if (lines.length === 0 || lines[0].trim() !== FrontmatterSerializer.DELIMITER) {
      const head: string = `${FrontmatterSerializer.DELIMITER}\n${body}\n` +
        `${FrontmatterSerializer.DELIMITER}\n`;
      return head + content;
    }
    let end: number = -1;
    for (let index = 1; index < lines.length; index++) {
      if (lines[index].trim() === FrontmatterSerializer.DELIMITER) {
        end = index;
        break;
      }
    }
    if (end < 0) {
      return content;
    }
    const rest: string[] = lines.slice(end + 1);
    const head: string = `${FrontmatterSerializer.DELIMITER}\n${body}\n` +
      `${FrontmatterSerializer.DELIMITER}`;
    if (rest.length === 0) {
      return `${head}\n`;
    }
    return `${head}\n${rest.join('\n')}`;
  }

  /** 按需加引号：包含 YAML 特殊字符时用双引号包裹。 */
  private static quoteIfNeeded(value: string): string {
    if (value.length === 0) {
      return '""';
    }
    const needsQuote: boolean = value.includes(':') || value.includes('#') || value.includes('\n') ||
      value.includes('"') || value.startsWith(' ') || value.endsWith(' ') ||
      value.startsWith('[') || value.startsWith('{');
    if (!needsQuote) {
      return value;
    }
    return `"${value.split('"').join('\\"')}"`;
  }
}
