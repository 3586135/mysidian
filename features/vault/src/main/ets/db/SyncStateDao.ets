import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { DbHelper } from './DbHelper';

/** 同步基线数据访问：记录上次同步后每个文件的哈希，用于识别冲突。 */
export class SyncStateDao {
  /** 写入（或更新）同步基线。 */
  public static async put(context: common.Context, path: string, fileHash: string, mtime: number,
    etag: string): Promise<void> {
    const store = await DbHelper.getStore();
    const args: Array<relationalStore.ValueType> = [path, fileHash, mtime, etag, Date.now()];
    await store.executeSql(
      'INSERT OR REPLACE INTO sync_state (path, file_hash, mtime, remote_etag, last_sync_at, state) ' +
      'VALUES (?, ?, ?, ?, ?, ?)', [...args, 'synced']);
  }

  /** 读取全部基线：路径 → 上次同步时的哈希。 */
  public static async baselines(context: common.Context): Promise<Map<string, string>> {
    const store = await DbHelper.getStore();
    const result = await store.querySql('SELECT path, file_hash FROM sync_state');
    const map: Map<string, string> = new Map<string, string>();
    if (result.goToFirstRow()) {
      do {
        map.set(result.getString(0), result.getString(1));
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
