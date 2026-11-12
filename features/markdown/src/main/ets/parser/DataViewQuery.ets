import { MdListItem } from '@ohos/domain';

/**
 * Obsidian-Dataview 查询解析（MVP 子集）：
 * - TASK 查询：WHERE 谓词（completed / !completed / contains(tags, "#x") /
 *   contains(text, "…") / file.name != this.file.name / FROM #tag）+ GROUP BY file.link。
 * - TABLE / LIST 查询：带 FROM 子句时为 live 查询（联动笔记索引），
 *   FROM #tag 或 FROM "folder"；TABLE 支持 WITHOUT ID 与属性列，LIST 支持单个属性。
 *   无 FROM 时回退为静态解析渲染（旧行为）。
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
  /** FROM #tag：来源标签（不含 #）。 */
  fromTag: string = '';
  /** FROM "folder"：来源目录。 */
  fromFolder: string = '';
  /** 是否为联动索引的 live 查询（TABLE/LIST 带 FROM 子句）。 */
  live: boolean = false;
  /** TABLE 请求的属性列（不含 File 首列）。 */
  tableProps: string[] = [];
  /** TABLE WITHOUT ID：不显示 File 首列。 */
  withoutId: boolean = false;
  /** LIST 请求的属性名（可为空）。 */
  listProp: string = '';
  /** TABLE 查询列头（解析后）。 */
  tableColumns: string[] = [];
  /** TABLE 查询数据行（每行=列值数组，静态回退用）。 */
  tableRows: string[][] = [];
  /** LIST 查询条目列表（静态回退用）。 */
  listItems: string[] = [];
  /** 解析是否成功（TABLE/LIST 用）。 */
  parsedOk: boolean = false;
  /** SORT 字段名（空表示不排序）。 */
  sortField: string = '';
  /** SORT 是否降序。 */
  sortDesc: boolean = false;
  /** LIMIT 条数（0 表示不限制）。 */
  limit: number = 0;
  /** 日期比较：due 与今天的比较算子（'' / '<' / '<=' / '>' / '>=' / '='）。 */
  dueOp: string = '';
  /** 日期比较：start 与今天的比较算子。 */
  startOp: string = '';
  /** 日期比较：scheduled 与今天的比较算子。 */
  scheduledOp: string = '';
  /** 日期比较字段名（due / start / scheduled，兼容旧读法）。 */
  dateField: string = '';

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
          DataViewQuery.parseTypeRest(line.substring(firstWord[1].length).trim(), query);
        }
        continue;
      }
      if (upper.startsWith('FROM')) {
        DataViewQuery.parseFrom(line.substring(4).trim(), query);
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
      if (upper.startsWith('SORT')) {
        DataViewQuery.parseSort(line.substring(4).trim(), query);
        continue;
      }
      if (upper.startsWith('LIMIT')) {
        const limitText: string = line.substring(5).trim();
        const limitValue: number = Number(limitText);
        if (!Number.isNaN(limitValue) && limitValue > 0) {
          query.limit = limitValue;
        }
        continue;
      }
      if (query.type === 'LIST' && !query.live) {
        query.parsedOk = true;
        query.listItems.push(line);
        continue;
      }
      if (query.type === 'TABLE' && !query.live && !query.parsedOk) {
        const headerLine: string = line.replace(/^\|/, '').replace(/\|$/, '').trim();
        query.tableColumns = headerLine.split('|').map((s: string) => s.trim());
        query.parsedOk = true;
        continue;
      }
      if (query.type === 'TABLE' && !query.live && query.parsedOk) {
        const rowValues: string = line.replace(/^\|/, '').replace(/\|$/, '').trim();
        const cells: string[] = rowValues.split('|').map((s: string) => s.trim());
        query.tableRows.push(cells);
        continue;
      }
    }
    DataViewQuery.finalize(query);
    return query;
  }

  /** 解析首行查询类型后的剩余部分（TABLE 列 / LIST 属性，可含行内 FROM）。 */
  private static parseTypeRest(rest: string, query: DataViewQuery): void {
    if (query.type === 'TABLE') {
      let body: string = rest;
      if (body.toUpperCase().startsWith('WITHOUT ID')) {
        query.withoutId = true;
        body = body.substring(10).trim();
      }
      const fromIndex: number = DataViewQuery.findInlineFrom(body);
      if (fromIndex >= 0) {
        DataViewQuery.parseFrom(body.substring(fromIndex + 4).trim(), query);
        body = body.substring(0, fromIndex).trim();
      }
      query.tableProps = DataViewQuery.splitColumns(body);
      return;
    }
    if (query.type === 'LIST') {
      let body: string = rest;
      const fromIndex: number = DataViewQuery.findInlineFrom(body);
      if (fromIndex >= 0) {
        DataViewQuery.parseFrom(body.substring(fromIndex + 4).trim(), query);
        body = body.substring(0, fromIndex).trim();
      }
      query.listProp = body;
      return;
    }
  }

  /** 查找行内 FROM 关键字位置（词边界），无则返回 -1。 */
  private static findInlineFrom(body: string): number {
    const match: RegExpExecArray | null = /(^|\s)FROM\s/i.exec(body);
    return match === null ? -1 : match.index + match[1].length;
  }

  /** 按逗号拆分列名（去引号与空白）。 */
  private static splitColumns(body: string): string[] {
    const props: string[] = [];
    if (body.length === 0) {
      return props;
    }
    for (const part of body.split(',')) {
      const trimmed: string = part.trim().replace(/^["']|["']$/g, '');
      if (trimmed.length > 0) {
        props.push(trimmed);
      }
    }
    return props;
  }

  /** 解析 FROM 子句来源：#tag 或 "folder"。 */
  private static parseFrom(source: string, query: DataViewQuery): void {
    const trimmed: string = source.trim();
    if (trimmed.length === 0) {
      return;
    }
    query.live = true;
    if (trimmed.startsWith('#')) {
      query.fromTag = trimmed.substring(1).trim();
      return;
    }
    let folder: string = trimmed;
    if (folder.length >= 2 && ((folder.startsWith('"') && folder.endsWith('"')) ||
      (folder.startsWith("'") && folder.endsWith("'")))) {
      folder = folder.substring(1, folder.length - 1);
    }
    query.fromFolder = folder;
  }

  /** live TABLE/LIST 查询收尾：生成显示列头并标记 parsedOk。 */
  private static finalize(query: DataViewQuery): void {
    if (!query.live) {
      return;
    }
    if (query.isTableQuery()) {
      const columns: string[] = [];
      if (!query.withoutId) {
        columns.push('File');
      }
      for (const prop of query.tableProps) {
        columns.push(prop);
      }
      query.tableColumns = columns;
      query.parsedOk = true;
      return;
    }
    if (query.isListQuery()) {
      query.parsedOk = true;
    }
  }

  /** 解析 SORT 子句：SORT field [ASC|DESC]。 */
  private static parseSort(clause: string, query: DataViewQuery): void {
    const trimmed: string = clause.trim();
    if (trimmed.length === 0) {
      return;
    }
    const parts: string[] = trimmed.split(/\s+/);
    query.sortField = parts[0].replace(/^["']|["']$/g, '');
    if (parts.length > 1) {
      query.sortDesc = parts[1].toUpperCase() === 'DESC';
    }
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
      const dateMatch: RegExpExecArray | null =
        /\b(due|start|scheduled)\b\s*(<=|>=|<|>|=)\s*(date\s*\(\s*today\s*\)|today|now\s*\(\s*\))/i
          .exec(body);
      if (dateMatch !== null) {
        DataViewQuery.parseDatePredicate(dateMatch[1].toLowerCase(), dateMatch[2], query);
        continue;
      }
    }
  }

  /** 记录日期比较条件（field 与今天的 operator 比较）。 */
  private static parseDatePredicate(field: string, operator: string, query: DataViewQuery): void {
    query.dateField = field;
    if (field === 'due') {
      query.dueOp = operator;
    } else if (field === 'start') {
      query.startOp = operator;
    } else {
      query.scheduledOp = operator;
    }
  }

  /**
   * 任务项是否满足查询条件（含日期比较）。
   * @param item 任务项（含 due / start / scheduled 元数据）
   */
  public matchesItem(item: MdListItem): boolean {
    if (!this.matches(item.rawLine, item.checked)) {
      return false;
    }
    return this.matchesDate(item);
  }

  /** 日期比较：把任务的 due / start / scheduled 按各自算子与今天比较。 */
  private matchesDate(item: MdListItem): boolean {
    const today: string = DataViewQuery.todayStamp();
    if (!DataViewQuery.matchDateOp(item.dueDate, this.dueOp, today)) {
      return false;
    }
    if (!DataViewQuery.matchDateOp(item.startDate, this.startOp, today)) {
      return false;
    }
    if (!DataViewQuery.matchDateOp(item.scheduledDate, this.scheduledOp, today)) {
      return false;
    }
    return true;
  }

  /** 单字段日期比较：无算子恒真；有算子但无值恒假。 */
  private static matchDateOp(value: string, op: string, today: string): boolean {
    if (op.length === 0) {
      return true;
    }
    if (value.length === 0) {
      return false;
    }
    if (op === '<') {
      return value < today;
    }
    if (op === '<=') {
      return value <= today;
    }
    if (op === '>') {
      return value > today;
    }
    if (op === '>=') {
      return value >= today;
    }
    return value === today;
  }

  /** 今天的日期戳（YYYY-MM-DD）。 */
  public static todayStamp(): string {
    const now: Date = new Date();
    const month: string = (now.getMonth() + 1) < 10
      ? `0${now.getMonth() + 1}` : `${now.getMonth() + 1}`;
    const day: string = now.getDate() < 10 ? `0${now.getDate()}` : `${now.getDate()}`;
    return `${now.getFullYear()}-${month}-${day}`;
  }

  /** 任务行是否满足查询条件（FROM #tag 为笔记级过滤，由宿主按页匹配，不在行内检查）。 */
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

  /** 页面级过滤（live TABLE/LIST）：标签 / 目录 / 文本 / 排除当前笔记。 */
  public matchesPage(content: string, frontTags: string[], path: string, currentPath: string): boolean {
    if (this.excludeCurrent && path === currentPath) {
      return false;
    }
    if (this.fromFolder.length > 0 &&
      !(path === this.fromFolder || path.startsWith(`${this.fromFolder}/`))) {
      return false;
    }
    const body: string = DataViewQuery.stripFencedCode(content);
    if (this.fromTag.length > 0 && !DataViewQuery.pageHasTag(body, frontTags, this.fromTag)) {
      return false;
    }
    for (const tag of this.requiredTags) {
      if (!DataViewQuery.pageHasTag(body, frontTags, tag)) {
        return false;
      }
    }
    if (this.containsText.length > 0 && !body.includes(this.containsText)) {
      return false;
    }
    return true;
  }

  /** TASK FROM #tag：笔记级标签匹配（frontmatter 标签或正文 #标签），无 FROM 恒真。 */
  public matchesPageSourceTag(content: string, frontTags: string[]): boolean {
    if (this.fromTag.length === 0) {
      return true;
    }
    const body: string = DataViewQuery.stripFencedCode(content);
    return DataViewQuery.pageHasTag(body, frontTags, this.fromTag);
  }

  /** 去除围栏代码块后再做文本匹配，避免查询块内的标签/文本自匹配。 */
  private static stripFencedCode(content: string): string {
    return content.replace(/```[\s\S]*?```/g, '');
  }

  /** 页面是否带指定标签：frontmatter 标签或正文 #标签。 */
  private static pageHasTag(content: string, frontTags: string[], tag: string): boolean {
    if (frontTags.includes(tag)) {
      return true;
    }
    return content.includes(`#${tag}`);
  }
}
