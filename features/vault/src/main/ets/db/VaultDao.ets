import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { VaultInfo } from '@ohos/domain';
import { DbHelper } from './DbHelper';

/** 仓库表数据访问。 */
export class VaultDao {
  /** 新增仓库，返回主键。 */
  public static async insert(context: common.Context, info: VaultInfo): Promise<number> {
    const store = await DbHelper.getStore();
    const values: relationalStore.ValuesBucket = {
      'name': info.name,
      'root': info.rootPath,
      'created_at': info.createdAt,
      'updated_at': info.updatedAt
    };
    return await store.insert('vault', values);
  }

  /** 查询全部仓库，按创建时间升序。 */
  public static async list(context: common.Context): Promise<VaultInfo[]> {
    const store = await DbHelper.getStore();
    const result = await store.querySql(
      'SELECT id, name, root, created_at, updated_at FROM vault ORDER BY created_at ASC');
    const vaults: VaultInfo[] = [];
    if (result.goToFirstRow()) {
      do {
        const info: VaultInfo = new VaultInfo();
        info.id = result.getLong(0);
        info.name = result.getString(1);
        info.rootPath = result.getString(2);
        info.createdAt = result.getLong(3);
        info.updatedAt = result.getLong(4);
        vaults.push(info);
      } while (result.goToNextRow());
    }
    result.close();
    return vaults;
  }

  /** 更新仓库的更新时间。 */
  public static async touch(context: common.Context, vaultId: number): Promise<void> {
    const store = await DbHelper.getStore();
    const values: relationalStore.ValuesBucket = {
      'updated_at': Date.now()
    };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('vault');
    predicates.equalTo('id', vaultId);
    await store.update(values, predicates);
  }

  /** 删除仓库记录。 */
  public static async remove(context: common.Context, vaultId: number): Promise<void> {
    const store = await DbHelper.getStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('vault');
    predicates.equalTo('id', vaultId);
    await store.delete(predicates);
  }
}
