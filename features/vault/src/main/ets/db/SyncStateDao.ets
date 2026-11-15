import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { DbHelper } from './DbHelper';

/** 单个文件的同步基线（上次同步时的状态快照）。 */
export class SyncBaseline {
  path: string = '';
  /** 上次同步时的本地内容哈希 */
  fileHash: string = '';
  /** 上次同步时的服务器原生版本标识（etag / mtime~size） */
  serverTag: string = '';
  /** 上次同步时的本地修改时间（秒），与 size 一起作为内容哈希缓存键 */
  mtime: number = 0;
  /** 上次同步时的本地文件大小（字节） */
  size: number = 0;
  /** 记录该基线的同步完成时间（毫秒） */
  lastSyncAt: number = 0;
  /** 基线状态：'synced' | 'local_deleted' | 'conflict' */
  state: string = 'synced';
  /** 绑定的远端目标标识（serverUrl|remoteRoot） */
  targetKey: string = '';
}

/** 待回写的单条基线数据。 */
export class SyncBaselineRow {
  path: string = '';
  fileHash: string = '';
  mtime: number = 0;
  size: number = 0;
  etag: string = '';
  serverTag: string = '';
  state: string = 'synced';
  targetKey: string = '';
}

/**
 * 同步基线数据访问：记录上次同步后每个文件的哈希与远端绑定目标，用于识别冲突及防止切换目录误删。
 * 基线按 (vault_id, path) 隔离——不同仓库常有相同相对路径，
 * 缺少仓库维度会导致基线互相污染、产生虚假冲突。
 */
export class SyncStateDao {
  /** 读取某仓库的全部基线：路径 → 上次同步时的快照。 */
  public static async baselines(context: common.Context,
    vaultId: number): Promise<Map<string, SyncBaseline>> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [vaultId];
    const result = await store.querySql(
      'SELECT path, file_hash, server_tag, mtime, size, last_sync_at, state, target_key FROM sync_state ' +
        'WHERE vault_id = ?', args);
    const map: Map<string, SyncBaseline> = new Map<string, SyncBaseline>();
    if (result.goToFirstRow()) {
      do {
        const baseline: SyncBaseline = new SyncBaseline();
        baseline.path = result.getString(0);
        baseline.fileHash = result.getString(1);
        baseline.serverTag = result.getString(2);
        baseline.mtime = result.getLong(3);
        baseline.size = result.getLong(4);
        baseline.lastSyncAt = result.getLong(5);
        const stateText: string = result.getString(6);
        baseline.state = stateText.length > 0 ? stateText : 'synced';
        const targetText: string = result.getString(7);
        baseline.targetKey = targetText !== null && targetText !== undefined ? targetText : '';
        map.set(baseline.path, baseline);
      } while (result.goToNextRow());
    }
    result.close();
    return map;
  }

  /** 清除某仓库的全部同步基线（仓库删除或切换远端目标时调用）。 */
  public static async clear(context: common.Context, vaultId: number): Promise<void> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [vaultId];
    await store.executeSql('DELETE FROM sync_state WHERE vault_id = ?', args);
  }

  /** 单条写入或更新某个路径的同步基线（用于冲突手动解决后立即收敛基线）。 */
  public static async upsertRow(context: common.Context, vaultId: number,
    row: SyncBaselineRow): Promise<void> {
    const store = await DbHelper.getStore();
    const now: number = Date.now();
    const stateVal: string = row.state.length > 0 ? row.state : 'synced';
    const args: Array<relationalStore.ValueType> =
      [vaultId, row.path, row.fileHash, row.mtime, row.etag, row.serverTag, now, stateVal,
        row.size, row.targetKey];
    await store.executeSql(
      'INSERT OR REPLACE INTO sync_state (vault_id, path, file_hash, mtime, remote_etag, ' +
        'server_tag, last_sync_at, state, size, target_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      args);
  }

  /**
   * 事务化整体替换某仓库的基线。
   * 先 clear 再逐条 put 的写法在中间失败时会留下「部分文件有基线、
   * 部分没有」的状态，缺基线的文件下次同步会被误判为冲突，
   * 故整段回写必须在一个事务内完成。
   */
  public static async replaceAll(context: common.Context, vaultId: number,
    rows: SyncBaselineRow[]): Promise<void> {
    const store = await DbHelper.getStore();
    store.beginTransaction();
    try {
      const clearArgs: Array<relationalStore.ValueType> = [vaultId];
      await store.executeSql('DELETE FROM sync_state WHERE vault_id = ?', clearArgs);
      const now: number = Date.now();
      for (const row of rows) {
        const stateVal: string = row.state.length > 0 ? row.state : 'synced';
        const args: Array<relationalStore.ValueType> =
          [vaultId, row.path, row.fileHash, row.mtime, row.etag, row.serverTag, now, stateVal,
            row.size, row.targetKey];
        await store.executeSql(
          'INSERT OR REPLACE INTO sync_state (vault_id, path, file_hash, mtime, remote_etag, ' +
          'server_tag, last_sync_at, state, size, target_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          args);
      }
      store.commit();
    } catch (error) {
      store.rollBack();
      throw error as Error;
    }
  }
}
