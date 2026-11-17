import { fileIo, hash } from '@kit.CoreFileKit';
import { VaultInfo } from '@ohos/domain';
import { Logger } from '@ohos/common';

const LOG: Logger = new Logger('MySidianConflict');

/**
 * 冲突处理：在保持远端不动的前提下，把远端冲突版本另存为本地冲突副本，
 * 并自动去重（避免周期自动同步在未处理期间重复生成内容完全一致的副本）。
 */
export class ConflictResolver {
  private static readonly FOLDER: string = 'conflicts';

  /** 确保存放冲突副本的本地目录存在。 */
  private static ensureFolder(vault: VaultInfo): string {
    const folder: string = `${vault.rootPath}/${ConflictResolver.FOLDER}`;
    if (!fileIo.accessSync(folder)) {
      fileIo.mkdirSync(folder, true);
    }
    return folder;
  }

  /**
   * 写入文本冲突副本；若 conflicts/ 内已存在同文件名且内容完全相同的副本，则直接复用。
   * @param vault 仓库信息
   * @param remotePath 远端相对路径
   * @param remoteContent 远端内容
   * @returns 冲突副本在仓库内的相对路径
   */
  public static async saveCopy(vault: VaultInfo, remotePath: string,
    remoteContent: string): Promise<string> {
    const folder: string = ConflictResolver.ensureFolder(vault);
    const name: string = ConflictResolver.copyNameOf(remotePath);
    const existing: string | null = ConflictResolver.findMatchingTextCopy(folder, name, remoteContent);
    if (existing !== null) {
      return existing;
    }
    const relative: string = ConflictResolver.buildUniqueRelative(folder, name);
    const absolute: string = `${vault.rootPath}/${relative}`;
    const file = fileIo.openSync(absolute,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, remoteContent);
      fileIo.fsyncSync(file.fd);
    } finally {
      fileIo.closeSync(file);
    }
    LOG.info(`conflict copy saved: ${relative}`);
    return relative;
  }

  /** 为临时下载二进制远端副本分配临时绝对路径（调用方下载后交给 commitBinaryCopy 去重转正）。 */
  public static prepareBinaryTempPath(vault: VaultInfo, remotePath: string): string {
    const folder: string = ConflictResolver.ensureFolder(vault);
    const name: string = ConflictResolver.copyNameOf(remotePath);
    return `${folder}/.tmp_${ConflictResolver.timestamp()}_${name}`;
  }

  /**
   * 校验临时二进制冲突副本：若 conflicts/ 内已存在同文件名且 sha256 相同的副本，
   * 删除临时文件并返回已有副本相对路径；否则原子转正为正式冲突副本。
   */
  public static async commitBinaryCopy(vault: VaultInfo, remotePath: string,
    tempAbsPath: string): Promise<string> {
    const folder: string = ConflictResolver.ensureFolder(vault);
    const name: string = ConflictResolver.copyNameOf(remotePath);
    const tempHash: string = await hash.hash(tempAbsPath, 'sha256');
    const existing: string | null = await ConflictResolver.findMatchingBinaryCopy(
      folder, name, tempHash);
    if (existing !== null) {
      try {
        fileIo.unlinkSync(tempAbsPath);
      } catch (error) {
        LOG.warn(`remove dup temp conflict failed: ${tempAbsPath}`);
      }
      return existing;
    }
    const relative: string = ConflictResolver.buildUniqueRelative(folder, name);
    const finalAbs: string = `${vault.rootPath}/${relative}`;
    fileIo.renameSync(tempAbsPath, finalAbs);
    LOG.info(`binary conflict copy saved: ${relative}`);
    return relative;
  }

  /**
   * 副本文件名：目录限定 + 基础名（如 a/note.md -> a_note.md）。
   * 不同目录下同名同内容的两份冲突若只用基础名去重会共享同一个
   * conflictPath，解决其一会误删/误移除其二；目录限定后天然区分。
   */
  private static copyNameOf(remotePath: string): string {
    const idx: number = remotePath.lastIndexOf('/');
    const base: string = idx < 0 ? remotePath : remotePath.substring(idx + 1);
    if (idx <= 0) {
      return base;
    }
    const dir: string = remotePath.substring(0, idx).replace(/\/+/g, '_');
    return `${dir}_${base}`;
  }

  private static findMatchingTextCopy(folder: string, name: string,
    remoteContent: string): string | null {
    const suffix: string = `_${name}`;
    const names: string[] = fileIo.listFileSync(folder);
    for (const item of names) {
      if (item.startsWith('.') || !item.endsWith(suffix)) {
        continue;
      }
      const abs: string = `${folder}/${item}`;
      try {
        if (!fileIo.statSync(abs).isDirectory() && fileIo.readTextSync(abs) === remoteContent) {
          return `${ConflictResolver.FOLDER}/${item}`;
        }
      } catch (error) {
        continue;
      }
    }
    return null;
  }

  private static async findMatchingBinaryCopy(folder: string, name: string,
    targetHash: string): Promise<string | null> {
    const suffix: string = `_${name}`;
    const names: string[] = fileIo.listFileSync(folder);
    for (const item of names) {
      if (item.startsWith('.') || !item.endsWith(suffix)) {
        continue;
      }
      const abs: string = `${folder}/${item}`;
      try {
        if (!fileIo.statSync(abs).isDirectory()) {
          const itemHash: string = await hash.hash(abs, 'sha256');
          if (itemHash === targetHash) {
            return `${ConflictResolver.FOLDER}/${item}`;
          }
        }
      } catch (error) {
        continue;
      }
    }
    return null;
  }

  private static buildUniqueRelative(folder: string, name: string): string {
    const stamp: string = ConflictResolver.timestamp();
    let candidate: string = `${stamp}_${name}`;
    let seq: number = 1;
    while (fileIo.accessSync(`${folder}/${candidate}`)) {
      candidate = `${stamp}_${seq}_${name}`;
      seq++;
    }
    return `${ConflictResolver.FOLDER}/${candidate}`;
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
