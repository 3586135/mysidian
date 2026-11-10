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
}

/** 同步基线数据访问：记录上次同步后每个文件的哈希，用于识别冲突。 */
export class SyncStateDao {
  /** 写入（或更新）同步基线。 */
  public static async put(context: common.Context, path: string, fileHash: string, mtime: number,
    etag: string, serverTag: string): Promise<void> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> =
      [path, fileHash, mtime, etag, serverTag, Date.now()];
    await store.executeSql(
      'INSERT OR REPLACE INTO sync_state (path, file_hash, mtime, remote_etag, server_tag, ' +
      'last_sync_at, state) VALUES (?, ?, ?, ?, ?, ?, ?)', [...args, 'synced']);
  }

  /** 读取全部基线：路径 → 上次同步时的快照。 */
  public static async baselines(context: common.Context): Promise<Map<string, SyncBaseline>> {
    const store = await DbHelper.getStore();
    const result = await store.querySql(
      'SELECT path, file_hash, server_tag FROM sync_state');
    const map: Map<string, SyncBaseline> = new Map<string, SyncBaseline>();
    if (result.goToFirstRow()) {
      do {
        const baseline: SyncBaseline = new SyncBaseline();
        baseline.path = result.getString(0);
        baseline.fileHash = result.getString(1);
        baseline.serverTag = result.getString(2);
        map.set(baseline.path, baseline);
      } while (result.goToNextRow());
    }
    result.close();
    return map;
  }

  /** 清理基线。 */
  public static async clear(context: common.Context): Promise<void> {
    const store = await DbHelper.getStore();
    await store.executeSql('DELETE FROM sync_state');
  }
}
