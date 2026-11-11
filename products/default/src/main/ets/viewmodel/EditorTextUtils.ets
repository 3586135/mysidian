/**
 * 编辑器纯函数工具：列表续行与 wiki 链接补全。
 *
 * 该模块不依赖 ArkUI 运行时，可直接单元测试。
 */

/** 列表项标记。 */
export class ListMarker {
  /** 匹配到的标记文本（如 "- " / "1. " / "- [ ] "）。 */
  text: string = '';
  /** 回车续行时应插入的文本。 */
  continuation: string = '';
}

/** 列表续行结果。 */
export class ListContinuation {
  /** 需要删除的区间起点（相对新文本）。 */
  deleteFrom: number = 0;
  /** 需要删除的区间终点（相对新文本，不含）。 */
  deleteTo: number = 0;
  /** 删除后需要插入的文本。 */
  insertText: string = '';
  /** 是否为「空列表项回车 → 结束列表」。 */
  endList: boolean = false;
}

/** wiki 链接补全候选项。 */
export class CompletionCandidate {
  /** 笔记标题。 */
  title: string = '';
  /** 选中后应追加的文本（标题剩余部分 + 右括号）。 */
  insertText: string = '';
  /** 候选替换起点（相对正文起始位置；-1 表示在光标处直接插入）。 */
  replaceFrom: number = -1;
}

/**
 * 编辑器纯函数工具集。
 */
export class EditorTextUtils {
  /** 补全浮层最多展示的候选数量。 */
  public static readonly MAX_COMPLETION_ITEMS: number = 8;

  /**
   * 计算列表续行结果。
   *
   * 仅当本次改动是「在光标处插入一个换行」且所在行是列表项时才返回结果：
   * - 列表项有内容 → 续行，插入同类标记（有序列表序号递增）
   * - 列表项为空   → 结束列表，删除该空列表项
   *
   * @param prevText 改动前的正文
   * @param newText 改动后的正文
   * @param prevCaret 改动前的光标位置（提示值，定位失败时自动回退为逐位比对）
   * @returns 续行结果；不满足条件时返回 null
   */
  public static computeListContinuation(prevText: string, newText: string,
    prevCaret: number): ListContinuation | null {
    const insertAt: number = EditorTextUtils.findInsertedNewline(prevText, newText, prevCaret);
    if (insertAt < 0) {
      return null;
    }
    const lineStart: number = EditorTextUtils.lineStartOf(prevText, insertAt);
    const lineEnd: number = EditorTextUtils.lineEndOf(prevText, insertAt);
    const lineText: string = prevText.substring(lineStart, lineEnd);
    const marker: ListMarker | null = EditorTextUtils.detectMarker(lineText);
    if (marker === null) {
      return null;
    }
    const result: ListContinuation = new ListContinuation();
    if (lineText.length === marker.text.length) {
      // 空列表项：结束列表，连同刚插入的换行一起删除。
      result.endList = true;
      result.deleteFrom = lineStart;
      result.deleteTo = insertAt + 1;
      result.insertText = '';
      return result;
    }
    result.deleteFrom = insertAt + 1;
    result.deleteTo = insertAt + 1;
    result.insertText = marker.continuation;
    return result;
  }

  /**
   * 计算 wiki 链接补全候选。
   *
   * 匹配规则：前缀命中排在前面，包含命中排在后面（输入 [[读书 可命中「2026-读书笔记」）。
   *
   * @param text 当前正文
   * @param caret 当前光标位置
   * @param allTitles 仓库内全部笔记标题
   * @returns 候选列表（最多 8 条）；当前不在 wiki 链接上下文中时返回空数组
   */
  public static getWikiCompletionCandidates(text: string, caret: number,
    allTitles: string[]): CompletionCandidate[] {
    const candidates: CompletionCandidate[] = [];
    if (caret < 0 || caret > text.length) {
      return candidates;
    }
    const before: string = text.substring(0, caret);
    const open: number = before.lastIndexOf('[[');
    if (open < 0) {
      return candidates;
    }
    if (before.lastIndexOf(']]') > open) {
      // 链接已闭合，不是补全场景。
      return candidates;
    }
    const query: string = before.substring(open + 2);
    if (query.includes('\n') || query.includes(']')) {
      return candidates;
    }
    const lower: string = query.toLowerCase();
    const prefixHits: CompletionCandidate[] = [];
    const containsHits: CompletionCandidate[] = [];
    for (const title of allTitles) {
      if (title.length === 0) {
        continue;
      }
      const lowerTitle: string = title.toLowerCase();
      const candidate: CompletionCandidate = new CompletionCandidate();
      candidate.title = title;
      candidate.replaceFrom = open + 2;
      if (lowerTitle.startsWith(lower)) {
        // 前缀命中：整体替换已输入的查询串。
        candidate.insertText = `${title}]]`;
        prefixHits.push(candidate);
      } else if (lowerTitle.includes(lower)) {
        // 包含命中：同样整体替换为完整标题。
        candidate.insertText = `${title}]]`;
        containsHits.push(candidate);
      }
    }
    for (const candidate of prefixHits) {
      candidates.push(candidate);
      if (candidates.length >= EditorTextUtils.MAX_COMPLETION_ITEMS) {
        return candidates;
      }
    }
    for (const candidate of containsHits) {
      candidates.push(candidate);
      if (candidates.length >= EditorTextUtils.MAX_COMPLETION_ITEMS) {
        break;
      }
    }
    return candidates;
  }

  /**
   * 计算标签补全候选（输入 # 时提示仓库内已有标签）。
   *
   * @param text 当前正文
   * @param caret 当前光标位置
   * @param allTags 仓库内全部标签
   * @returns 候选列表；当前不在标签上下文中时返回空数组
   */
  public static getTagCompletionCandidates(text: string, caret: number,
    allTags: string[]): CompletionCandidate[] {
    const candidates: CompletionCandidate[] = [];
    if (caret < 0 || caret > text.length) {
      return candidates;
    }
    const before: string = text.substring(0, caret);
    const hash: number = before.lastIndexOf('#');
    if (hash < 0) {
      return candidates;
    }
    // '#' 必须是标签起始（前为空白或行首），避免命中 "C#" / URL 片段。
    if (hash > 0) {
      const prev: string = before.charAt(hash - 1);
      const isBoundary: boolean = prev.trim().length === 0 || prev === '(' || prev === '[';
      if (!isBoundary) {
        return candidates;
      }
    }
    const query: string = before.substring(hash + 1);
    if (query.includes('\n') || query.includes(' ') || query.includes('#')) {
      return candidates;
    }
    const lower: string = query.toLowerCase();
    for (const tag of allTags) {
      const name: string = tag.startsWith('#') ? tag.substring(1) : tag;
      if (name.length === 0) {
        continue;
      }
      if (!name.toLowerCase().startsWith(lower)) {
        continue;
      }
      const candidate: CompletionCandidate = new CompletionCandidate();
      candidate.title = name;
      candidate.insertText = name;
      candidate.replaceFrom = hash + 1;
      candidates.push(candidate);
      if (candidates.length >= EditorTextUtils.MAX_COMPLETION_ITEMS) {
        break;
      }
    }
    return candidates;
  }

  /** 定位本次改动中插入的换行位置；不是单次换行插入时返回 -1。 */
  private static findInsertedNewline(prevText: string, newText: string, hint: number): number {
    if (newText.length !== prevText.length + 1) {
      return -1;
    }
    if (hint >= 0 && hint <= prevText.length && newText.charAt(hint) === '\n' &&
      newText.substring(0, hint) === prevText.substring(0, hint) &&
      newText.substring(hint + 1) === prevText.substring(hint)) {
      return hint;
    }
    // 回退：逐位比对定位唯一差异点。
    let common: number = 0;
    while (common < prevText.length && newText.charAt(common) === prevText.charAt(common)) {
      common++;
    }
    if (newText.charAt(common) !== '\n') {
      return -1;
    }
    if (newText.substring(common + 1) !== prevText.substring(common)) {
      return -1;
    }
    return common;
  }

  /** 取所在行的起始索引。 */
  private static lineStartOf(text: string, index: number): number {
    let start: number = index;
    while (start > 0 && text.charAt(start - 1) !== '\n') {
      start--;
    }
    return start;
  }

  /** 取所在行的结束索引（不含换行符）。 */
  private static lineEndOf(text: string, index: number): number {
    let end: number = index;
    while (end < text.length && text.charAt(end) !== '\n') {
      end++;
    }
    return end;
  }

  /** 识别行首的列表标记；不是列表项时返回 null。 */
  private static detectMarker(lineText: string): ListMarker | null {
    const task: RegExpExecArray | null = /^([-*+]) \[([ xX])\] /.exec(lineText);
    if (task !== null) {
      const marker: ListMarker = new ListMarker();
      marker.text = `${task[1]} [${task[2]}] `;
      marker.continuation = `${task[1]} [ ] `;
      return marker;
    }
    const unordered: RegExpExecArray | null = /^([-*+]) /.exec(lineText);
    if (unordered !== null) {
      const marker: ListMarker = new ListMarker();
      marker.text = `${unordered[1]} `;
      marker.continuation = `${unordered[1]} `;
      return marker;
    }
    const ordered: RegExpExecArray | null = /^(\d+)([.)]) /.exec(lineText);
    if (ordered !== null) {
      const marker: ListMarker = new ListMarker();
      const ordinal: number = Number(ordered[1]);
      marker.text = `${ordered[1]}${ordered[2]} `;
      marker.continuation = `${ordinal + 1}${ordered[2]} `;
      return marker;
    }
    return null;
  }
}
