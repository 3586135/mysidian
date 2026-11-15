import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { MdBlock, MdBlockType, MdInline, OutlineEntry } from '@ohos/domain';
import { DbHelper } from './DbHelper';

/** 块级索引数据访问（大纲来源于此）。 */
export class BlockDao {
  /** 覆盖写入一篇笔记的块索引。 */
  public static async replaceForNote(context: common.Context, noteId: number,
    blocks: MdBlock[]): Promise<void> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [noteId];
    await store.executeSql('DELETE FROM block WHERE note_id = ?', args);
    let ordinal: number = 0;
    for (const block of blocks) {
      const insertArgs: Array<relationalStore.ValueType> = [
        noteId,
        ordinal,
        block.type,
        BlockDao.plainText(block),
        block.level,
        block.lang
      ];
      await store.executeSql(
        'INSERT INTO block (note_id, ordinal, type, block_text, level, lang) VALUES (?, ?, ?, ?, ?, ?)',
        insertArgs);
      ordinal++;
    }
  }

  /** 统计一篇笔记的块数量（用于判断是否已建立索引）。 */
  public static async countOfNote(context: common.Context, noteId: number): Promise<number> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [noteId];
    const result = await store.querySql('SELECT COUNT(*) FROM block WHERE note_id = ?', args);
    let count: number = 0;
    if (result.goToFirstRow()) {
      count = result.getLong(0);
    }
    result.close();
    return count;
  }

  /** 查询笔记的大纲（标题块）。 */
  public static async outline(context: common.Context, noteId: number): Promise<OutlineEntry[]> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [noteId, MdBlockType.HEADING];
    const result = await store.querySql(
      'SELECT ordinal, level, block_text FROM block WHERE note_id = ? AND type = ? ORDER BY ordinal ASC',
      args);
    const entries: OutlineEntry[] = [];
    if (result.goToFirstRow()) {
      do {
        const entry: OutlineEntry = new OutlineEntry();
        entry.ordinal = result.getLong(0);
        entry.level = result.getLong(1);
        entry.text = result.getString(2);
        entries.push(entry);
      } while (result.goToNextRow());
    }
    result.close();
    return entries;
  }

  /**
   * 在块索引中批量检索包含指定标题文本的笔记及首个命中块文本，
   * 供「未链接提及」直接走 RDB 索引，避免逐篇读文件。
   */
  public static async findMentions(context: common.Context, vaultId: number,
    keyword: string, excludePath: string): Promise<Map<string, string>> {
    const map: Map<string, string> = new Map<string, string>();
    if (keyword.length === 0) {
      return map;
    }
    const store = await DbHelper.getStore();
    const escaped: string = keyword.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
    const args: Array<relationalStore.ValueType> = [vaultId, excludePath, `%${escaped}%`];
    const result = await store.querySql(
      'SELECT n.path, b.block_text FROM block b JOIN note n ON n.id = b.note_id ' +
      'WHERE n.vault_id = ? AND n.path != ? AND b.block_text LIKE ? ESCAPE \'\\\' ' +
      'ORDER BY n.path ASC, b.ordinal ASC', args);
    if (result.goToFirstRow()) {
      do {
        const notePath: string = result.getString(0);
        if (!map.has(notePath)) {
          map.set(notePath, result.getString(1));
        }
      } while (result.goToNextRow());
    }
    result.close();
    return map;
  }

  /** 提取块内纯文本。 */
  public static plainTextOfBlock(block: MdBlock): string {
    if (block.inlines.length === 0) {
      return block.rawContent;
    }
    let text: string = '';
    for (const inline of block.inlines) {
      text += BlockDao.inlineText(inline);
    }
    return text;
  }

  private static plainText(block: MdBlock): string {
    return BlockDao.plainTextOfBlock(block);
  }

  private static inlineText(inline: MdInline): string {
    if (inline.children.length > 0) {
      let text: string = '';
      for (const child of inline.children) {
        text += BlockDao.inlineText(child);
      }
      return text;
    }
    return inline.text;
  }
}
