/**
 * 搜索框标签子句解析（Obsidian 风格）：
 * - `tag:#工作` / `#工作`：要求包含该标签（含子标签）；
 * - `-tag:#已完成` / `-#已完成`：排除该标签；
 * - `tag:#a OR tag:#b`：同组任一命中即可；`tag:#a AND tag:#b` 或相邻排列：分别要求；
 * - 其余词元原样保留为全文关键词。
 */
import { TagRules } from './TagRules';

export class SearchTextParser {
  private static readonly OP_AND: number = 0;
  private static readonly OP_OR: number = 1;

  public static parse(input: string): ParsedSearchText {
    const result: ParsedSearchText = new ParsedSearchText();
    const rawTokens: string[] = input.split(/\s+/);
    const keywordParts: string[] = [];
    let lastOperator: number = SearchTextParser.OP_AND;
    for (const raw of rawTokens) {
      const token: string = raw.trim();
      if (token.length === 0) {
        continue;
      }
      const upper: string = token.toUpperCase();
      if (upper === 'AND') {
        lastOperator = SearchTextParser.OP_AND;
        continue;
      }
      if (upper === 'OR') {
        lastOperator = SearchTextParser.OP_OR;
        continue;
      }
      const clause: TagClause | null = SearchTextParser.parseTagClause(token);
      if (clause === null) {
        keywordParts.push(token);
        lastOperator = SearchTextParser.OP_AND;
        continue;
      }
      if (clause.exclude) {
        result.tagExcludes.push(clause.tag);
        lastOperator = SearchTextParser.OP_AND;
        continue;
      }
      if (lastOperator === SearchTextParser.OP_OR && result.tagGroups.length > 0) {
        result.tagGroups[result.tagGroups.length - 1].push(clause.tag);
      } else {
        const group: string[] = [clause.tag];
        result.tagGroups.push(group);
      }
      lastOperator = SearchTextParser.OP_AND;
    }
    result.keyword = keywordParts.join(' ');
    return result;
  }

  /** 解析单个标签子句词元；非标签子句返回 null（交回关键词）。 */
  private static parseTagClause(token: string): TagClause | null {
    let rest: string = token;
    let exclude: boolean = false;
    if (rest.startsWith('-')) {
      exclude = true;
      rest = rest.substring(1);
    }
    if (rest.startsWith('tag:')) {
      rest = rest.substring('tag:'.length);
    } else if (!rest.startsWith('#')) {
      return null;
    }
    if (rest.startsWith('#')) {
      rest = rest.substring(1);
    }
    if (rest.length === 0 || !TagRules.isTagBody(rest)) {
      return null;
    }
    const clause: TagClause = new TagClause();
    clause.tag = rest.toLowerCase();
    clause.exclude = exclude;
    return clause;
  }
}

/** 解析结果：剩余关键词 + 标签包含组（组内 OR、组间 AND）+ 排除标签。 */
export class ParsedSearchText {
  keyword: string = '';
  tagGroups: string[][] = [];
  tagExcludes: string[] = [];
}

/** 单个标签子句。 */
class TagClause {
  tag: string = '';
  exclude: boolean = false;
}
