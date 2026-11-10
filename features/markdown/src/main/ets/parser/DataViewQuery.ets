/**
 * Obsidian-Dataview 查询解析（MVP 子集）：
 * 支持 TASK 查询 + WHERE 谓词（completed / !completed / contains(tags, "#x") /
 * contains(text, "…") / file.name != this.file.name）+ GROUP BY file.link。
 * 参考 https://github.com/blacksmithgu/obsidian-dataview
 */
export class DataViewQuery {
  /** 查询类型：TASK / TABLE / LIST。 */
  type: string = '';
  /** 过滤：仅已完成任务。 */
  requireCompleted: boolean = false;
  /** 过滤：仅未完成任务。 */
  requireIncomplete: boolean = false;
  /** 过滤：行内必须包含的 #标签（不含 #）。 */
  requiredTags: string[] = [];
  /** 过滤：行内必须包含的文本。 */
  containsText: string = '';
  /** 过滤：排除当前笔记。 */
  excludeCurrent: boolean = false;
  /** 按来源笔记分组显示。 */
  groupByFile: boolean = false;
  /** TABLE 查询列头（解析后）。 */
  tableColumns: string[] = [];
  /** TABLE 查询数据行（每行=列值数组）。 */
  tableRows: string[][] = [];
  /** LIST 查询条目列表。 */
  listItems: string[] = [];
  /** 解析是否成功（TABLE/LIST 用）。 */
  parsedOk: boolean = false;

  /** 是否为可执行的任务查询。 */
  public isTaskQuery(): boolean {
    return this.type === 'TASK';
  }

  /** 是否为 TABLE 查询。 */
  public isTableQuery(): boolean {
    return this.type === 'TABLE';
  }

  /** 是否为 LIST 查询。 */
  public isListQuery(): boolean {
    return this.type === 'LIST';
  }

  /** 解析 dataview 查询文本。 */
  public static parse(raw: string): DataViewQuery {
    const query: DataViewQuery = new DataViewQuery();
    const lines: string[] = raw.split('\n');
    for (let index = 0; index < lines.length; index++) {
      const line: string = lines[index].trim();
      if (line.length === 0) {
        continue;
      }
      const upper: string = line.toUpperCase();
      if (query.type.length === 0) {
        const firstWord: RegExpExecArray | null = /^([A-Za-z]+)\b/.exec(line);
        if (firstWord !== null) {
          query.type = firstWord[1].toUpperCase();
        }
        continue;
      }
      if (upper.startsWith('WHERE')) {
        DataViewQuery.parseWhere(line.substring(5), query);
        continue;
      }
      if (upper.startsWith('GROUP BY')) {
        query.groupByFile = true;
        continue;
      }
      if (query.type === 'TABLE' && upper.startsWith('FROM')) {
        query.parsedOk = true;
        continue;
      }
      if (query.type === 'LIST') {
        query.parsedOk = true;
        query.listItems.push(line);
        continue;
      }
      if (query.type === 'TABLE' && !query.parsedOk) {
        const headerLine: string = line.replace(/^\|/, '').replace(/\|$/, '').trim();
        query.tableColumns = headerLine.split('|').map((s: string) => s.trim());
        query.parsedOk = true;
        continue;
      }
      if (query.type === 'TABLE' && query.parsedOk) {
        const rowValues: string = line.replace(/^\|/, '').replace(/\|$/, '').trim();
        const cells: string[] = rowValues.split('|').map((s: string) => s.trim());
        query.tableRows.push(cells);
        continue;
      }
    }
    return query;
  }

  /** 解析 WHERE 子句（按 AND 拆分，未识别谓词忽略）。 */
  private static parseWhere(clause: string, query: DataViewQuery): void {
    const parts: string[] = clause.split(' AND ');
    for (let index = 0; index < parts.length; index++) {
      const part: string = parts[index].trim();
      if (part.length === 0) {
        continue;
      }
      const negated: boolean = part.startsWith('!');
      const body: string = negated ? part.substring(1).trim() : part;
      if (body === 'completed') {
        query.requireIncomplete = negated;
        query.requireCompleted = !negated;
        continue;
      }
      const tagMatch: RegExpExecArray | null =
        /contains\s*\(\s*tags\s*,\s*["']#?([^"']+)["']\s*\)/i.exec(body);
      if (tagMatch !== null) {
        query.requiredTags.push(tagMatch[1]);
        continue;
      }
      const textMatch: RegExpExecArray | null =
        /contains\s*\(\s*text\s*,\s*["']([^"']*)["']\s*\)/i.exec(body);
      if (textMatch !== null) {
        query.containsText = textMatch[1];
        continue;
      }
      if (/file\.name\s*!=\s*this\.file\.name/i.test(body)) {
        query.excludeCurrent = true;
        continue;
      }
    }
  }

  /** 任务行是否满足查询条件。 */
  public matches(rawLine: string, checked: boolean): boolean {
    if (this.requireCompleted && !checked) {
      return false;
    }
    if (this.requireIncomplete && checked) {
      return false;
    }
    for (let index = 0; index < this.requiredTags.length; index++) {
      if (!rawLine.includes(`#${this.requiredTags[index]}`)) {
        return false;
      }
    }
    if (this.containsText.length > 0 && !rawLine.includes(this.containsText)) {
      return false;
    }
    return true;
  }
}
