/** 表格列对齐方式。 */
export type WysiwygTableAlign = 'left' | 'center' | 'right';

/** Markdown 表格结构化模型（用于 WYSIWYG 真表格渲染与网格编辑）。 */
export class WysiwygTableData {
  headers: string[] = ['列1', '列2'];
  aligns: WysiwygTableAlign[] = ['left', 'left'];
  rows: string[][] = [['', '']];

  public clone(): WysiwygTableData {
    const copy: WysiwygTableData = new WysiwygTableData();
    copy.headers = this.headers.slice();
    copy.aligns = this.aligns.slice();
    copy.rows = [];
    for (const r of this.rows) {
      copy.rows.push(r.slice());
    }
    return copy;
  }
}

/**
 * Markdown 表格与结构化网格模型无损互转工具：
 * - 正确处理单元格内的转义竖线 `\|` 与行内代码 `` `a|b` ``
 * - 自动归一化不规则列数并保留对齐方式 (`:---`, `:---:`, `---:`)
 */
export class WysiwygTableCodec {
  /** 判断一行文本是否为 Markdown 表格对齐分隔行。 */
  public static isDelimiterLine(trimmed: string): boolean {
    if (trimmed.length === 0 || !trimmed.includes('-')) {
      return false;
    }
    return /^\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?$/.test(trimmed);
  }

  /** 将一行 Markdown 表格行拆分为单元格文本（尊重 `\|` 转义与行内代码）。 */
  public static splitRow(line: string): string[] {
    let trimmed: string = line.trim();
    if (trimmed.startsWith('|')) {
      trimmed = trimmed.substring(1);
    }
    if (trimmed.endsWith('|') && !(trimmed.length >= 2 && trimmed.charAt(trimmed.length - 2) === '\\')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    const cells: string[] = [];
    let cur: string = '';
    let inBackticks: boolean = false;
    let i: number = 0;
    while (i < trimmed.length) {
      const ch: string = trimmed.charAt(i);
      if (ch === '\\' && i + 1 < trimmed.length && trimmed.charAt(i + 1) === '|') {
        cur += '|';
        i += 2;
        continue;
      }
      if (ch === '`') {
        inBackticks = !inBackticks;
        cur += ch;
        i++;
        continue;
      }
      if (ch === '|' && !inBackticks) {
        cells.push(cur.trim());
        cur = '';
        i++;
        continue;
      }
      cur += ch;
      i++;
    }
    cells.push(cur.trim());
    return cells;
  }

  /** 解析分隔行各列对齐方式。 */
  public static parseAligns(delimiterLine: string, colCount: number): WysiwygTableAlign[] {
    const rawCells: string[] = WysiwygTableCodec.splitRow(delimiterLine);
    const aligns: WysiwygTableAlign[] = [];
    for (let i: number = 0; i < colCount; i++) {
      const cell: string = i < rawCells.length ? rawCells[i].trim() : '---';
      const left: boolean = cell.startsWith(':');
      const right: boolean = cell.endsWith(':');
      if (left && right) {
        aligns.push('center');
      } else if (right) {
        aligns.push('right');
      } else {
        aligns.push('left');
      }
    }
    return aligns;
  }

  /** 从原始 Markdown 表格多行文本解析结构化表格。 */
  public static parseFromMarkdown(rawMd: string): WysiwygTableData {
    const lines: string[] = rawMd.split('\n').filter((l: string): boolean => l.trim().length > 0);
    return WysiwygTableCodec.parseFromMarkdownLines(lines);
  }

  /** 从按行切分好的 Markdown 表格行解析结构化表格。 */
  public static parseFromMarkdownLines(lines: string[]): WysiwygTableData {
    if (lines.length === 0) {
      return WysiwygTableCodec.defaultTable();
    }
    const headerCells: string[] = WysiwygTableCodec.splitRow(lines[0]);
    const hasDelim: boolean = lines.length >= 2 && WysiwygTableCodec.isDelimiterLine(lines[1].trim());
    const delimCells: string[] = hasDelim ? WysiwygTableCodec.splitRow(lines[1]) : [];
    const dataStart: number = hasDelim ? 2 : 1;

    let colCount: number = Math.max(headerCells.length, delimCells.length, 1);
    const rawRows: string[][] = [];
    for (let r: number = dataStart; r < lines.length; r++) {
      const cells: string[] = WysiwygTableCodec.splitRow(lines[r]);
      if (cells.length > colCount) {
        colCount = cells.length;
      }
      rawRows.push(cells);
    }

    const table: WysiwygTableData = new WysiwygTableData();
    table.headers = [];
    for (let c: number = 0; c < colCount; c++) {
      table.headers.push(c < headerCells.length ? headerCells[c] : '');
    }
    table.aligns = hasDelim
      ? WysiwygTableCodec.parseAligns(lines[1], colCount)
      : WysiwygTableCodec.buildDefaultAligns(colCount);
    table.rows = [];
    for (const row of rawRows) {
      const normalized: string[] = [];
      for (let c: number = 0; c < colCount; c++) {
        normalized.push(c < row.length ? row[c] : '');
      }
      table.rows.push(normalized);
    }
    return table;
  }

  /** 序列化结构化表格回标准 Markdown 表格文本。 */
  public static toMarkdown(table: WysiwygTableData): string {
    return WysiwygTableCodec.toMarkdownLines(table).join('\n');
  }

  /** 序列化结构化表格回标准 Markdown 表格行数组。 */
  public static toMarkdownLines(table: WysiwygTableData): string[] {
    const colCount: number = Math.max(table.headers.length, 1);
    const out: string[] = [];

    const headCells: string[] = [];
    const delimCells: string[] = [];
    for (let c: number = 0; c < colCount; c++) {
      const h: string = c < table.headers.length ? table.headers[c] : '';
      headCells.push(WysiwygTableCodec.escapeCell(h));
      const align: WysiwygTableAlign = c < table.aligns.length ? table.aligns[c] : 'left';
      if (align === 'center') {
        delimCells.push(':---:');
      } else if (align === 'right') {
        delimCells.push('---:');
      } else {
        delimCells.push('---');
      }
    }
    out.push(`| ${headCells.join(' | ')} |`);
    out.push(`| ${delimCells.join(' | ')} |`);

    for (const row of table.rows) {
      const cells: string[] = [];
      for (let c: number = 0; c < colCount; c++) {
        cells.push(WysiwygTableCodec.escapeCell(c < row.length ? row[c] : ''));
      }
      out.push(`| ${cells.join(' | ')} |`);
    }
    return out;
  }

  /** 创建默认示例空表格（默认 2 列 1 数据行）。 */
  public static defaultTable(cols: number = 2, dataRows: number = 1): WysiwygTableData {
    const colCount: number = Math.max(1, cols);
    const table: WysiwygTableData = new WysiwygTableData();
    table.headers = [];
    table.aligns = [];
    for (let c: number = 0; c < colCount; c++) {
      table.headers.push(`列${c + 1}`);
      table.aligns.push('left');
    }
    table.rows = [];
    for (let r: number = 0; r < Math.max(0, dataRows); r++) {
      const row: string[] = [];
      for (let c: number = 0; c < colCount; c++) {
        row.push('');
      }
      table.rows.push(row);
    }
    return table;
  }

  /** 切换指定列的对齐方式（left -> center -> right -> left）。 */
  public static cycleAlign(table: WysiwygTableData, colIdx: number): void {
    if (colIdx < 0 || colIdx >= table.aligns.length) {
      return;
    }
    const cur: WysiwygTableAlign = table.aligns[colIdx];
    if (cur === 'left') {
      table.aligns[colIdx] = 'center';
    } else if (cur === 'center') {
      table.aligns[colIdx] = 'right';
    } else {
      table.aligns[colIdx] = 'left';
    }
  }

  /** 在末尾追加空白数据行。 */
  public static appendRow(table: WysiwygTableData): void {
    const colCount: number = Math.max(1, table.headers.length);
    const nextRow: string[] = [];
    for (let c: number = 0; c < colCount; c++) {
      nextRow.push('');
    }
    table.rows.push(nextRow);
  }

  /** 删除指定数据行。 */
  public static removeRow(table: WysiwygTableData, rowIdx: number): void {
    if (rowIdx < 0 || rowIdx >= table.rows.length) {
      return;
    }
    table.rows.splice(rowIdx, 1);
  }

  /** 在末尾追加新列。 */
  public static appendColumn(table: WysiwygTableData): void {
    const nextIdx: number = table.headers.length + 1;
    table.headers.push(`列${nextIdx}`);
    table.aligns.push('left');
    for (const row of table.rows) {
      row.push('');
    }
  }

  /** 删除指定列（至少保留 1 列）。 */
  public static removeColumn(table: WysiwygTableData, colIdx: number): void {
    if (table.headers.length <= 1 || colIdx < 0 || colIdx >= table.headers.length) {
      return;
    }
    table.headers.splice(colIdx, 1);
    if (colIdx < table.aligns.length) {
      table.aligns.splice(colIdx, 1);
    }
    for (const row of table.rows) {
      if (colIdx < row.length) {
        row.splice(colIdx, 1);
      }
    }
  }

  private static buildDefaultAligns(count: number): WysiwygTableAlign[] {
    const aligns: WysiwygTableAlign[] = [];
    for (let i: number = 0; i < count; i++) {
      aligns.push('left');
    }
    return aligns;
  }

  private static escapeCell(raw: string): string {
    const singleLine: string = raw.replace(/\r?\n/g, ' ').trim();
    if (singleLine.length === 0) {
      return '';
    }
    let out: string = '';
    let inBackticks: boolean = false;
    let i: number = 0;
    while (i < singleLine.length) {
      const ch: string = singleLine.charAt(i);
      if (ch === '`') {
        inBackticks = !inBackticks;
        out += ch;
        i++;
        continue;
      }
      if (ch === '|' && !inBackticks) {
        const escapedAlready: boolean = i > 0 && singleLine.charAt(i - 1) === '\\';
        out += escapedAlready ? '|' : '\\|';
        i++;
        continue;
      }
      out += ch;
      i++;
    }
    return out;
  }
}
