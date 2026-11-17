/**
 * 标签合法性规则（与 Obsidian 对齐，单一事实来源）：
 * - 允许：字母（ASCII + CJK 文字）、数字、_、-、/；
 * - 拒绝：CJK 符号/标点（，。、）、全角标点（）！？等）、其余符号；
 * - 纯数字（#2026）与十六进制色值（#FFF、#1A1A2E、#FFFFFF80）不是标签。
 */
export class TagRules {
  /** 单个字符是否可作为标签体字符。 */
  public static isTagChar(ch: string): boolean {
    if (ch.length === 0) {
      return false;
    }
    const code: number = ch.charCodeAt(0);
    if ((code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122) ||
      code === 45 || code === 95 || code === 47) {
      return true;
    }
    return TagRules.isCjkText(code);
  }

  /** 标签体整体是否合法：非空、字符集合规、非纯数字、非十六进制色值。 */
  public static isTagBody(body: string): boolean {
    if (body.length === 0) {
      return false;
    }
    let allDigits: boolean = true;
    let allHex: boolean = true;
    for (let index: number = 0; index < body.length; index++) {
      const ch: string = body.charAt(index);
      if (!TagRules.isTagChar(ch)) {
        return false;
      }
      const code: number = ch.charCodeAt(0);
      if (code < 48 || code > 57) {
        allDigits = false;
      }
      if (!TagRules.isHexCode(code)) {
        allHex = false;
      }
    }
    if (allDigits) {
      return false;
    }
    if (allHex && (body.length === 3 || body.length === 4 || body.length === 6 || body.length === 8)) {
      return false;
    }
    return true;
  }

  /** CJK 文字区间（汉字/假名/谚文等）；不含 CJK 符号标点（U+3000 区）与全角形式（U+FF00 区）。 */
  private static isCjkText(code: number): boolean {
    return (code >= 0x3005 && code <= 0x3007) ||
      (code >= 0x3040 && code <= 0x30FF) ||
      (code >= 0x3100 && code <= 0x312F) ||
      (code >= 0x31A0 && code <= 0x31BF) ||
      (code >= 0x3400 && code <= 0x4DBF) ||
      (code >= 0x4E00 && code <= 0x9FFF) ||
      (code >= 0xA960 && code <= 0xA97F) ||
      (code >= 0xAC00 && code <= 0xD7AF) ||
      (code >= 0xF900 && code <= 0xFAFF) ||
      (code >= 0x20000 && code <= 0x2FA1F);
  }

  private static isHexCode(code: number): boolean {
    return (code >= 48 && code <= 57) || (code >= 65 && code <= 70) || (code >= 97 && code <= 102);
  }
}
