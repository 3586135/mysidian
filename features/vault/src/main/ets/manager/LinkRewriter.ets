import { common } from '@kit.AbilityKit';
import { BacklinkItem } from '@ohos/domain';
import { Logger } from '@ohos/common';
import { LinkDao } from '../db/LinkDao';
import { VaultPath } from './VaultPath';

const LOG: Logger = new Logger('MySidianLinkRewrite');

/**
 * 双链重写：笔记改名后，把其它笔记正文中指向旧名的 [[旧名]] 改写为 [[新名]]。
 *
 * 仓库内的 wiki 链接按文件名（basename）解析，因此只有「改名」会影响既有链接，
 * 「移动目录」不需要重写任何正文。
 */
export class LinkRewriter {
  /** 转义正则元字符，便于按笔记名动态构造匹配模式。 */
  public static escapeRegExp(text: string): string {
    return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  /**
   * 重写正文中的 wiki 链接。
   * 覆盖 [[旧名]] / [[旧名|别名]] / [[旧名#标题]] / [[旧名^块引用]] /
   * [[目录/旧名]]（路径限定写法，重写为按文件名解析的 [[新名]]）。
   */
  public static rewriteWikiLinks(text: string, oldName: string, newName: string): string {
    if (oldName.length === 0 || newName.length === 0 || oldName === newName) {
      return text;
    }
    // 仅在 [[ 之后（允许目录前缀）紧跟旧名、且后随 ]]/|/#/^ 时才替换，
    // 避免误伤 [[旧名后缀]] 这类其它笔记；^ 为 Obsidian 块引用符。
    const pattern: string =
      `\\[\\[(?:[^\\[\\]\\|#^]+/)?${LinkRewriter.escapeRegExp(oldName)}(?=\\]|\\||#|\\^)`;
    return text.replace(new RegExp(pattern, 'gi'),
      (match: string): string => `[[${newName}`);
  }

  /**
   * 重命名后重写所有指向旧名的源笔记。
   *
   * @param context 应用上下文
   * @param oldPath 旧相对路径
   * @param newPath 新相对路径
   * @param readNote 读取源笔记内容
   * @param writeNote 写回源笔记内容
   * @returns 被改写的源笔记相对路径列表
   */
  public static async rewriteForRename(context: common.Context, oldPath: string, newPath: string,
    readNote: (path: string) => Promise<string>,
    writeNote: (path: string, content: string) => Promise<void>): Promise<string[]> {
    const oldName: string = VaultPath.basenameWithoutExt(oldPath);
    const newName: string = VaultPath.basenameWithoutExt(newPath);
    const affected: string[] = [];
    if (oldName.length === 0 || newName.length === 0 || oldName === newName) {
      return affected;
    }
    const backlinks: BacklinkItem[] = await LinkDao.backlinks(context, oldPath);
    for (const item of backlinks) {
      const content: string = await readNote(item.sourcePath);
      const next: string = LinkRewriter.rewriteWikiLinks(content, oldName, newName);
      if (next === content) {
        continue;
      }
      await writeNote(item.sourcePath, next);
      affected.push(item.sourcePath);
    }
    if (affected.length > 0) {
      LOG.info(`rewrote ${affected.length} backlink(s): ${oldName} -> ${newName}`);
    }
    return affected;
  }
}
