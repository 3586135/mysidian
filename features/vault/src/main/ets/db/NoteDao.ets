import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { NoteRow } from '@ohos/domain';
import { DbHelper } from './DbHelper';

/** 笔记表数据访问。 */
export class NoteDao {
  /** 按 (vault_id, path) 覆盖写入笔记元数据，返回笔记主键。 */
  public static async upsert(context: common.Context, row: NoteRow): Promise<number> {
    const store = await DbHelper.getStore();
    const now: number = Date.now();
    const args: Array<relationalStore.ValueType> = [
      row.vaultId,
      row.path,
      row.title,
      row.ext,
      row.mtime,
      row.size,
      row.hash,
      row.frontmatter,
      now,
      now
    ];
    await store.executeSql(
      'INSERT INTO note (vault_id, path, title, ext, mtime, size, hash, frontmatter, created_at, updated_at) ' +
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ' +
      'ON CONFLICT(vault_id, path) DO UPDATE SET title = excluded.title, ext = excluded.ext, ' +
      'mtime = excluded.mtime, size = excluded.size, hash = excluded.hash, ' +
      'frontmatter = excluded.frontmatter, updated_at = excluded.updated_at', args);
    const found: NoteRow | null = await NoteDao.findByPath(context, row.vaultId, row.path);
    return found === null ? 0 : found.id;
  }

  /** 按相对路径查询笔记。 */
  public static async findByPath(context: common.Context, vaultId: number,
    path: string): Promise<NoteRow | null> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [vaultId, path];
    const result = await store.querySql(
      'SELECT id, vault_id, path, title, ext, mtime, size, hash, frontmatter FROM note ' +
      'WHERE vault_id = ? AND path = ? LIMIT 1', args);
    let row: NoteRow | null = null;
    if (result.goToFirstRow()) {
      row = NoteDao.readRow(result);
    }
    result.close();
    return row;
  }

  /** 查询仓库下全部笔记。 */
  public static async listByVault(context: common.Context,
    vaultId: number): Promise<NoteRow[]> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [vaultId];
    const result = await store.querySql(
      'SELECT id, vault_id, path, title, ext, mtime, size, hash, frontmatter FROM note ' +
      'WHERE vault_id = ? ORDER BY path ASC', args);
    const rows: NoteRow[] = [];
    if (result.goToFirstRow()) {
      do {
        rows.push(NoteDao.readRow(result));
      } while (result.goToNextRow());
    }
    result.close();
    return rows;
  }

  /** 统计仓库笔记数量。 */
  public static async count(context: common.Context, vaultId: number): Promise<number> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [vaultId];
    const result = await store.querySql('SELECT COUNT(*) FROM note WHERE vault_id = ?', args);
    let count: number = 0;
    if (result.goToFirstRow()) {
      count = result.getLong(0);
    }
    result.close();
    return count;
  }

  /** 删除仓库下全部笔记记录（重新索引前调用）。 */
  public static async removeByVault(context: common.Context,
    vaultId: number): Promise<void> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [vaultId];
    await store.executeSql(
      'DELETE FROM block WHERE note_id IN (SELECT id FROM note WHERE vault_id = ?)', args);
    await store.executeSql(
      'DELETE FROM link WHERE source_note_id IN (SELECT id FROM note WHERE vault_id = ?)', args);
    await store.executeSql(
      'DELETE FROM tag WHERE note_id IN (SELECT id FROM note WHERE vault_id = ?)', args);
    await store.executeSql(
      'DELETE FROM prop WHERE note_id IN (SELECT id FROM note WHERE vault_id = ?)', args);
    await store.executeSql('DELETE FROM note WHERE vault_id = ?', args);
  }

  /**
   * 更新笔记的相对路径（重命名 / 移动）。
   * 必须保持主键不变：block / link / tag / prop 均以 note_id 关联，
   * 删表重建会连带丢失引用并带来不必要的重建开销。
   */
  public static async updatePath(context: common.Context, vaultId: number, oldPath: string,
    newPath: string, newTitle: string): Promise<void> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [newPath, newTitle, Date.now(), vaultId, oldPath];
    await store.executeSql(
      'UPDATE note SET path = ?, title = ?, updated_at = ? WHERE vault_id = ? AND path = ?', args);
  }

  /** 删除单篇笔记的全部索引记录（移入回收站时调用）。 */
  public static async removeByPath(context: common.Context, vaultId: number,
    path: string): Promise<void> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [vaultId, path];
    await store.executeSql(
      'DELETE FROM block WHERE note_id IN (SELECT id FROM note WHERE vault_id = ? AND path = ?)', args);
    await store.executeSql(
      'DELETE FROM link WHERE source_note_id IN (SELECT id FROM note WHERE vault_id = ? AND path = ?)',
      args);
    await store.executeSql(
      'DELETE FROM tag WHERE note_id IN (SELECT id FROM note WHERE vault_id = ? AND path = ?)', args);
    await store.executeSql(
      'DELETE FROM prop WHERE note_id IN (SELECT id FROM note WHERE vault_id = ? AND path = ?)', args);
    await store.executeSql('DELETE FROM note WHERE vault_id = ? AND path = ?', args);
  }

  /** 查询指定路径前缀下的笔记相对路径（清空回收站时使用）。 */
  public static async listByPathPrefix(context: common.Context, vaultId: number,
    prefix: string): Promise<string[]> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [vaultId, `${prefix}%`];
    const result = await store.querySql(
      'SELECT path FROM note WHERE vault_id = ? AND path LIKE ? ORDER BY path ASC', args);
    const paths: string[] = [];
    if (result.goToFirstRow()) {
      do {
        paths.push(result.getString(0));
      } while (result.goToNextRow());
    }
    result.close();
    return paths;
  }

  private static readRow(result: relationalStore.ResultSet): NoteRow {
    const row: NoteRow = new NoteRow();
    row.id = result.getLong(0);
    row.vaultId = result.getLong(1);
    row.path = result.getString(2);
    row.title = result.getString(3);
    row.ext = result.getString(4);
    row.mtime = result.getLong(5);
    row.size = result.getLong(6);
    row.hash = result.getString(7);
    row.frontmatter = result.getString(8);
    return row;
  }
}
