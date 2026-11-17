/**
 * ArkUI RichEditor 所见即所得（WYSIWYG）编辑器文档模型。
 * 纯数据类型，无 ArkUI 运行时依赖，供 parser/editor 与单元测试共用。
 */

/** 段落级块类型。 */
export enum WysiwygBlockKind {
  PARAGRAPH = 'paragraph',
  HEADING = 'heading',
  BULLET = 'bullet',
  ORDERED = 'ordered',
  TASK = 'task',
  QUOTE = 'quote',
  CALLOUT = 'callout',
  CODE = 'code',
  HR = 'hr',
  MATH = 'math',
  TABLE = 'table',
  HTML = 'html',
  IMAGE = 'image',
  EMBED = 'embed'
}

/** 行内特殊语义标记类型（附加在 TextSpan 上用于无损序列化）。 */
export enum WysiwygSpanKind {
  PLAIN = 'plain',
  WIKI_LINK = 'wiki',
  MD_LINK = 'link',
  TAG = 'tag',
  MATH_INLINE = 'math'
}

/** 所见即所得行内片段。 */
export class WysiwygInline {
  text: string = '';
  bold: boolean = false;
  italic: boolean = false;
  strike: boolean = false;
  highlight: boolean = false;
  code: boolean = false;
  kind: WysiwygSpanKind = WysiwygSpanKind.PLAIN;
  /** 语义目标：WIKI_LINK 为原始内部串，MD_LINK 为 URL，TAG 为标签名，MATH_INLINE 为 TeX。 */
  target: string = '';
  /** 加载时展示文本：用于检测用户是否编辑过链接别名/文本。 */
  originalDisplay: string = '';
  isImage: boolean = false;
  imageTarget: string = '';
  imageAlt: string = '';
  imageWidth: number = 0;
  imageRawMd: string = '';

  public clone(): WysiwygInline {
    const copy: WysiwygInline = new WysiwygInline();
    copy.text = this.text;
    copy.bold = this.bold;
    copy.italic = this.italic;
    copy.strike = this.strike;
    copy.highlight = this.highlight;
    copy.code = this.code;
    copy.kind = this.kind;
    copy.target = this.target;
    copy.originalDisplay = this.originalDisplay;
    copy.isImage = this.isImage;
    copy.imageTarget = this.imageTarget;
    copy.imageAlt = this.imageAlt;
    copy.imageWidth = this.imageWidth;
    copy.imageRawMd = this.imageRawMd;
    return copy;
  }

  public static plain(text: string): WysiwygInline {
    const item: WysiwygInline = new WysiwygInline();
    item.text = text;
    return item;
  }
}

/** 所见即所得单个段落。 */
export class WysiwygParagraph {
  kind: WysiwygBlockKind = WysiwygBlockKind.PARAGRAPH;
  /** HEADING 层级 1..6。 */
  level: number = 0;
  /** LIST / TASK 缩进层级 0..4。 */
  indent: number = 0;
  /** ORDERED 序号。 */
  ordinal: number = 1;
  /** 有序列表分隔符 '.' 或 ')'。 */
  orderedDelimiter: string = '.';
  /** 无序/任务列表前缀符 '-' / '*' / '+'。 */
  bulletChar: string = '-';
  /** TASK 勾选态。 */
  checked: boolean = false;
  /** CODE 围栏语言。 */
  lang: string = '';
  /** CALLOUT 类型（NOTE / TIP / WARNING 等）。 */
  calloutType: string = '';
  /** CALLOUT 是否有折叠标记。 */
  calloutHasFoldMarker: boolean = false;
  /** CALLOUT 是否默认折叠（'-' 为折叠，'+' 为展开）。 */
  calloutFolded: boolean = false;
  /** 仅从已有文档加载时记录与下一非空块间的精确分隔（'\n' 或 '' 表示默认 '\n\n'）。 */
  tightBreakAfter: boolean = false;
  /** 同类相邻独立块（如两段连续代码块）分组 ID，防止合并序列化。 */
  blockGroupId: number = 0;
  /** 表格块的完整原始 Markdown（仅 kind === TABLE 时使用，单个空格占位 RichEditor 图片 span）。 */
  tableRawMd: string = '';
  inlines: WysiwygInline[] = [];

  public clone(): WysiwygParagraph {
    const copy: WysiwygParagraph = new WysiwygParagraph();
    copy.kind = this.kind;
    copy.level = this.level;
    copy.indent = this.indent;
    copy.ordinal = this.ordinal;
    copy.orderedDelimiter = this.orderedDelimiter;
    copy.bulletChar = this.bulletChar;
    copy.checked = this.checked;
    copy.lang = this.lang;
    copy.calloutType = this.calloutType;
    copy.calloutHasFoldMarker = this.calloutHasFoldMarker;
    copy.calloutFolded = this.calloutFolded;
    copy.tightBreakAfter = this.tightBreakAfter;
    copy.blockGroupId = this.blockGroupId;
    copy.tableRawMd = this.tableRawMd;
    for (const inline of this.inlines) {
      copy.inlines.push(inline.clone());
    }
    return copy;
  }
}

/** 整篇 WYSIWYG 文档。 */
export class WysiwygDocument {
  hasFrontmatter: boolean = false;
  /** frontmatter 分隔线内的原始 YAML 内容（不含首尾 `---`）。 */
  frontmatterRaw: string = '';
  /** frontmatter 闭合分隔行后是否紧跟空行。 */
  frontmatterBlankAfter: boolean = true;
  paragraphs: WysiwygParagraph[] = [];
}
