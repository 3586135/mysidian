/**
 * 仓库路径处理工具：统一使用 '/' 作为相对路径分隔符。
 */
export class VaultPath {
  /** 拼接仓库根路径与相对路径。 */
  public static join(root: string, relative: string): string {
    if (relative.length === 0) {
      return root;
    }
    return `${root}/${VaultPath.normalize(relative)}`;
  }

  /** 规范化相对路径：反斜杠转正斜杠，去掉前导 './' 与 '/'。 */
  public static normalize(relative: string): string {
    let result: string = relative.replace(/\\/g, '/');
    while (result.startsWith('./')) {
      result = result.substring(2);
    }
    while (result.startsWith('/')) {
      result = result.substring(1);
    }
    if (result.split('/').includes('..')) {
      const segments: string[] = result.split('/');
      const kept: string[] = [];
      for (const segment of segments) {
        if (segment !== '..') {
          kept.push(segment);
        }
      }
      result = kept.join('/');
    }
    return result;
  }

  /** 把相对路径转成绝对路径。 */
  public static absolute(root: string, relative: string): string {
    return VaultPath.join(root, relative);
  }

  /** 文件名（不含目录）。 */
  public static basename(path: string): string {
    const normalized: string = VaultPath.normalize(path);
    const index: number = normalized.lastIndexOf('/');
    return index < 0 ? normalized : normalized.substring(index + 1);
  }

  /** 文件名去掉扩展名。 */
  public static basenameWithoutExt(path: string): string {
    const name: string = VaultPath.basename(path);
    const index: number = name.lastIndexOf('.');
    return index <= 0 ? name : name.substring(0, index);
  }

  /** 默认日记根目录名。 */
  public static readonly DAILY_ROOT_DIR: string = '日记';

  /** 默认日记相对路径：`日记/YYYY-MM/YYYY-MM-DD.md`。 */
  public static dailyNotePath(dateKey: string): string {
    const cleanKey: string = VaultPath.normalize(dateKey).replace(/\.md$/i, '');
    if (cleanKey.length >= 7) {
      const monthDir: string = cleanKey.substring(0, 7);
      return `${VaultPath.DAILY_ROOT_DIR}/${monthDir}/${cleanKey}.md`;
    }
    return `${VaultPath.DAILY_ROOT_DIR}/${cleanKey}.md`;
  }

  /** 返回同一天日记的候选路径（新目录格式优先，兼容历史根目录日记）。 */
  public static dailyNoteCandidates(dateKey: string): string[] {
    const cleanKey: string = VaultPath.normalize(dateKey).replace(/\.md$/i, '');
    const preferred: string = VaultPath.dailyNotePath(cleanKey);
    const legacy: string = `${cleanKey}.md`;
    return preferred === legacy ? [preferred] : [preferred, legacy];
  }

  /** 目录名（不含末尾分隔符；若入参为绝对路径则保留前导 `/`）。 */
  public static dirname(path: string): string {
    const trimmed: string = path.trim();
    const isAbsolute: boolean = trimmed.startsWith('/') || trimmed.startsWith('\\');
    const normalized: string = VaultPath.normalize(path);
    const index: number = normalized.lastIndexOf('/');
    if (index <= 0) {
      return isAbsolute ? '/' : '';
    }
    const parent: string = normalized.substring(0, index);
    return isAbsolute ? `/${parent}` : parent;
  }

  /** 扩展名（小写，不含点），无扩展名时返回空串。 */
  public static extension(path: string): string {
    const name: string = VaultPath.basename(path);
    const index: number = name.lastIndexOf('.');
    return index <= 0 ? '' : name.substring(index + 1).toLowerCase();
  }

  /** 是否为 Markdown 笔记文件。 */
  public static isMarkdown(path: string): boolean {
    const ext: string = VaultPath.extension(path);
    return ext === 'md' || ext === 'markdown';
  }

  /** 清理仓库名中的非法字符。 */
  public static sanitizeName(name: string): string {
    const cleaned: string = name.replace(/[\\/:*?"<>|\s]+/g, '_').trim();
    return cleaned.length === 0 ? 'vault' : cleaned;
  }
}
