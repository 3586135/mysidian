import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger } from '@ohos/common';

const LOG: Logger = new Logger('MySidianDb');

/**
 * 关系型数据库入口。
 * 负责打开数据库、创建表结构、执行版本迁移，并暴露 FTS 可用性标记。
 */
export class DbHelper {
  private static store: relationalStore.RdbStore | null = null;
  /** 平台 SQLite 是否支持 FTS5（不支持时搜索退化为 LIKE 扫描） */
  private static ftsReady: boolean = false;
  private static readonly CURRENT_VERSION: number = 1;

  private static readonly SCHEMA_V1: string[] = [
    'CREATE TABLE IF NOT EXISTS vault (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, root TEXT NOT NULL,' +
    'created_at INTEGER, updated_at INTEGER)',
    'CREATE TABLE IF NOT EXISTS note (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, vault_id INTEGER NOT NULL, path TEXT NOT NULL,' +
    'title TEXT, ext TEXT, mtime INTEGER, size INTEGER, hash TEXT, frontmatter TEXT,' +
    'created_at INTEGER, updated_at INTEGER, UNIQUE(vault_id, path))',
    'CREATE INDEX IF NOT EXISTS idx_note_vault_path ON note(vault_id, path)',
    'CREATE INDEX IF NOT EXISTS idx_note_vault_mtime ON note(vault_id, mtime)',
    'CREATE TABLE IF NOT EXISTS block (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, note_id INTEGER NOT NULL, ordinal INTEGER,' +
    'type TEXT, block_text TEXT, level INTEGER, lang TEXT, meta TEXT)',
    'CREATE INDEX IF NOT EXISTS idx_block_note ON block(note_id, ordinal)',
    'CREATE TABLE IF NOT EXISTS link (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, source_note_id INTEGER NOT NULL, target_raw TEXT,' +
    'target_path TEXT, target_note_id INTEGER, kind TEXT, link_context TEXT)',
    'CREATE INDEX IF NOT EXISTS idx_link_source ON link(source_note_id)',
    'CREATE INDEX IF NOT EXISTS idx_link_target ON link(target_path)',
    'CREATE TABLE IF NOT EXISTS tag (note_id INTEGER, tag TEXT, PRIMARY KEY(note_id, tag))',
    'CREATE TABLE IF NOT EXISTS prop (' +
    'note_id INTEGER, prop_key TEXT, prop_value TEXT, vtype TEXT, PRIMARY KEY(note_id, prop_key))',
    'CREATE TABLE IF NOT EXISTS sync_state (' +
    'path TEXT PRIMARY KEY, file_hash TEXT, mtime INTEGER, remote_etag TEXT,' +
    'last_sync_at INTEGER, state TEXT)'
  ];

  private static readonly FTS_V1: string =
    'CREATE VIRTUAL TABLE IF NOT EXISTS note_fts USING fts5(title, terms, tokenize=\'unicode61\')';

  /** 打开数据库并完成迁移，可重复调用。 */
  public static async init(context: common.Context): Promise<void> {
    if (DbHelper.store !== null) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: 'mysidian.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
    DbHelper.store = store;
    await DbHelper.migrate(store);
  }

  /** 获取已初始化的数据库实例。 */
  public static async getStore(): Promise<relationalStore.RdbStore> {
    const store: relationalStore.RdbStore | null = DbHelper.store;
    if (store === null) {
      throw new Error('DbHelper is not initialized, call init() first.');
    }
    return store;
  }

  /** 平台是否支持 FTS5 虚表。 */
  public static isFtsReady(): boolean {
    return DbHelper.ftsReady;
  }

  private static async migrate(store: relationalStore.RdbStore): Promise<void> {
    const version: number = await DbHelper.readUserVersion(store);
    if (version >= DbHelper.CURRENT_VERSION) {
      return;
    }
    for (const sql of DbHelper.SCHEMA_V1) {
      await store.executeSql(sql);
    }
    try {
      await store.executeSql(DbHelper.FTS_V1);
      DbHelper.ftsReady = true;
      LOG.info(`fts5 enabled, schema migrated to ${DbHelper.CURRENT_VERSION}`);
    } catch (error) {
      DbHelper.ftsReady = false;
      LOG.warn('fts5 not available, search falls back to LIKE scan');
    }
    await store.executeSql(`PRAGMA user_version = ${DbHelper.CURRENT_VERSION}`);
  }

  private static async readUserVersion(store: relationalStore.RdbStore): Promise<number> {
    const result = await store.querySql('PRAGMA user_version');
    let version: number = 0;
    if (result.goToFirstRow()) {
      version = result.getLong(0);
    }
    result.close();
    return version;
  }
}
