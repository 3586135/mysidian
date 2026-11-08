/**
 * 中英文分词器。
 * 平台 FTS 默认使用 unicode61 分词器，不切分中文，
 * 因此在应用层完成切分：中文按二元组（bigram）、英文与数字按单词。
 */
export class Tokenizer {
  /** 切分为检索词。 */
  public static tokenize(text: string): string[] {
    const tokens: string[] = [];
    const lower: string = text.toLowerCase();
    let index: number = 0;
    while (index < lower.length) {
      const code: number = lower.charCodeAt(index);
      if (Tokenizer.isCjk(code)) {
        const next: number = index + 1 < lower.length ? lower.charCodeAt(index + 1) : 0;
        if (index + 1 < lower.length && Tokenizer.isCjk(next)) {
          tokens.push(lower.substring(index, index + 2));
          index++;
          continue;
        }
        tokens.push(lower.charAt(index));
        index++;
        continue;
      }
      if (Tokenizer.isWordChar(code)) {
        let end: number = index;
        while (end < lower.length && Tokenizer.isWordChar(lower.charCodeAt(end))) {
          end++;
        }
        tokens.push(lower.substring(index, end));
        index = end;
        continue;
      }
      index++;
    }
    return tokens;
  }

  /** 生成写入 FTS 的空格分隔词串。 */
  public static buildTerms(text: string): string {
    return Tokenizer.tokenize(text).join(' ');
  }

  /** 生成 MATCH 表达式：所有词以 AND 连接，末词支持前缀匹配。 */
  public static buildMatchExpression(text: string): string {
    const tokens: string[] = Tokenizer.tokenize(text);
    if (tokens.length === 0) {
      return '';
    }
    const parts: string[] = [];
    for (let index: number = 0; index < tokens.length; index++) {
      if (index === tokens.length - 1) {
        parts.push(`${tokens[index]}*`);
      } else {
        parts.push(tokens[index]);
      }
    }
    return parts.join(' ');
  }

  private static isCjk(code: number): boolean {
    return (code >= 0x4E00 && code <= 0x9FFF) ||
      (code >= 0x3400 && code <= 0x4DBF) ||
      (code >= 0x3040 && code <= 0x30FF) ||
      (code >= 0xAC00 && code <= 0xD7AF);
  }

  private static isWordChar(code: number): boolean {
    return (code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      code === 95;
  }
}
