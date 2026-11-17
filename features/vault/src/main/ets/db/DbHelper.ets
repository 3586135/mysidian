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
  /** 标签语义升级（v7）后待执行的一次性全量重索引标记 */
  private static pendingFullReindex: boolean = false;
  private static readonly CURRENT_VERSION: number = 7;

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
    'vault_id INTEGER NOT NULL, path TEXT NOT NULL, file_hash TEXT, mtime INTEGER, remote_etag TEXT,' +
    "server_tag TEXT, last_sync_at INTEGER, state TEXT, size INTEGER DEFAULT 0, target_key TEXT DEFAULT '', PRIMARY KEY(vault_id, path))"
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

  /** 消费一次性全量重索引标记（v6 标签语义升级）；读后即复位。 */
  public static consumePendingFullReindex(): boolean {
    const pending: boolean = DbHelper.pendingFullReindex;
    DbHelper.pendingFullReindex = false;
    return pending;
  }

  private static async migrate(store: relationalStore.RdbStore): Promise<void> {
    const version: number = await DbHelper.readUserVersion(store);
    if (version < 1) {
      for (const sql of DbHelper.SCHEMA_V1) {
        await store.executeSql(sql);
      }
    }
    if (version >= 1 && version < 2) {
      // v2：sync_state 增加 server_tag 列（外部修改检测基线）。
      // 基线是缓存性质数据，直接重建，下次同步自动回填。
      await store.executeSql('DROP TABLE IF EXISTS sync_state');
      await store.executeSql(DbHelper.SCHEMA_V1[DbHelper.SCHEMA_V1.length - 1]);
      LOG.info('sync_state rebuilt for v2 (server_tag column)');
    }
    if (version >= 1 && version < 3) {
      // v3：sync_state 增加 vault_id 维度（不同仓库常有相同相对路径，
      // 缺少隔离会导致基线互相污染、产生虚假冲突）。基线为缓存数据，重建即可。
      await store.executeSql('DROP TABLE IF EXISTS sync_state');
      await store.executeSql(DbHelper.SCHEMA_V1[DbHelper.SCHEMA_V1.length - 1]);
      LOG.info('sync_state rebuilt for v3 (vault_id column)');
    }
    if (version === 3) {
      // v4：sync_state 增加 size 列，配合 mtime 作为本地内容哈希缓存键，
      // 避免每轮同步对全部文件重算 sha256。保留现有基线，仅追加列。
      try {
        await store.executeSql('ALTER TABLE sync_state ADD COLUMN size INTEGER DEFAULT 0');
        LOG.info('sync_state altered for v4 (size column)');
      } catch (error) {
        LOG.warn('sync_state size column already exists or alter failed');
      }
    }
    if (version >= 1 && version < 5) {
      // v5：sync_state 增加 target_key 列，绑定服务器与远端目录，防止切换配置后旧基线触发误删。
      try {
        await store.executeSql("ALTER TABLE sync_state ADD COLUMN target_key TEXT DEFAULT ''");
        LOG.info('sync_state altered for v5 (target_key column)');
      } catch (error) {
        LOG.warn('sync_state target_key column already exists or alter failed');
      }
    }
    if (version >= 1 && version < 7) {
      // v6/v7：标签语义升级（大小写归一 / 下划线 / 纯数字与色值拒绝 / 嵌套匹配 /
      // CJK 标点剔除）。tag 行为派生缓存，标记一次性全量重索引，
      // 由界面层在仓库打开后触发 rescanVault 清除旧规则误报；
      // 同时清理已删笔记遗留的孤儿标签行（JOIN 不可见但占用空间）。
      try {
        await store.executeSql('DELETE FROM tag WHERE note_id NOT IN (SELECT id FROM note)');
      } catch (error) {
        LOG.warn('orphan tag cleanup failed');
      }
      DbHelper.pendingFullReindex = true;
      LOG.info('tag semantics upgraded, full reindex pending (v7)');
    }
    // FTS 可用性探测必须每次启动执行：早于本修复的版本在 schema 已是最新时
    // 提前返回，导致 ftsReady 恒为 false，全文搜索静默退化为 LIKE（只查标题）。
    try {
      await store.executeSql(DbHelper.FTS_V1);
      DbHelper.ftsReady = true;
      LOG.info('fts5 enabled');
    } catch (error) {
      DbHelper.ftsReady = false;
      LOG.warn('fts5 not available, search falls back to LIKE scan');
    }
    if (version < DbHelper.CURRENT_VERSION) {
      await store.executeSql(`PRAGMA user_version = ${DbHelper.CURRENT_VERSION}`);
      LOG.info(`schema migrated to ${DbHelper.CURRENT_VERSION}`);
    }
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
