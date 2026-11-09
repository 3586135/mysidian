import { MdListItem } from '@ohos/domain';

/** 提取结果：匹配值与剩余文本。 */
class ExtractResult {
  value: string = '';
  rest: string = '';
}

/**
 * Obsidian-Tasks 兼容的任务元数据：
 * 解析 🛫 ⏳ 📅 ✅ ➕ 🔁 与优先级 ⏫/🔼/🔽，并提供勾选回写。
 * 格式参考 https://github.com/obsidian-tasks-group/obsidian-tasks
 */
export class TaskMetadata {
  private static readonly RECURRENCE_EMOJI: string = '🔁';
  private static readonly META_EMOJIS: string[] =
    ['🛫', '⏳', '📅', '✅', '➕', '🔁', '⏫', '🔼', '🔽'];
  private static readonly PRIORITY_EMOJIS: string[] = ['⏫', '🔼', '🔽'];

  /** 从任务文本提取元数据写入 item，返回剔除元数据后的正文。 */
  public static apply(item: MdListItem, content: string): string {
    let text: string = content;
    const start: ExtractResult = TaskMetadata.extractDate(text, '🛫');
    item.startDate = start.value;
    text = start.rest;
    const scheduled: ExtractResult = TaskMetadata.extractDate(text, '⏳');
    item.scheduledDate = scheduled.value;
    text = scheduled.rest;
    const due: ExtractResult = TaskMetadata.extractDate(text, '📅');
    item.dueDate = due.value;
    text = due.rest;
    const done: ExtractResult = TaskMetadata.extractDate(text, '✅');
    item.doneDate = done.value;
    text = done.rest;
    const created: ExtractResult = TaskMetadata.extractDate(text, '➕');
    item.createdDate = created.value;
    text = created.rest;
    const recurrence: ExtractResult = TaskMetadata.extractRecurrence(text);
    item.recurrence = recurrence.value;
    text = recurrence.rest;
    const priority: ExtractResult = TaskMetadata.extractPriority(text);
    item.priority = priority.value;
    text = priority.rest;
    return TaskMetadata.collapseSpaces(text);
  }

  /** 勾选/取消勾选任务：更新 [ ]/[x] 标记，并维护 ✅ 完成日期。 */
  public static toggle(rawLine: string, checked: boolean): string {
    const marker: RegExpExecArray | null =
      /^(\s*(?:[-*+]|\d+[.)])\s+\[)([ xX])(\].*)$/u.exec(rawLine);
    if (marker === null) {
      return rawLine;
    }
    const body: string = marker[3];
    if (checked) {
      const withDate: string = TaskMetadata.ensureDoneDate(body);
      return `${marker[1]}x${withDate}`;
    }
    const cleared: string = TaskMetadata.removeDoneDate(body);
    return `${marker[1]} ${cleared}`;
  }

  /** 今日日期字符串（YYYY-MM-DD）。 */
  public static today(): string {
    const now: Date = new Date();
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
  }

  /** 提取 "emoji YYYY-MM-DD" 形式的日期元数据。 */
  private static extractDate(text: string, emoji: string): ExtractResult {
    const result: ExtractResult = new ExtractResult();
    const pattern: RegExp = new RegExp(`(^|\\s)${emoji}\\s*(\\d{4}-\\d{2}-\\d{2})(?=\\s|$)`, 'u');
    const match: RegExpExecArray | null = pattern.exec(text);
    if (match === null) {
      result.rest = text;
      return result;
    }
    result.value = match[2];
    result.rest = text.substring(0, match.index) + ' ' +
      text.substring(match.index + match[0].length);
    return result;
  }

  /** 提取 🔁 重复规则（到下一个元数据 emoji 或行尾）。 */
  private static extractRecurrence(text: string): ExtractResult {
    const result: ExtractResult = new ExtractResult();
    const index: number = text.indexOf(TaskMetadata.RECURRENCE_EMOJI);
    if (index < 0) {
      result.rest = text;
      return result;
    }
    let end: number = text.length;
    const from: number = index + TaskMetadata.RECURRENCE_EMOJI.length;
    for (const emoji of TaskMetadata.META_EMOJIS) {
      const next: number = text.indexOf(emoji, from);
      if (next >= 0 && next < end) {
        end = next;
      }
    }
    result.value = TaskMetadata.collapseSpaces(
      text.substring(from, end)).trim();
    result.rest = text.substring(0, index) + ' ' + text.substring(end);
    return result;
  }

  /** 提取优先级 emoji（⏫/🔼/🔽）。 */
  private static extractPriority(text: string): ExtractResult {
    const result: ExtractResult = new ExtractResult();
    for (const emoji of TaskMetadata.PRIORITY_EMOJIS) {
      const pattern: RegExp = new RegExp(`(^|\\s)${emoji}(?=\\s|$)`, 'u');
      const match: RegExpExecArray | null = pattern.exec(text);
      if (match !== null) {
        result.value = emoji;
        result.rest = text.substring(0, match.index) + ' ' +
          text.substring(match.index + match[0].length);
        return result;
      }
    }
    result.rest = text;
    return result;
  }

  /** 勾选时确保存在 ✅ 日期（缺失则补今日）。 */
  private static ensureDoneDate(body: string): string {
    const existing: RegExpExecArray | null = /\s*✅\s*\d{4}-\d{2}-\d{2}(?=\s|$)/u.exec(body);
    if (existing !== null) {
      const updated: string = body.substring(0, existing.index) +
        ` ✅ ${TaskMetadata.today()} ` + body.substring(existing.index + existing[0].length);
      return TaskMetadata.collapseSpaces(updated).trim();
    }
    return `${body.trimEnd()} ✅ ${TaskMetadata.today()}`;
  }

  /** 取消勾选时移除 ✅ 日期。 */
  private static removeDoneDate(body: string): string {
    const existing: RegExpExecArray | null = /\s*✅\s*\d{4}-\d{2}-\d{2}(?=\s|$)/u.exec(body);
    if (existing === null) {
      return body;
    }
    const updated: string = body.substring(0, existing.index) + ' ' +
      body.substring(existing.index + existing[0].length);
    return TaskMetadata.collapseSpaces(updated).trim();
  }

  /** 压缩多余空白。 */
  private static collapseSpaces(text: string): string {
    return text.replace(/\s+/g, ' ').trim();
  }
}
