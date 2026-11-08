import { common } from '@kit.AbilityKit';
import { LinkKind, LinkRef, MdBlock, MdDocument, MdInline, MdInlineType, NoteRow } from '@ohos/domain';
import { BlockDao } from '../db/BlockDao';
import { LinkDao } from '../db/LinkDao';
import { NoteDao } from '../db/NoteDao';
import { PropDao } from '../db/PropDao';
import { TagDao } from '../db/TagDao';
import { VaultPath } from '../manager/VaultPath';

/**
 * 索引管线：把解析后的文档写入块 / 链接 / 标签 / 属性索引表。
 * 索引必须可以完全从源文件重建，数据库只是缓存。
 */
export class IndexPipeline {
  /**
   * 为单篇笔记建立索引。
   * @param context 应用上下文
   * @param note 笔记元数据
   * @param document 解析后的文档
   */
  public static async indexNote(context: common.Context, note: NoteRow,
    document: MdDocument): Promise<void> {
    await BlockDao.replaceForNote(context, note.id, document.blocks);

    const resolver: Map<string, string> = await IndexPipeline.buildResolver(context, note.vaultId);
    const links: LinkRef[] = IndexPipeline.collectLinks(document, resolver);
    await LinkDao.replaceForNote(context, note.id, links);

    const tags: string[] = IndexPipeline.collectTags(document);
    await TagDao.replaceForNote(context, note.id, tags);

    await PropDao.replaceForNote(context, note.id, document.frontmatter.properties);
  }

  /** 重建整个仓库的索引。 */
  public static async reindexVault(context: common.Context, vaultId: number,
    documents: Map<string, MdDocument>): Promise<void> {
    const notes: NoteRow[] = await NoteDao.listByVault(context, vaultId);
    for (const note of notes) {
      const document: MdDocument | undefined = documents.get(note.path);
      if (document === undefined) {
        continue;
      }
      await IndexPipeline.indexNote(context, note, document);
    }
  }

  /** 构建「文件名 → 相对路径」的解析表。 */
  private static async buildResolver(context: common.Context, vaultId: number):
    Promise<Map<string, string>> {
    const resolver: Map<string, string> = new Map<string, string>();
    const notes: NoteRow[] = await NoteDao.listByVault(context, vaultId);
    for (const note of notes) {
      const key: string = VaultPath.basenameWithoutExt(note.path).toLowerCase();
      if (!resolver.has(key)) {
        resolver.set(key, note.path);
      }
    }
    return resolver;
  }

  /** 收集文档中的链接。 */
  private static collectLinks(document: MdDocument, resolver: Map<string, string>): LinkRef[] {
    const links: LinkRef[] = [];
    for (const block of document.blocks) {
      const context: string = IndexPipeline.blockText(block);
      for (const inline of block.inlines) {
        IndexPipeline.collectInlineLinks(inline, context, resolver, links);
      }
    }
    return links;
  }

  private static collectInlineLinks(inline: MdInline, context: string,
    resolver: Map<string, string>, links: LinkRef[]): void {
    for (const child of inline.children) {
      IndexPipeline.collectInlineLinks(child, context, resolver, links);
    }
    if (inline.type === MdInlineType.WIKI_LINK || inline.type === MdInlineType.EMBED) {
      const link: LinkRef = new LinkRef();
      link.targetRaw = inline.target;
      link.context = context;
      link.kind = inline.type === MdInlineType.EMBED ? LinkKind.EMBED : LinkKind.WIKI_LINK;
      const resolved: string | undefined = resolver.get(inline.target.toLowerCase());
      if (resolved !== undefined) {
        link.targetPath = resolved;
        link.resolved = true;
      }
      links.push(link);
      return;
    }
    if (inline.type === MdInlineType.LINK) {
      const link: LinkRef = new LinkRef();
      link.targetRaw = inline.url;
      link.context = context;
      link.kind = LinkKind.MARKDOWN;
      links.push(link);
      return;
    }
    if (inline.type === MdInlineType.TAG) {
      const link: LinkRef = new LinkRef();
      link.targetRaw = inline.text;
      link.context = context;
      link.kind = LinkKind.TAG;
      links.push(link);
    }
  }

  /** 收集文档中的标签（含 frontmatter 标签）。 */
  private static collectTags(document: MdDocument): string[] {
    const tags: string[] = [];
    for (const tag of document.frontmatter.tags) {
      IndexPipeline.addTag(tags, tag);
    }
    for (const block of document.blocks) {
      for (const inline of block.inlines) {
        IndexPipeline.collectInlineTags(inline, tags);
      }
    }
    return tags;
  }

  private static collectInlineTags(inline: MdInline, tags: string[]): void {
    for (const child of inline.children) {
      IndexPipeline.collectInlineTags(child, tags);
    }
    if (inline.type === MdInlineType.TAG) {
      IndexPipeline.addTag(tags, inline.text);
    }
  }

  private static addTag(tags: string[], tag: string): void {
    if (tag.length > 0 && !tags.includes(tag)) {
      tags.push(tag);
    }
  }

  private static blockText(block: MdBlock): string {
    let text: string = '';
    for (const inline of block.inlines) {
      text += IndexPipeline.inlineText(inline);
    }
    if (text.length === 0) {
      return block.rawContent;
    }
    return text;
  }

  private static inlineText(inline: MdInline): string {
    if (inline.children.length > 0) {
      let text: string = '';
      for (const child of inline.children) {
        text += IndexPipeline.inlineText(child);
      }
      return text;
    }
    return inline.text;
  }
}
