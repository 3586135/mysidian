import { MdProperty, MdPropType } from '@ohos/domain';

/**
 * YAML frontmatter 反向序列化：把属性模型写回文档头部。
 *
 * 与 FrontmatterParser 互为逆运算，用于可视化属性编辑器的保存。
 *
 * 写回采用「按 key 合并」策略：只替换被修改的属性块，
 * 解析器未识别的内容（嵌套 map、注释、非法行）原样保留，避免保存时丢数据。
 */
export class FrontmatterSerializer {
  private static readonly DELIMITER: string = '---';

  /**
   * 序列化属性为 YAML 正文（不含分隔行）。
   */
  public static serialize(properties: MdProperty[]): string {
    const lines: string[] = [];
    for (const property of properties) {
      lines.push(...FrontmatterSerializer.serializeProperty(property));
    }
    return lines.join('\n');
  }

  /** 序列化单个属性（列表为多行）。 */
  private static serializeProperty(property: MdProperty): string[] {
    const lines: string[] = [];
    if (property.key.trim().length === 0) {
      return lines;
    }
    if (property.type === MdPropType.MAP && property.rawBlock.length > 0) {
      // 嵌套 map：原样回写解析时保留的原始块，不丢内容。
      for (const line of property.rawBlock.split('\n')) {
        lines.push(line);
      }
      return lines;
    }
    if (property.type === MdPropType.LIST) {
      if (property.listValue.length === 0) {
        lines.push(`${property.key}: []`);
        return lines;
      }
      lines.push(`${property.key}:`);
      for (const item of property.listValue) {
        lines.push(`  - ${FrontmatterSerializer.quoteIfNeeded(item)}`);
      }
      return lines;
    }
    lines.push(`${property.key}: ${FrontmatterSerializer.quoteIfNeeded(property.value)}`);
    return lines;
  }

  /**
   * 用新的属性集合替换文档中的 frontmatter；文档原本没有 frontmatter 时补写。
   *
   * @param content 原文档
   * @param properties 新属性集合
   * @param removedKeys 显式删除的属性 key（整块移除，含嵌套 map 块）
   * @returns 替换后的整篇文档
   */
  public static rebuild(content: string, properties: MdProperty[],
    removedKeys: string[] = []): string {
    const lines: string[] = content.split('\n');
    if (lines.length === 0 || lines[0].trim() !== FrontmatterSerializer.DELIMITER) {
      const head: string = `${FrontmatterSerializer.DELIMITER}\n${FrontmatterSerializer.serialize(properties)}\n` +
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
    const merged: string[] = FrontmatterSerializer.merge(lines.slice(1, end), properties, removedKeys);
    const head: string = `${FrontmatterSerializer.DELIMITER}\n${merged.join('\n')}\n` +
      `${FrontmatterSerializer.DELIMITER}`;
    const rest: string[] = lines.slice(end + 1);
    if (rest.length === 0) {
      return `${head}\n`;
    }
    return `${head}\n${rest.join('\n')}`;
  }

  /**
   * 按 key 合并 frontmatter 正文。
   *
   * - 命中属性集合的 key：整块替换为新内容；
   * - 显式删除（removedKeys）的 key：整块移除；
   * - 未命中的块（注释 / 解析器忽略的行）：原样保留；
   * - 新增的 key：追加到末尾。
   */
  private static merge(original: string[], properties: MdProperty[],
    removedKeys: string[]): string[] {
    const output: string[] = [];
    const done: string[] = [];
    let index = 0;
    while (index < original.length) {
      const line: string = original[index];
      const trimmed: string = line.trim();
      const separator: number = trimmed.indexOf(':');
      const isTopLevel: boolean = trimmed.length > 0 && !trimmed.startsWith('#') &&
        !trimmed.startsWith('- ') && !line.startsWith(' ') && !line.startsWith('\t') &&
        separator > 0;
      if (!isTopLevel) {
        // 注释、空行、列表项等：原样保留。
        output.push(line);
        index++;
        continue;
      }
      const key: string = trimmed.substring(0, separator).trim();
      // 收集该 key 的整个块（含缩进子行）。
      const block: string[] = [line];
      let cursor = index + 1;
      while (cursor < original.length) {
        const next: string = original[cursor];
        const nextTrimmed: string = next.trim();
        if (nextTrimmed.length === 0) {
          break;
        }
        if (!next.startsWith(' ') && !next.startsWith('\t') && !nextTrimmed.startsWith('- ')) {
          break;
        }
        block.push(next);
        cursor++;
      }
      let property: MdProperty | null = null;
      for (const item of properties) {
        if (item.key === key) {
          property = item;
          break;
        }
      }
      if (property === null) {
        if (removedKeys.includes(key)) {
          // 显式删除：整块移除（含嵌套 map 块）。
          done.push(key);
          index = cursor;
          continue;
        }
        // 未在属性集合中的键：整块保留（注释等内容不丢）。
        output.push(...block);
      } else if (FrontmatterSerializer.hasNestedContent(block) &&
        property.type === MdPropType.LIST && property.listValue.length === 0) {
        // 原块是嵌套 map（解析器未展开），新值为空列表：保留原内容。
        output.push(...block);
      } else {
        output.push(...FrontmatterSerializer.serializeProperty(property));
      }
      done.push(key);
      index = cursor;
    }
    // 追加新增属性。
    for (const item of properties) {
      if (done.includes(item.key)) {
        continue;
      }
      output.push(...FrontmatterSerializer.serializeProperty(item));
    }
    return output;
  }

  /** 判定属性块中是否含嵌套 map（缩进且不是列表项的行）。 */
  private static hasNestedContent(block: string[]): boolean {
    for (let index = 1; index < block.length; index++) {
      const line: string = block[index];
      const trimmed: string = line.trim();
      if (trimmed.startsWith('- ')) {
        continue;
      }
      if (line.startsWith(' ') || line.startsWith('\t')) {
        return true;
      }
    }
    return false;
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
