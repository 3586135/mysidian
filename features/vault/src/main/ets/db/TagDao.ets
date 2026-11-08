import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { TagRef } from '@ohos/domain';
import { DbHelper } from './DbHelper';

/** 标签索引数据访问。 */
export class TagDao {
  /** 覆盖写入一篇笔记的标签。 */
  public static async replaceForNote(context: common.Context, noteId: number,
    tags: string[]): Promise<void> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [noteId];
    await store.executeSql('DELETE FROM tag WHERE note_id = ?', args);
    for (const tag of tags) {
      if (tag.length === 0) {
        continue;
      }
      const insertArgs: Array<relationalStore.ValueType> = [noteId, tag];
      await store.executeSql('INSERT OR IGNORE INTO tag (note_id, tag) VALUES (?, ?)', insertArgs);
    }
  }

  /** 查询一篇笔记的标签。 */
  public static async tagsOfNote(context: common.Context, noteId: number): Promise<string[]> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [noteId];
    const result = await store.querySql('SELECT tag FROM tag WHERE note_id = ? ORDER BY tag ASC', args);
    const tags: string[] = [];
    if (result.goToFirstRow()) {
      do {
        tags.push(result.getString(0));
      } while (result.goToNextRow());
    }
    result.close();
    return tags;
  }

  /** 查询仓库内全部标签及引用次数。 */
  public static async listAll(context: common.Context, vaultId: number): Promise<TagRef[]> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [vaultId];
    const result = await store.querySql(
      'SELECT t.tag, COUNT(*) FROM tag t JOIN note n ON n.id = t.note_id ' +
      'WHERE n.vault_id = ? GROUP BY t.tag ORDER BY t.tag ASC', args);
    const tags: TagRef[] = [];
    if (result.goToFirstRow()) {
      do {
        const tag: TagRef = new TagRef();
        tag.tag = result.getString(0);
        tag.count = result.getLong(1);
        tags.push(tag);
      } while (result.goToNextRow());
    }
    result.close();
    return tags;
  }

  /** 查询使用指定标签的笔记路径。 */
  public static async notesByTag(context: common.Context, vaultId: number,
    tag: string): Promise<string[]> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [vaultId, tag];
    const result = await store.querySql(
      'SELECT n.path FROM tag t JOIN note n ON n.id = t.note_id ' +
      'WHERE n.vault_id = ? AND t.tag = ? ORDER BY n.path ASC', args);
    const paths: string[] = [];
    if (result.goToFirstRow()) {
      do {
        paths.push(result.getString(0));
      } while (result.goToNextRow());
    }
    result.close();
    return paths;
  }
}
