/**
 * 同步文件过滤规则：Markdown 笔记与常用知识库附件（图片/PDF/Office 文档/音视频/白板）参与同步，
 * 避免把仓库中的任意归档/临时/数据库文件（zip、tmp、sqlite 等）推送到远端。
 */
export class SyncFileFilter {
  /** 图片扩展名（小写，用于在 UI 走图片内联预览与全屏缩放）。 */
  private static readonly IMAGE_EXTENSIONS: string[] =
    ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'ico', 'heic', 'avif'];

  /** 参与二进制双向同步的全部附件扩展名（小写）。 */
  private static readonly ATTACHMENT_EXTENSIONS: string[] = [
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'ico', 'heic', 'avif',
    'pdf', 'docx', 'doc', 'xlsx', 'xls', 'pptx', 'ppt', 'txt', 'csv', 'tsv', 'rtf', 'odt', 'epub',
    'mp3', 'm4a', 'wav', 'ogg', 'aac', 'flac', 'mp4', 'mov', 'webm',
    'excalidraw', 'canvas'
  ];

  /** 是否为 Markdown 笔记文件。 */
  public static isMarkdown(fileName: string): boolean {
    const lower: string = fileName.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown');
  }

  /** 是否为支持内联预览的图片附件。 */
  public static isImage(fileName: string): boolean {
    const lower: string = fileName.toLowerCase();
    const index: number = lower.lastIndexOf('.');
    if (index <= 0) {
      return false;
    }
    return SyncFileFilter.IMAGE_EXTENSIONS.includes(lower.substring(index + 1));
  }

  /** 是否为参与同步的文件（Markdown 笔记或受支持的知识库附件）。 */
  public static isSyncable(fileName: string): boolean {
    if (SyncFileFilter.isMarkdown(fileName)) {
      return true;
    }
    const lower: string = fileName.toLowerCase();
    const index: number = lower.lastIndexOf('.');
    if (index <= 0) {
      return false;
    }
    return SyncFileFilter.ATTACHMENT_EXTENSIONS.includes(lower.substring(index + 1));
  }

  /** 是否为二进制附件（图片/PDF/DOCX 等非 Markdown 附件，走二进制同步通道）。 */
  public static isBinary(fileName: string): boolean {
    return !SyncFileFilter.isMarkdown(fileName) && SyncFileFilter.isSyncable(fileName);
  }
}

/**
 * 同步路径安全防火墙（Obsidian 共存保护）：
 * 拒绝任何隐藏目录/文件（.obsidian、.trash、.git、.mysidian 等）、冲突备份目录
 * 与非同步扩展名进入上传、覆盖、移动或删除队列，同时支持可选的 .mysidianignore 规则。
 */
export class SyncPathGuard {
  /** 与点目录同等受保护的特殊目录名（小写比较）。 */
  private static readonly PROTECTED_DIRS: string[] = ['conflicts', 'node_modules'];

  /** 单个目录段是否属于必须忽略/保护的目录名。 */
  public static isIgnoredDirName(name: string): boolean {
    if (name.length === 0 || name === '.' || name === '..' || name.startsWith('.')) {
      return true;
    }
    return SyncPathGuard.PROTECTED_DIRS.includes(name.toLowerCase());
  }

  /** 判断相对路径是否属于允许参与双向同步的安全笔记/附件路径。 */
  public static isSafeSyncPath(relativePath: string): boolean {
    if (relativePath.length === 0 || relativePath.startsWith('/') || relativePath.endsWith('/') ||
      relativePath.includes('\\')) {
      return false;
    }
    const segments: string[] = relativePath.split('/');
    for (let i = 0; i < segments.length; i++) {
      const seg: string = segments[i];
      if (seg.length === 0 || seg === '.' || seg === '..' || seg.startsWith('.')) {
        return false;
      }
      if (i < segments.length - 1 && SyncPathGuard.PROTECTED_DIRS.includes(seg.toLowerCase())) {
        return false;
      }
    }
    const lastSeg: string = segments[segments.length - 1];
    return SyncFileFilter.isSyncable(lastSeg);
  }

  /** 校验远端回收站目标路径（必须位于 .trash/ 下且无路径穿越）。 */
  public static isValidTrashPath(relativePath: string): boolean {
    if (!relativePath.startsWith('.trash/') || relativePath.endsWith('/') ||
      relativePath.includes('\\')) {
      return false;
    }
    const segments: string[] = relativePath.split('/');
    if (segments.length < 2) {
      return false;
    }
    for (let i = 0; i < segments.length; i++) {
      const seg: string = segments[i];
      if (seg.length === 0 || seg === '.' || seg === '..') {
        return false;
      }
      if (i > 0 && seg.startsWith('.')) {
        return false;
      }
    }
    return true;
  }

  /** 解析 `.mysidianignore` 文本为规范化规则数组（忽略空行与 `#` 注释）。 */
  public static parseIgnoreRules(content: string): string[] {
    const lines: string[] = content.split(/\r?\n/);
    const rules: string[] = [];
    for (const raw of lines) {
      let line: string = raw.trim().replace(/\\/g, '/');
      if (line.length === 0 || line.startsWith('#')) {
        continue;
      }
      while (line.startsWith('./') || line.startsWith('/')) {
        line = line.startsWith('./') ? line.substring(2) : line.substring(1);
      }
      if (line.length > 0) {
        rules.push(line);
      }
    }
    return rules;
  }

  /** 判断相对路径是否命中自定义忽略规则（支持目录前缀、`*.ext` 扩展名与精确匹配）。 */
  public static isIgnoredByRules(relativePath: string, rules: string[]): boolean {
    if (rules.length === 0) {
      return false;
    }
    const norm: string = relativePath.replace(/\\/g, '/').replace(/^\/+/, '');
    const slashIdx: number = norm.lastIndexOf('/');
    const baseName: string = slashIdx < 0 ? norm : norm.substring(slashIdx + 1);
    for (const rule of rules) {
      const cleanRule: string = rule.endsWith('/') ? rule.substring(0, rule.length - 1) : rule;
      if (cleanRule.length === 0) {
        continue;
      }
      if (cleanRule.startsWith('*.')) {
        const suffix: string = cleanRule.substring(1).toLowerCase();
        if (baseName.toLowerCase().endsWith(suffix)) {
          return true;
        }
        continue;
      }
      if (norm === cleanRule || norm.startsWith(`${cleanRule}/`)) {
        return true;
      }
    }
    return false;
  }
}
