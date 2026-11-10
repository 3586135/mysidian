import { RemoteEntry, SyncConfig } from '../model/SyncModel';

/**
 * 同步供应方抽象。不同后端（WebDAV / S3 / 华为云空间）实现同一接口，
 * 由 SyncEngine 统一调度，不感知具体协议。
 */
export interface SyncProvider {
  /** 建立连接，失败时抛出异常 */
  connect(config: SyncConfig): Promise<void>;

  /** 列出远端目录下的条目（含子目录递归由实现决定） */
  list(remoteDir: string): Promise<RemoteEntry[]>;

  /** 拉取远端文件到本地沙箱路径 */
  pull(entry: RemoteEntry, destPath: string): Promise<void>;

  /** 推送本地文件到远端，返回上传后的服务器版本标识（未知时为空串） */
  push(localPath: string, entry: RemoteEntry): Promise<string>;

  /** 查询远端单个文件元信息，不存在时返回 null */
  stat(path: string): Promise<RemoteEntry | null>;

  /** 读取远端文件文本内容（用于哈希未知时的内容比对） */
  readRemote(path: string): Promise<string>;

  /** 写回远端清单（用于记录已同步的文件与哈希） */
  putManifest(entries: RemoteEntry[]): Promise<void>;

  /** 断开连接并释放资源 */
  disconnect(): Promise<void>;
}
