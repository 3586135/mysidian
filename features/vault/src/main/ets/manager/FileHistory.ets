import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { VaultInfo } from '@ohos/domain';
import { Logger } from '@ohos/common';
import { VaultPath } from './VaultPath';

const LOG: Logger = new Logger('MySidianHistory');

/** 一条历史快照。 */
export class HistorySnapshot {
  /** 快照文件名。 */
  name: string = '';
  /** 快照时间戳（毫秒）。 */
  timestamp: number = 0;
  /** 快照对应的仓库相对路径。 */
  path: string = '';
}

/** Diff 结果的一行。 */
export class DiffLine {
  /** 标记：'-' 删除 / '+' 新增 / ' ' 相同。 */
  marker: string = ' ';
  /** 行文本。 */
  text: string = '';
}

/**
 * 本地文件历史：保存与同步覆盖前保留最近 N 份快照，支持对比与一键回滚。
 *
 * 快照目录为仓库根下的 .history（以 '.' 开头，不会出现在文件树、索引与同步中）。
 */
export class FileHistory {
  /** 快照目录名。 */
  public static readonly DIR: string = '.history';
  /** 每篇笔记保留的快照数量上限。 */
  public static readonly MAX_SNAPSHOTS: number = 20;

  /**
   * 为笔记保存一份快照（覆盖前的旧内容）。
   *
   * @param context 应用上下文
   * @param vault 当前仓库
   * @param relativePath 笔记相对路径
   */
  public static async snapshot(context: common.Context, vault: VaultInfo,
    relativePath: string): Promise<void> {
    try {
      const absolute: string = VaultPath.absolute(vault.rootPath, relativePath);
      if (!fileIo.accessSync(absolute)) {
        return;
      }
      const stat = fileIo.statSync(absolute);
      if (stat.size === 0) {
        return;
      }
      const dir: string = VaultPath.absolute(vault.rootPath, FileHistory.DIR);
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
      const encoded: string = FileHistory.encodePath(relativePath);
      const name: string = `${encoded}.${Date.now()}.md`;
      const source = fileIo.openSync(absolute, fileIo.OpenMode.READ_ONLY);
      const target = fileIo.openSync(`${dir}/${name}`,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.copyFileSync(source.fd, target.fd);
      } finally {
        fileIo.closeSync(source);
        fileIo.closeSync(target);
      }
      FileHistory.prune(dir, encoded);
    } catch (error) {
      const err = error as BusinessError;
      LOG.warn(`snapshot failed, code=${err.code}, message=${err.message}`);
    }
  }

  /**
   * 列出某篇笔记的历史快照（按时间倒序）。
   * 兼容读取旧编码（斜杠直替 `__`）的历史快照。
   */
  public static async list(vault: VaultInfo, relativePath: string): Promise<HistorySnapshot[]> {
    const items: HistorySnapshot[] = [];
    const dir: string = VaultPath.absolute(vault.rootPath, FileHistory.DIR);
    if (!fileIo.accessSync(dir)) {
      return items;
    }
    const names: string[] = fileIo.listFileSync(dir);
    for (const name of names) {
      const prefix: string | null = FileHistory.matchPrefix(name, relativePath);
      if (prefix === null || !name.endsWith('.md')) {
        continue;
      }
      const item: HistorySnapshot = new HistorySnapshot();
      item.name = name;
      item.path = relativePath;
      const stampText: string = name.substring(prefix.length, name.length - 3);
      const stamp: number = Number(stampText);
      item.timestamp = Number.isNaN(stamp) ? 0 : stamp;
      items.push(item);
    }
    items.sort((a: HistorySnapshot, b: HistorySnapshot): number => b.timestamp - a.timestamp);
    return items;
  }

  /**
   * 读取快照内容。
   */
  public static async read(vault: VaultInfo, relativePath: string, name: string): Promise<string> {
    const path: string = `${VaultPath.absolute(vault.rootPath, FileHistory.DIR)}/${name}`;
    if (!fileIo.accessSync(path)) {
      return '';
    }
    return fileIo.readTextSync(path);
  }

  /**
   * 回滚到指定快照：把快照内容写回笔记文件。
   * 覆盖前先对现行内容快照——否则回滚目标之后的所有编辑
   * （若无更早快照兜底）将被永久丢弃。
   */
  public static async rollback(vault: VaultInfo, relativePath: string, name: string): Promise<boolean> {
    const content: string = await FileHistory.read(vault, relativePath, name);
    if (content.length === 0) {
      return false;
    }
    const absolute: string = VaultPath.absolute(vault.rootPath, relativePath);
    if (fileIo.accessSync(absolute)) {
      const dir: string = VaultPath.absolute(vault.rootPath, FileHistory.DIR);
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
      const encoded: string = FileHistory.encodePath(relativePath);
      const currentName: string = `${encoded}.${Date.now()}.md`;
      const source = fileIo.openSync(absolute, fileIo.OpenMode.READ_ONLY);
      const target = fileIo.openSync(`${dir}/${currentName}`,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.copyFileSync(source.fd, target.fd);
      } finally {
        fileIo.closeSync(source);
        fileIo.closeSync(target);
      }
      FileHistory.prune(dir, encoded);
    }
    const file = fileIo.openSync(absolute,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, content);
      fileIo.fsyncSync(file.fd);
    } finally {
      fileIo.closeSync(file);
    }
    return true;
  }

  /**
   * 删除快照。
   */
  public static async remove(vault: VaultInfo, name: string): Promise<void> {
    const path: string = `${VaultPath.absolute(vault.rootPath, FileHistory.DIR)}/${name}`;
    if (fileIo.accessSync(path)) {
      fileIo.unlinkSync(path);
    }
  }

  /**
   * 行级 Diff（LCS 算法）。
   *
   * @param before 旧内容
   * @param after 新内容
   * @returns 逐行差异
   */
  public static diff(before: string, after: string): DiffLine[] {
    const oldLines: string[] = before.split('\n');
    const newLines: string[] = after.split('\n');
    const rows: number = oldLines.length;
    const cols: number = newLines.length;
    // LCS 长度表
    const table: number[][] = [];
    for (let i = 0; i <= rows; i++) {
      const row: number[] = new Array<number>(cols + 1).fill(0);
      table.push(row);
    }
    for (let i = 1; i <= rows; i++) {
      for (let j = 1; j <= cols; j++) {
        if (oldLines[i - 1] === newLines[j - 1]) {
          table[i][j] = table[i - 1][j - 1] + 1;
        } else {
          table[i][j] = Math.max(table[i - 1][j], table[i][j - 1]);
        }
      }
    }
    const result: DiffLine[] = [];
    let i: number = rows;
    let j: number = cols;
    while (i > 0 && j > 0) {
      if (oldLines[i - 1] === newLines[j - 1]) {
        const same: DiffLine = new DiffLine();
        same.marker = ' ';
        same.text = oldLines[i - 1];
        result.push(same);
        i--;
        j--;
      } else if (table[i - 1][j] >= table[i][j - 1]) {
        const removed: DiffLine = new DiffLine();
        removed.marker = '-';
        removed.text = oldLines[i - 1];
        result.push(removed);
        i--;
      } else {
        const added: DiffLine = new DiffLine();
        added.marker = '+';
        added.text = newLines[j - 1];
        result.push(added);
        j--;
      }
    }
    while (i > 0) {
      const removed: DiffLine = new DiffLine();
      removed.marker = '-';
      removed.text = oldLines[i - 1];
      result.push(removed);
      i--;
    }
    while (j > 0) {
      const added: DiffLine = new DiffLine();
      added.marker = '+';
      added.text = newLines[j - 1];
      result.push(added);
      j--;
    }
    result.reverse();
    return result;
  }

  /**
   * 把相对路径编码为快照文件名前缀。
   * 先转义字面下划线（`_`→`_u`）再替换斜杠（`/`→`__`），
   * 否则 `a/b.md` 与字面名 `a__b.md` 编码相同，快照互相污染、
   * prune 会跨笔记误删。
   */
  private static encodePath(relativePath: string): string {
    return relativePath.split('_').join('_u').split('/').join('__');
  }

  /** 旧编码（斜杠直替双下划线），仅用于兼容读取历史快照。 */
  private static encodePathLegacy(relativePath: string): string {
    return relativePath.split('/').join('__');
  }

  /** 判断快照文件名属于该笔记（新/旧编码），命中返回所用前缀，否则 null。 */
  private static matchPrefix(name: string, relativePath: string): string | null {
    const modern: string = `${FileHistory.encodePath(relativePath)}.`;
    if (name.startsWith(modern)) {
      return modern;
    }
    const legacy: string = `${FileHistory.encodePathLegacy(relativePath)}.`;
    if (legacy !== modern && name.startsWith(legacy)) {
      return legacy;
    }
    return null;
  }

  /** 清理超出数量上限的旧快照（含旧编码快照，统一计入配额）。 */
  private static prune(dir: string, encoded: string): void {
    const names: string[] = fileIo.listFileSync(dir);
    const matched: string[] = [];
    for (const name of names) {
      if (name.startsWith(`${encoded}.`) && name.endsWith('.md')) {
        matched.push(name);
      }
    }
    if (matched.length <= FileHistory.MAX_SNAPSHOTS) {
      return;
    }
    matched.sort();
    const excess: number = matched.length - FileHistory.MAX_SNAPSHOTS;
    for (let index = 0; index < excess; index++) {
      const path: string = `${dir}/${matched[index]}`;
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    }
  }
}
