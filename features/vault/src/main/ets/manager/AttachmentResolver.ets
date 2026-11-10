import { VaultPath } from './VaultPath';

/**
 * 附件目标解析：把正文中的图片 / 嵌入目标解析为仓库内的相对路径。
 *
 * 解析策略与笔记链接保持一致（先按相对路径精确命中，再按文件名兜底），
 * 因此 `![[x.png]]` 与 `![[folder/x.png]]` 都能命中同一份附件。
 */
export class AttachmentResolver {
  /**
   * 解析附件目标。
   *
   * @param target 原始目标串（可含路径）
   * @param currentNotePath 当前笔记的相对路径，用于解析相对目录
   * @param vaultFiles 仓库内全部文件的相对路径
   * @returns 命中的仓库相对路径，未命中返回空串
   */
  public static resolve(target: string, currentNotePath: string,
    vaultFiles: string[]): string {
    const trimmed: string = AttachmentResolver.stripQuery(target.trim());
    if (trimmed.length === 0) {
      return '';
    }
    // 绝对形式：/folder/x.png
    if (trimmed.startsWith('/')) {
      const direct: string = trimmed.substring(1);
      if (AttachmentResolver.contains(vaultFiles, direct)) {
        return direct;
      }
    }
    // 相对形式：优先按当前笔记所在目录拼接
    const dir: string = VaultPath.dirname(currentNotePath);
    const relative: string = dir.length === 0 ? trimmed : `${dir}/${trimmed}`;
    if (AttachmentResolver.contains(vaultFiles, relative)) {
      return relative;
    }
    // 兜底：按文件名匹配（与笔记 basename 解析策略一致）
    const base: string = VaultPath.basename(trimmed);
    if (base.length === 0) {
      return '';
    }
    for (const file of vaultFiles) {
      if (VaultPath.basename(file) === base) {
        return file;
      }
    }
    return '';
  }

  /** 去掉目标串中的查询串与锚点（图片链接可能带 ?v=2 之类的参数）。 */
  private static stripQuery(target: string): string {
    const hash: number = target.indexOf('#');
    const withoutHash: string = hash >= 0 ? target.substring(0, hash) : target;
    const query: number = withoutHash.indexOf('?');
    return query >= 0 ? withoutHash.substring(0, query) : withoutHash;
  }

  /** 判断相对路径是否存在于仓库文件列表。 */
  private static contains(vaultFiles: string[], relative: string): boolean {
    for (const file of vaultFiles) {
      if (file === relative) {
        return true;
      }
    }
    return false;
  }
}
