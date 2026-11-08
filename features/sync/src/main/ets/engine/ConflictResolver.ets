import { fileIo } from '@kit.CoreFileKit';
import { RemoteEntry, VaultInfo } from '@ohos/domain';
import { Logger } from '@ohos/common';

const LOG: Logger = new Logger('MySidianConflict');

/**
 * 冲突处理：把远端版本另存为本地冲突副本，保留用户当前内容。
 */
export class ConflictResolver {
  private static readonly FOLDER: string = 'conflicts';

  /**
   * 写入冲突副本。
   * @param vault 仓库信息
   * @param remotePath 远端相对路径
   * @param remoteContent 远端内容
   * @returns 冲突副本在仓库内的相对路径
   */
  public static async saveCopy(vault: VaultInfo, remotePath: string,
    remoteContent: string): Promise<string> {
    const folder: string = `${vault.rootPath}/${ConflictResolver.FOLDER}`;
    if (!fileIo.accessSync(folder)) {
      fileIo.mkdirSync(folder, true);
    }
    const name: string = remotePath.substring(remotePath.lastIndexOf('/') + 1);
    const stamp: string = ConflictResolver.timestamp();
    const relative: string = `${ConflictResolver.FOLDER}/${stamp}_${name}`;
    const absolute: string = `${vault.rootPath}/${relative}`;
    const file = fileIo.openSync(absolute,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, remoteContent);
    } finally {
      fileIo.closeSync(file);
    }
    LOG.info(`conflict copy saved: ${relative}`);    return relative;
  }

  private static timestamp(): string {
    const now: Date = new Date();
    const pad: (value: number) => string = (value: number): string => {
      return value < 10 ? `0${value}` : `${value}`;
    };
    return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}` +
      `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  }
}
