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
