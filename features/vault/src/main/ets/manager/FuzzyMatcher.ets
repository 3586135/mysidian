/**
 * 模糊匹配：用于快速切换器。
 * 支持子串匹配与子序列匹配，返回匹配得分，未命中返回 -1。
 */
export class FuzzyMatcher {
  /** 计算匹配得分，分值越高越靠前。 */
  public static score(query: string, target: string): number {
    const needle: string = query.trim().toLowerCase();
    if (needle.length === 0) {
      return 0;
    }
    const haystack: string = target.toLowerCase();
    if (haystack.length === 0) {
      return -1;
    }
    const direct: number = haystack.indexOf(needle);
    if (direct === 0) {
      return 1000 - haystack.length;
    }
    if (direct > 0) {
      return 700 - direct - haystack.length * 0.1;
    }
    let score: number = 0;
    let position: number = 0;
    let previousMatch: number = -1;
    for (let index: number = 0; index < needle.length; index++) {
      const ch: string = needle.charAt(index);
      const found: number = haystack.indexOf(ch, position);
      if (found < 0) {
        return -1;
      }
      if (previousMatch >= 0 && found === previousMatch + 1) {
        score += 20;
      } else {
        score += 5;
      }
      if (found === 0 || haystack.charAt(found - 1) === '/' || haystack.charAt(found - 1) === ' ') {
        score += 10;
      }
      previousMatch = found;
      position = found + 1;
    }
    return score;
  }
}
