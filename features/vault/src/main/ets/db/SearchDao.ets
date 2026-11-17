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
  /** 片段补齐时按笔记主键分批查询的批大小。 */
  private static readonly SNIPPET_BATCH: number = 200;

  /** 执行检索。 */
  public static async search(context: common.Context, vaultId: number,
    query: SearchQuery): Promise<SearchHit[]> {
    const keyword: string = query.text.trim();
    if (keyword.length === 0 && query.tag.length === 0 &&
      query.propKey.length === 0 && query.propValue.length === 0) {
      return [];
    }
    let hits: SearchHit[] = [];
    // 关键词非空但分词后 MATCH 表达式为空（如纯标点）时跳过 FTS，
    // 否则 searchByFts 会退化为 WHERE 1 = 1，把仓库全部笔记误判为关键词命中。
    if (DbHelper.isFtsReady() &&
      (keyword.length === 0 || Tokenizer.buildMatchExpression(keyword).length > 0)) {
      try {
        hits = await SearchDao.searchByFts(vaultId, query);
      } catch (error) {
        hits = [];
      }
      if (hits.length > 0 || keyword.length === 0) {
        await SearchDao.fillSnippets(vaultId, hits, keyword);
        await SearchDao.fillPropSnippets(hits, query);
        return hits;
      }
    }
    const fallback: SearchHit[] = await SearchDao.searchByLike(vaultId, query);
    await SearchDao.fillSnippets(vaultId, fallback, keyword);
    await SearchDao.fillPropSnippets(fallback, query);
    return fallback;
  }

  private static async searchByFts(vaultId: number, query: SearchQuery): Promise<SearchHit[]> {
    const store = await DbHelper.getStore();
    const expression: string = Tokenizer.buildMatchExpression(query.text);
    const args: Array<relationalStore.ValueType> = [];
    let sql: string = 'SELECT n.id, n.path, n.title FROM note_fts f JOIN note n ON n.id = f.rowid ';
    if (expression.length > 0) {
      // 表级 MATCH 同时覆盖标题与正文两列；FTS5 不允许两列 MATCH 以 OR 连接。
      sql += 'WHERE note_fts MATCH ? ';
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
    sql = SearchDao.appendPropFilter(sql, args, query, 'n');
    // 有关键词时按 BM25 相关度排序（标题权重 10 倍于正文词），同分按最近修改；
    // 无关键词（仅标签/属性过滤）时按最近修改。
    sql += expression.length > 0 ? 'ORDER BY bm25(note_fts, 10.0, 1.0) ASC, n.mtime DESC LIMIT ?' :
      'ORDER BY n.mtime DESC LIMIT ?';
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
    sql = SearchDao.appendPropFilter(sql, args, query, '');
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

  /** 拼接属性（frontmatter）过滤子句，返回新的 SQL。noteAlias 为笔记表别名或空串。 */
  private static appendPropFilter(sql: string, args: Array<relationalStore.ValueType>,
    query: SearchQuery, noteAlias: string): string {
    let result: string = sql;
    if (query.propKey.length > 0 || query.propValue.length > 0) {
      const idColumn: string = noteAlias.length > 0 ? `${noteAlias}.id` : 'id';
      result += `AND ${idColumn} IN (SELECT note_id FROM prop WHERE prop_key LIKE ? AND prop_value LIKE ?) `;
      args.push(`%${query.propKey}%`);
      args.push(`%${query.propValue}%`);
    }
    return result;
  }

  /** 用块索引补齐命中片段（单次批量查询，避免逐条命中各查一次）。 */
  private static async fillSnippets(vaultId: number, hits: SearchHit[], keyword: string): Promise<void> {
    if (keyword.length === 0 || hits.length === 0) {
      return;
    }
    const store = await DbHelper.getStore();
    const byNote: Map<number, SearchHit> = new Map<number, SearchHit>();
    for (const hit of hits) {
      byNote.set(hit.noteId, hit);
    }
    const pattern: string = `%${SearchDao.escapeLike(keyword)}%`;
    const ids: number[] = Array.from(byNote.keys());
    for (let start: number = 0; start < ids.length; start += SearchDao.SNIPPET_BATCH) {
      const batch: number[] = ids.slice(start, start + SearchDao.SNIPPET_BATCH);
      const marks: string = batch.map((): string => '?').join(',');
      const args: Array<relationalStore.ValueType> = [];
      for (const id of batch) {
        args.push(id);
      }
      args.push(pattern);
      const result = await store.querySql(
        `SELECT note_id, block_text FROM block WHERE note_id IN (${marks}) ` +
        `AND block_text LIKE ? ESCAPE '\\' ORDER BY note_id, ordinal`, args);
      if (result.goToFirstRow()) {
        do {
          const hit: SearchHit | undefined = byNote.get(result.getLong(0));
          if (hit !== undefined && hit.snippet.length === 0) {
            hit.snippet = result.getString(1);
          }
        } while (result.goToNextRow());
      }
      result.close();
    }
  }

  /** 转义 LIKE 通配符，使用户输入的 % _ \ 按字面匹配。 */
  private static escapeLike(text: string): string {
    return text.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
  }

  /** 属性过滤时，用命中的属性行补齐片段。 */
  private static async fillPropSnippets(hits: SearchHit[], query: SearchQuery): Promise<void> {
    if (query.propKey.length === 0 && query.propValue.length === 0) {
      return;
    }
    const store = await DbHelper.getStore();
    for (const hit of hits) {
      if (hit.snippet.length > 0) {
        continue;
      }
      const args: Array<relationalStore.ValueType> =
        [hit.noteId, `%${query.propKey}%`, `%${query.propValue}%`];
      const result = await store.querySql(
        'SELECT prop_key, prop_value FROM prop WHERE note_id = ? AND prop_key LIKE ? ' +
        'AND prop_value LIKE ? LIMIT 1', args);
      if (result.goToFirstRow()) {
        hit.snippet = `${result.getString(0)}: ${result.getString(1)}`;
      }
      result.close();
    }
  }
}
