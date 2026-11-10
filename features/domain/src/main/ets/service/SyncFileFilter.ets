/**
 * 同步文件过滤规则：仅 Markdown 笔记与图片附件参与同步，
 * 避免把仓库中的任意文件（zip、临时文件等）推送到远端。
 */
export class SyncFileFilter {
  /** 参与同步的图片扩展名（小写）。 */
  private static readonly IMAGE_EXTENSIONS: string[] =
    ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'];

  /** 是否为 Markdown 笔记文件。 */
  public static isMarkdown(fileName: string): boolean {
    const lower: string = fileName.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown');
  }

  /** 是否为参与同步的文件（Markdown 笔记或图片附件）。 */
  public static isSyncable(fileName: string): boolean {
    if (SyncFileFilter.isMarkdown(fileName)) {
      return true;
    }
    const lower: string = fileName.toLowerCase();
    const index: number = lower.lastIndexOf('.');
    if (index <= 0) {
      return false;
    }
    return SyncFileFilter.IMAGE_EXTENSIONS.includes(lower.substring(index + 1));
  }

  /** 是否为二进制附件（图片，走二进制同步通道）。 */
  public static isBinary(fileName: string): boolean {
    return !SyncFileFilter.isMarkdown(fileName) && SyncFileFilter.isSyncable(fileName);
  }
}
