import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BacklinkItem, LinkKind, LinkRef } from '@ohos/domain';
import { DbHelper } from './DbHelper';

/** 链接索引数据访问（反向链接来源于此）。 */
export class LinkDao {
  /** 覆盖写入一篇笔记的链接索引。 */
  public static async replaceForNote(context: common.Context, noteId: number,
    links: LinkRef[]): Promise<void> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [noteId];
    await store.executeSql('DELETE FROM link WHERE source_note_id = ?', args);
    for (const link of links) {
      const insertArgs: Array<relationalStore.ValueType> = [
        noteId,
        link.targetRaw,
        link.targetPath,
        link.targetNoteId,
        link.kind,
        link.context
      ];
      await store.executeSql(
        'INSERT INTO link (source_note_id, target_raw, target_path, target_note_id, kind, link_context) ' +
        'VALUES (?, ?, ?, ?, ?, ?)', insertArgs);
    }
  }

  /** 查询指向目标笔记的反向链接。 */
  public static async backlinks(context: common.Context, targetPath: string): Promise<BacklinkItem[]> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [targetPath];
    const result = await store.querySql(
      'SELECT n.id, n.path, n.title, l.link_context FROM link l ' +
      'JOIN note n ON n.id = l.source_note_id WHERE l.target_path = ? ORDER BY n.path ASC', args);
    const items: BacklinkItem[] = [];
    if (result.goToFirstRow()) {
      do {
        const item: BacklinkItem = new BacklinkItem();
        item.sourceNoteId = result.getLong(0);
        item.sourcePath = result.getString(1);
        item.sourceTitle = result.getString(2);
        item.context = result.getString(3);
        items.push(item);
      } while (result.goToNextRow());
    }
    result.close();
    return items;
  }

  /** 查询一篇笔记的所有出链。 */
  public static async outgoing(context: common.Context, noteId: number): Promise<LinkRef[]> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [noteId];
    const result = await store.querySql(
      'SELECT target_raw, target_path, target_note_id, kind, link_context FROM link ' +
      'WHERE source_note_id = ? ORDER BY id ASC', args);
    const links: LinkRef[] = [];
    if (result.goToFirstRow()) {
      do {
        const link: LinkRef = new LinkRef();
        link.sourceNoteId = noteId;
        link.targetRaw = result.getString(0);
        link.targetPath = result.getString(1);
        link.targetNoteId = result.getLong(2);
        link.kind = LinkDao.parseKind(result.getString(3));
        link.context = result.getString(4);
        link.resolved = link.targetPath.length > 0;
        links.push(link);
      } while (result.goToNextRow());
    }
    result.close();
    return links;
  }

  private static parseKind(value: string): LinkKind {
    if (value === 'embed') {
      return LinkKind.EMBED;
    }
    if (value === 'markdown') {
      return LinkKind.MARKDOWN;
    }
    if (value === 'tag') {
      return LinkKind.TAG;
    }
    return LinkKind.WIKI_LINK;
  }
}
