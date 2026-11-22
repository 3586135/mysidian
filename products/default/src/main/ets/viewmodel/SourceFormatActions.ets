/**
 * 源码模式工具栏格式动作的纯函数实现。
 *
 * 设计目标：与所见即所得引擎（WysiwygEditorEngine.applyToolbarAction）保持
 * 「同命令同语义」——同一工具栏按钮在两种编辑模式下行为对齐：
 * - heading：光标所在行标题级别循环 0→1→2→3→4→0（对齐 cycleHeadingOnActiveParagraph）；
 * - 行内标记：有选区包裹/解包，无选区在光标处成对插入/移除（toggle）；
 * - [[：成对插入 [[ 与 ]]，光标落在对内（对齐 insertWikiPair）。
 *
 * 全部为无副作用纯函数，可独立单元测试（参照 LocalUnit.test.ets 风格）。
 */

/** 一次源码文本编辑的结果：新文本 + 编辑后的选区范围。 */
export interface SourceTextEdit {
  text: string;
  selStart: number;
  selEnd: number;
}

export class SourceFormatActions {
  private static readonly INLINE_MARKS: string[] = ['**', '*', '~~', '==', '`'];

  /** 是否为行内包裹型语法（B / I / 删除线 / 高亮 / 行内代码）。 */
  public static isInlineMark(syntax: string): boolean {
    return SourceFormatActions.INLINE_MARKS.indexOf(syntax) >= 0;
  }

  /** 选区包裹：选区已包裹同一标记时解包，否则包裹；返回 null 表示选区无效。 */
  public static wrapInlineSelection(text: string, start: number, end: number,
    mark: string): SourceTextEdit | null {
    if (end <= start || start < 0 || end > text.length) {
      return null;
    }
    const sel: string = text.substring(start, end);
    if (sel.length >= mark.length * 2 && sel.startsWith(mark) && sel.endsWith(mark)) {
      const inner: string = sel.substring(mark.length, sel.length - mark.length);
      const unwrapped: SourceTextEdit = {
        text: text.substring(0, start) + inner + text.substring(end),
        selStart: start,
        selEnd: start + inner.length
      };
      return unwrapped;
    }
    const wrapped: SourceTextEdit = {
      text: text.substring(0, start) + mark + sel + mark + text.substring(end),
      selStart: start + mark.length,
      selEnd: start + mark.length + sel.length
    };
    return wrapped;
  }

  /** 光标处成对插入标记：光标已夹在成对标记之间时移除（toggle 语义）。 */
  public static toggleMarkAtCaret(text: string, caret: number, mark: string): SourceTextEdit {
    const c: number = Math.max(0, Math.min(caret, text.length));
    const before: string = text.substring(0, c);
    const after: string = text.substring(c);
    if (before.endsWith(mark) && after.startsWith(mark)) {
      const nextCaret: number = c - mark.length;
      const removed: SourceTextEdit = {
        text: before.substring(0, before.length - mark.length) + after.substring(mark.length),
        selStart: nextCaret,
        selEnd: nextCaret
      };
      return removed;
    }
    const inserted: SourceTextEdit = {
      text: before + mark + mark + after,
      selStart: c + mark.length,
      selEnd: c + mark.length
    };
    return inserted;
  }

  /** 光标处插入成对文本（如 [[ 与 ]]），光标落在对内。 */
  public static insertPairAtCaret(text: string, caret: number, open: string,
    close: string): SourceTextEdit {
    const c: number = Math.max(0, Math.min(caret, text.length));
    const pair: SourceTextEdit = {
      text: text.substring(0, c) + open + close + text.substring(c),
      selStart: c + open.length,
      selEnd: c + open.length
    };
    return pair;
  }

  /** 光标所在行标题级别循环：无 → H1 → H2 → H3 → H4 → 无。 */
  public static cycleHeadingAtCaret(text: string, caret: number): SourceTextEdit {
    const c: number = Math.max(0, Math.min(caret, text.length));
    const lineStart: number = c > 0 ? text.lastIndexOf('\n', c - 1) + 1 : 0;
    let lineEnd: number = text.indexOf('\n', c);
    if (lineEnd < 0) {
      lineEnd = text.length;
    }
    const line: string = text.substring(lineStart, lineEnd);
    const m: RegExpExecArray | null = /^(#{1,6}) /.exec(line);
    const level: number = m !== null ? m[1].length : 0;
    const nextLevel: number = level === 0 ? 1 : (level < 4 ? level + 1 : 0);
    const body: string = m !== null ? line.substring(m[0].length) : line;
    const prefix: string = nextLevel > 0 ? `${'#'.repeat(nextLevel)} ` : '';
    const nextLine: string = prefix + body;
    const shift: number = nextLine.length - line.length;
    const edit: SourceTextEdit = {
      text: text.substring(0, lineStart) + nextLine + text.substring(lineEnd),
      selStart: c + shift,
      selEnd: c + shift
    };
    return edit;
  }
}
