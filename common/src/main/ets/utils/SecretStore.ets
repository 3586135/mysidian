import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from './Logger';

const LOG: Logger = new Logger('MySidianSecret');

/** Asset Store 返回「条目已存在」的错误码。 */
const ERR_DUPLICATED: number = 24000003;
/** Asset Store 返回「条目不存在」的错误码。 */
const ERR_NOT_FOUND: number = 24000002;

/**
 * 敏感信息（如 WebDAV 密码）安全存储。
 * 基于 Asset Store Kit（系统级加密存储，数据不落入应用沙箱明文文件），
 * 以别名 alias 区分条目。
 */
export class SecretStore {
  /** 读取密文，不存在或失败时返回 null（区别于「空串」）。 */
  public static async get(alias: string): Promise<string | null> {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, SecretStore.encode(alias));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const rows: Array<asset.AssetMap> = await asset.query(query);
      if (rows.length === 0) {
        return null;
      }
      const secret: asset.Value | undefined = rows[0].get(asset.Tag.SECRET);
      if (secret instanceof Uint8Array) {
        return SecretStore.decode(secret);
      }
      return null;
    } catch (error) {
      const err = error as BusinessError;
      if (err.code !== ERR_NOT_FOUND) {
        LOG.warn(`secret query failed, code=${err.code}`);
      }
      return null;
    }
  }

  /** 写入或覆盖密文，成功返回 true。 */
  public static async put(alias: string, value: string): Promise<boolean> {
    const add: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    add.set(asset.Tag.ALIAS, SecretStore.encode(alias));
    add.set(asset.Tag.SECRET, SecretStore.encode(value));
    add.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    try {
      await asset.add(add);
      return true;
    } catch (error) {
      const err = error as BusinessError;
      if (err.code !== ERR_DUPLICATED) {
        LOG.warn(`secret add failed, code=${err.code}`);
        return false;
      }
    }
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, SecretStore.encode(alias));
    const update: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    update.set(asset.Tag.SECRET, SecretStore.encode(value));
    try {
      await asset.update(query, update);
      return true;
    } catch (error) {
      const err = error as BusinessError;
      LOG.warn(`secret update failed, code=${err.code}`);
      return false;
    }
  }

  /** 删除条目（不存在视为成功）。 */
  public static async remove(alias: string): Promise<void> {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, SecretStore.encode(alias));
    try {
      await asset.remove(query);
    } catch (error) {
      const err = error as BusinessError;
      if (err.code !== ERR_NOT_FOUND) {
        LOG.warn(`secret remove failed, code=${err.code}`);
      }
    }
  }

  private static encode(text: string): Uint8Array {
    return new util.TextEncoder().encodeInto(text);
  }

  private static decode(bytes: Uint8Array): string {
    return util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(bytes);
  }
}
