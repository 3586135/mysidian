/**
 * 模板引擎：把仓库内 Templates/ 目录下的模板套用到新笔记 / 日记。
 *
 * 支持占位符（对齐 Obsidian Templater 的常用子集）：
 * - {{title}}            笔记标题
 * - {{date}}             当天日期（YYYY-MM-DD）
 * - {{date:YYYY-MM-DD}}  自定义日期格式
 * - {{time}}             当前时间（HH:mm）
 * - {{week}}             ISO 周编号（WW）
 * - {{cursor}}           光标占位符（渲染后移除，位置记录在结果中）
 */
export class TemplateRenderResult {
  /** 渲染后的正文。 */
  content: string = '';
  /** 光标应放置的位置（正文长度）。 */
  cursorOffset: number = 0;
}

/**
 * 模板渲染器。
 */
export class TemplateEngine {
  /** 模板目录名（仓库根目录下的 Templates）。 */
  public static readonly TEMPLATES_DIR: string = 'Templates';
  /** 光标占位符标记（渲染后移除，位置记录在结果中）。 */
  private static readonly CURSOR_TOKEN: string = '{{cursor}}';

  /**
   * 渲染模板。
   *
   * @param template 模板正文
   * @param title 笔记标题
   * @param now 当前时间
   * @returns 渲染结果（含光标位置）
   */
  public static render(template: string, title: string, now: Date): TemplateRenderResult {
    const result: TemplateRenderResult = new TemplateRenderResult();
    let content: string = template;
    content = TemplateEngine.replaceAll(content, '{{title}}', title);
    content = TemplateEngine.replaceAll(content, '{{date}}', TemplateEngine.formatDate(now, 'YYYY-MM-DD'));
    content = TemplateEngine.replaceAll(content, '{{time}}', TemplateEngine.formatDate(now, 'HH:mm'));
    content = TemplateEngine.replaceAll(content, '{{week}}', TemplateEngine.weekKey(now));
    // 自定义日期格式：{{date:FORMAT}}
    content = content.replace(/\{\{date:([^}]+)\}\}/g,
      (match: string, format: string): string => {
        return TemplateEngine.formatDate(now, format);
      });
    // 光标占位符：全部移除并记录首处位置（多个 {{cursor}} 时
    // 第二个此前会残留为字面文本）。
    const cursorIndex: number = content.indexOf(TemplateEngine.CURSOR_TOKEN);
    if (cursorIndex >= 0) {
      content = TemplateEngine.replaceAll(content, TemplateEngine.CURSOR_TOKEN, '');
      result.cursorOffset = cursorIndex;
    } else {
      result.cursorOffset = content.length;
    }
    result.content = content;
    return result;
  }

  /** 按格式渲染日期：支持 YYYY / MM / DD / HH / mm / ss / ww。 */
  public static formatDate(now: Date, pattern: string): string {
    const year: string = now.getFullYear().toString();
    const month: string = TemplateEngine.pad(now.getMonth() + 1, 2);
    const day: string = TemplateEngine.pad(now.getDate(), 2);
    const hour: string = TemplateEngine.pad(now.getHours(), 2);
    const minute: string = TemplateEngine.pad(now.getMinutes(), 2);
    const second: string = TemplateEngine.pad(now.getSeconds(), 2);
    const week: string = TemplateEngine.pad(TemplateEngine.isoWeek(now), 2);
    let result: string = pattern;
    result = TemplateEngine.replaceAll(result, 'YYYY', year);
    result = TemplateEngine.replaceAll(result, 'MM', month);
    result = TemplateEngine.replaceAll(result, 'DD', day);
    result = TemplateEngine.replaceAll(result, 'HH', hour);
    result = TemplateEngine.replaceAll(result, 'mm', minute);
    result = TemplateEngine.replaceAll(result, 'ss', second);
    result = TemplateEngine.replaceAll(result, 'ww', week);
    return result;
  }

  /** ISO 周键：YYYY-Www（Obsidian 周期笔记的周报文件名）。 */
  public static weekKey(now: Date): string {
    const year: number = TemplateEngine.isoWeekYear(now);
    const week: number = TemplateEngine.isoWeek(now);
    return `${year}-W${TemplateEngine.pad(week, 2)}`;
  }

  /**
   * ISO 8601 周所属年份。
   *
   * 跨年周（如 2024-12-30 属于 2025-W01）按 ISO 周年计算，
   * 与 Obsidian 的周报命名保持一致。
   */
  public static isoWeekYear(now: Date): number {
    const date: Date = new Date(now.getTime());
    const weekday: number = (date.getDay() + 6) % 7;
    date.setDate(date.getDate() - weekday + 3);
    return date.getFullYear();
  }

  /** ISO 8601 周序号。 */
  public static isoWeek(now: Date): number {
    const date: Date = new Date(now.getTime());
    const weekday: number = (date.getDay() + 6) % 7;
    date.setDate(date.getDate() - weekday + 3);
    const firstThursday: Date = new Date(date.getFullYear(), 0, 4);
    const firstWeekday: number = (firstThursday.getDay() + 6) % 7;
    firstThursday.setDate(firstThursday.getDate() - firstWeekday + 3);
    const weeks: number = 1 + Math.round(
      (date.getTime() - firstThursday.getTime()) / (7 * 24 * 60 * 60 * 1000));
    return weeks;
  }

  /** 补零到指定宽度。 */
  private static pad(value: number, width: number): string {
    let text: string = value.toString();
    while (text.length < width) {
      text = `0${text}`;
    }
    return text;
  }

  /** 字符串全量替换（ArkTS 严格模式下 replaceAll 可用）。 */
  private static replaceAll(text: string, search: string, replacement: string): string {
    return text.split(search).join(replacement);
  }
}
