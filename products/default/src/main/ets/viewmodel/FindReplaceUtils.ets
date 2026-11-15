/**
 * 页内查找 / 替换的纯函数工具。
 *
 * 不依赖 ArkUI 运行时，可直接单元测试。所有偏移均为 UTF-16 码元下标，
 * 与 TextArea 的 caret / selection 偏移一致。
 */
export class FindReplaceUtils {
  /**
   * 查找所有不重叠的匹配起点（升序）。关键词为空返回空数组。
   * 默认不区分大小写（toLowerCase 不改变 BMP 字符的码元长度，下标可直接对应原文）。
   */
  public static findAll(text: string, keyword: string, matchCase: boolean = false): number[] {
    const result: number[] = [];
    if (keyword.length === 0 || text.length === 0) {
      return result;
    }
    const source: string = matchCase ? text : text.toLowerCase();
    const target: string = matchCase ? keyword : keyword.toLowerCase();
    // 个别字符（如 İ）转小写后长度会变化，此时下标无法对应原文，退回区分大小写匹配。
    if (source.length !== text.length || target.length !== keyword.length) {
      return FindReplaceUtils.findAll(text, keyword, true);
    }
    let from: number = 0;
    while (from <= source.length - target.length) {
      const index: number = source.indexOf(target, from);
      if (index < 0) {
        break;
      }
      result.push(index);
      from = index + target.length;
    }
    return result;
  }

  /** 把当前匹配的下标按环形移动（step 为 +1 / -1），空集返回 -1。 */
  public static cycle(current: number, count: number, step: number): number {
    if (count <= 0) {
      return -1;
    }
    if (current < 0) {
      return step >= 0 ? 0 : count - 1;
    }
    return (current + step + count) % count;
  }

  /** 替换单个匹配：返回新文本。起点越界时原样返回。 */
  public static replaceAt(text: string, start: number, length: number, replacement: string): string {
    if (start < 0 || start > text.length) {
      return text;
    }
    return text.substring(0, start) + replacement + text.substring(start + length);
  }

  /** 全部替换：返回新文本（按 findAll 的匹配集合，一次完成）。 */
  public static replaceAll(text: string, keyword: string, replacement: string,
    matchCase: boolean = false): string {
    const matches: number[] = FindReplaceUtils.findAll(text, keyword, matchCase);
    if (matches.length === 0) {
      return text;
    }
    let output: string = '';
    let cursor: number = 0;
    for (const start of matches) {
      output += text.substring(cursor, start) + replacement;
      cursor = start + keyword.length;
    }
    return output + text.substring(cursor);
  }
}
