/**
 * Markdown 领域模型（纯数据类型，无 UI / 无 IO）。
 * 命名规则：所有全局类型使用 Md* 前缀，避免 arkts-no-decl-merging 冲突。
 */

export enum MdBlockType {
  HEADING = 'heading',
  PARAGRAPH = 'paragraph',
  LIST = 'list',
  CODE = 'code',
  QUOTE = 'quote',
  CALLOUT = 'callout',
  TABLE = 'table',
  THEMATIC_BREAK = 'thematicBreak',
  HTML = 'html',
  MATH = 'math',
  EMBED = 'embed',
  IMAGE = 'image'
}

export enum MdInlineType {
  TEXT = 'text',
  STRONG = 'strong',
  EMPHASIS = 'emphasis',
  STRIKETHROUGH = 'strikethrough',
  INLINE_CODE = 'inlineCode',
  LINK = 'link',
  WIKI_LINK = 'wikiLink',
  EMBED = 'embed',
  TAG = 'tag',
  IMAGE = 'image',
  BREAK = 'break',
  MATH = 'math',
  HTML_INLINE = 'htmlInline'
}

export enum MdPropType {
  STRING = 'string',
  NUMBER = 'number',
  BOOLEAN = 'boolean',
  LIST = 'list',
  MAP = 'map'
}

/** 行内节点。 */
export class MdInline {  type: MdInlineType = MdInlineType.TEXT;
  /** 文本内容（TEXT / INLINE_CODE / TAG 等） */
  text: string = '';
  /** 链接地址（LINK / IMAGE） */
  url: string = '';
  /** Wiki 链接目标原始串 */
  target: string = '';
  /** Wiki 链接别名 */
  alias: string = '';
  /** Wiki 链接锚点（#标题） */
  heading: string = '';
  /** Wiki 链接块引用（^块ID） */
  blockRef: string = '';
  /** 子节点（STRONG / EMPHASIS / STRIKETHROUGH） */
  children: MdInline[] = [];
}

/** 列表项。 */
export class MdListItem {
  ordinal: number = 0;
  /** 是否为任务列表项（- [ ] / - [x]） */
  isTask: boolean = false;
  checked: boolean = false;
  inlines: MdInline[] = [];
  children: MdListItem[] = [];
}

/** 块级节点。 */
export class MdBlock {
  type: MdBlockType = MdBlockType.PARAGRAPH;
  /** 标题层级 1-6 */
  level: number = 0;
  /** 行内内容 */
  inlines: MdInline[] = [];
  /** 代码块语言 */
  lang: string = '';
  /** 原始文本（代码 / HTML / 数学） */
  rawContent: string = '';
  /** 是否有序列表 */
  ordered: boolean = false;
  /** 列表项 */
  items: MdListItem[] = [];
  /** Callout 类型（NOTE / TIP / WARNING ...） */
  calloutType: string = '';
  /** 表格表头 */
  headers: string[] = [];
  /** 表格数据行 */
  rows: string[][] = [];
  /** 表格列对齐（left / center / right） */
  aligns: string[] = [];
  /** 嵌入目标（embed / image） */
  target: string = '';
}

/** 单条属性。 */
export class MdProperty {
  key: string = '';
  value: string = '';
  listValue: string[] = [];
  type: MdPropType = MdPropType.STRING;
}

/** YAML frontmatter。 */
export class MdFrontmatter {
  properties: MdProperty[] = [];
  tags: string[] = [];
  raw: string = '';
}

/** 扁平化后的行内片段，渲染层按片段着色。 */
export class MdInlineSegment {
  text: string = '';
  bold: boolean = false;
  italic: boolean = false;
  strike: boolean = false;
  code: boolean = false;
  /** 链接目标（wiki 链接为笔记名，markdown 链接为 url） */
  linkTarget: string = '';
  /** 链接类型：wiki / url / embed */
  linkKind: string = '';
  /** 标签名（不含 #） */
  tag: string = '';
}

/** 解析后的整篇文档。 */
export class MdDocument {
  title: string = '';
  frontmatter: MdFrontmatter = new MdFrontmatter();
  blocks: MdBlock[] = [];
}
