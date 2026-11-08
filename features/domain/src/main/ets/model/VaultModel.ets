/**
 * 仓库 / 笔记 / 链接 / 检索 领域模型（纯数据类型）。
 */

export enum LinkKind {
  WIKI_LINK = 'wikiLink',
  MARKDOWN = 'markdown',
  EMBED = 'embed',
  TAG = 'tag'
}

/** 仓库信息。 */
export class VaultInfo {
  id: number = 0;
  name: string = '';
  /** 仓库根目录绝对路径 */
  rootPath: string = '';
  createdAt: number = 0;
  updatedAt: number = 0;
}

/** 笔记元数据行（对应 note 表）。 */
export class NoteRow {
  id: number = 0;
  vaultId: number = 0;
  /** 相对仓库根的路径，使用 '/' 分隔 */
  path: string = '';
  title: string = '';
  ext: string = '';
  mtime: number = 0;
  size: number = 0;
  /** 内容哈希（sha256） */
  hash: string = '';
  /** frontmatter 原始文本 */
  frontmatter: string = '';
}

/** 文件树节点。 */
export class FileNode {
  name: string = '';
  path: string = '';
  isDir: boolean = false;
  size: number = 0;
  mtime: number = 0;
  children: FileNode[] = [];
}

/** 扁平化后的文件树条目，配合懒加载列表渲染。 */
export class FlatFileNode {
  node: FileNode = new FileNode();
  depth: number = 0;
  expanded: boolean = false;
}

/** 链接记录。 */
export class LinkRef {
  sourceNoteId: number = 0;
  /** 链接原始目标串 */
  targetRaw: string = '';
  /** 解析后的目标相对路径（未解析时为空） */
  targetPath: string = '';
  targetNoteId: number = 0;
  /** 是否已解析到具体笔记 */
  resolved: boolean = false;
  kind: LinkKind = LinkKind.WIKI_LINK;
  /** 链接所在段落上下文 */
  context: string = '';
}

/** 标签统计。 */
export class TagRef {
  tag: string = '';
  count: number = 0;
}

/** 检索命中项。 */
export class SearchHit {
  noteId: number = 0;
  path: string = '';
  title: string = '';
  /** 命中片段 */
  snippet: string = '';
  score: number = 0;
}

/** 检索条件。 */
export class SearchQuery {
  /** 关键词 */
  text: string = '';
  /** path: 前缀过滤 */
  path: string = '';
  /** tag: 标签过滤 */
  tag: string = '';
  /** 检索范围：content / title / path */
  scope: string = 'content';
  limit: number = 50;
}

/** 大纲条目。 */
export class OutlineEntry {
  level: number = 0;
  text: string = '';
  ordinal: number = 0;
}

/** 反向链接条目。 */
export class BacklinkItem {
  sourceNoteId: number = 0;
  sourcePath: string = '';
  sourceTitle: string = '';
  context: string = '';
}

/** 索引进度。 */
export class IndexProgress {
  total: number = 0;
  processed: number = 0;
  running: boolean = false;
}
