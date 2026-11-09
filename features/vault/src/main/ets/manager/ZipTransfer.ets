import { fileIo } from '@kit.CoreFileKit';
import { zlib, BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { Logger } from '@ohos/common';

const LOG: Logger = new Logger('MySidianZip');

/**
 * 仓库归档导入导出。
 * 依赖系统 zlib 的 zip 能力：压缩支持目录，解压自带路径穿越防护。
 */
export class ZipTransfer {
  private static readonly OPTIONS: zlib.Options = {
    level: zlib.CompressLevel.COMPRESS_LEVEL_BEST_COMPRESSION,
    strategy: zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY,
    parallel: zlib.ParallelStrategy.PARALLEL_STRATEGY_SEQUENTIAL
  };

  /**
   * 将用户选择的 zip（uri）导入到目标目录。
   */
  public static async importZip(context: common.Context, uri: string,
    destDir: string): Promise<void> {
    const cacheFile: string = `${context.cacheDir}/import_${Date.now()}.zip`;
    try {
      let copiedSize = 0;
      try {
        copiedSize = ZipTransfer.copyUriToFile(uri, cacheFile);
      } catch (error) {
        const err = error as BusinessError;
        LOG.error(`copy zip from uri failed, code=${err.code}, message=${err.message}, uri=${uri}`);
        throw new Error(`copy zip failed, code=${err.code}, message=${err.message}`);
      }
      LOG.info(`picked archive copied, uri=${uri}, file=${cacheFile}, size=${copiedSize}`);
      if (copiedSize <= 0) {
        throw new Error(`picked archive is empty, uri=${uri}`);
      }
      try {
        await zlib.decompressFile(cacheFile, destDir, ZipTransfer.OPTIONS);
        LOG.info(`imported vault archive to ${destDir}`);
      } catch (error) {
        const err = error as BusinessError;
        LOG.error(`decompress zip failed, code=${err.code}, message=${err.message}, file=${cacheFile}, size=${copiedSize}`);
        throw new Error(`decompress zip failed, code=${err.code}, message=${err.message}`);
      }
    } finally {
      if (fileIo.accessSync(cacheFile)) {
        fileIo.unlinkSync(cacheFile);
      }
    }
  }

  /**
   * 将目录导出为 zip 并写入用户选择的 uri。
   */
  public static async exportZip(context: common.Context, srcDir: string,
    uri: string): Promise<void> {
    const cacheFile: string = `${context.cacheDir}/export_${Date.now()}.zip`;
    await zlib.compressFile(srcDir, cacheFile, ZipTransfer.OPTIONS);
    try {
      ZipTransfer.copyFileToUri(cacheFile, uri);
      LOG.info(`exported vault archive from ${srcDir}`);
    } finally {
      if (fileIo.accessSync(cacheFile)) {
        fileIo.unlinkSync(cacheFile);
      }
    }
  }

  /** 把 uri 指向的文件复制到沙箱文件，返回复制后的文件大小（字节）。 */
  public static copyUriToFile(uri: string, destPath: string): number {
    const source = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    let dest: fileIo.File | undefined = undefined;
    try {
      dest = fileIo.openSync(destPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE);
      fileIo.copyFileSync(source.fd, dest.fd);
    } finally {
      fileIo.closeSync(source);
      if (dest !== undefined) {
        fileIo.closeSync(dest);
      }
    }
    return fileIo.statSync(destPath).size;
  }

  /** 把沙箱文件内容写入 uri 指向的文件。 */
  public static copyFileToUri(srcPath: string, uri: string): void {
    const source = fileIo.openSync(srcPath, fileIo.OpenMode.READ_ONLY);
    const stat = fileIo.statSync(srcPath);
    const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
    try {
      fileIo.readSync(source.fd, buffer);
    } finally {
      fileIo.closeSync(source);
    }
    const target = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE);
    try {
      fileIo.writeSync(target.fd, buffer);
    } finally {
      fileIo.closeSync(target);
    }
  }
}
