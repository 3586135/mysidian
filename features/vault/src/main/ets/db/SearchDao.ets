import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { SearchHit, SearchQuery } from '@ohos/domain';
import { DbHelper } from './DbHelper';
import { Tokenizer } from '../indexer/Tokenizer';

/**
 * 全文检索。
 * 优先使用 FTS5 虚表（MATCH），平台不支持时退化为 LIKE 扫描。
 */
export class SearchDao {
  /** 执行检索。 */
  public static async search(context: common.Context, vaultId: number,
    query: SearchQuery): Promise<SearchHit[]> {
    const keyword: string = query.text.trim();
    if (keyword.length === 0 && query.tag.length === 0) {
      return [];
    }
    if (DbHelper.isFtsReady()) {
      const hits: SearchHit[] = await SearchDao.searchByFts(vaultId, query);
      if (hits.length > 0) {
        await SearchDao.fillSnippets(vaultId, hits, keyword);
        return hits;
      }
      if (keyword.length === 0) {
        return hits;
      }
    }
    const fallback: SearchHit[] = await SearchDao.searchByLike(vaultId, query);
    await SearchDao.fillSnippets(vaultId, fallback, keyword);
    return fallback;
  }

  private static async searchByFts(vaultId: number, query: SearchQuery): Promise<SearchHit[]> {
    const store = await DbHelper.getStore();
    const expression: string = Tokenizer.buildMatchExpression(query.text);
    const args: Array<relationalStore.ValueType> = [];
    let sql: string = 'SELECT n.id, n.path, n.title FROM note_fts f JOIN note n ON n.id = f.rowid ';
    if (expression.length > 0) {
      sql += 'WHERE f.terms MATCH ? ';
      args.push(expression);
    } else {
      sql += 'WHERE 1 = 1 ';
    }
    sql += 'AND n.vault_id = ? ';
    args.push(vaultId);
    if (query.path.length > 0) {
      sql += 'AND n.path LIKE ? ';
      args.push(`%${query.path}%`);
    }
    if (query.tag.length > 0) {
      sql += 'AND n.id IN (SELECT note_id FROM tag WHERE tag = ?) ';
      args.push(query.tag);
    }
    sql += 'ORDER BY n.mtime DESC LIMIT ?';
    args.push(query.limit);
    const result = await store.querySql(sql, args);
    const hits: SearchHit[] = [];
    if (result.goToFirstRow()) {
      do {
        const hit: SearchHit = new SearchHit();
        hit.noteId = result.getLong(0);
        hit.path = result.getString(1);
        hit.title = result.getString(2);
        hit.score = 1;
        hits.push(hit);
      } while (result.goToNextRow());
    }
    result.close();
    return hits;
  }

  private static async searchByLike(vaultId: number, query: SearchQuery): Promise<SearchHit[]> {
    const store = await DbHelper.getStore();
    const keyword: string = query.text.trim();
    const args: Array<relationalStore.ValueType> = [vaultId];
    let sql: string = 'SELECT id, path, title FROM note WHERE vault_id = ? ';
    if (keyword.length > 0) {
      sql += 'AND (title LIKE ? OR path LIKE ?) ';
      args.push(`%${keyword}%`);
      args.push(`%${keyword}%`);
    }
    if (query.path.length > 0) {
      sql += 'AND path LIKE ? ';
      args.push(`%${query.path}%`);
    }
    if (query.tag.length > 0) {
      sql += 'AND id IN (SELECT note_id FROM tag WHERE tag = ?) ';
      args.push(query.tag);
    }
    sql += 'ORDER BY mtime DESC LIMIT ?';
    args.push(query.limit);
    const result = await store.querySql(sql, args);
    const hits: SearchHit[] = [];
    if (result.goToFirstRow()) {
      do {
        const hit: SearchHit = new SearchHit();
        hit.noteId = result.getLong(0);
        hit.path = result.getString(1);
        hit.title = result.getString(2);
        hit.score = 1;
        hits.push(hit);
      } while (result.goToNextRow());
    }
    result.close();
    return hits;
  }

  /** 用块索引补齐命中片段。 */
  private static async fillSnippets(vaultId: number, hits: SearchHit[], keyword: string): Promise<void> {
    if (keyword.length === 0) {
      return;
    }
    const store = await DbHelper.getStore();
    for (const hit of hits) {
      const args: Array<relationalStore.ValueType> = [hit.noteId, `%${keyword}%`];
      const result = await store.querySql(
        'SELECT block_text FROM block WHERE note_id = ? AND block_text LIKE ? LIMIT 1', args);
      if (result.goToFirstRow()) {
        hit.snippet = result.getString(0);
      }
      result.close();
    }
  }
}
