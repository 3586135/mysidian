import { common } from '@kit.AbilityKit';
import { NoteRow, SearchHit, SearchQuery, TagRef } from '@ohos/domain';
import { FuzzyMatcher, NoteDao, SearchDao, TagDao } from '@ohos/vault';

/**
 * 搜索与导航视图模型：全文搜索、快速切换器。
 * 搜索模式：0 全文 / 1 标签 / 2 属性（frontmatter）。
 */
@ObservedV2
export class SearchViewModel {
  @Trace keyword: string = '';
  @Trace hits: SearchHit[] = [];
  @Trace busy: boolean = false;
  @Trace searchMode: number = 0;
  @Trace tagChips: TagRef[] = [];
  @Trace activeTag: string = '';
  @Trace quickKeyword: string = '';
  @Trace quickItems: NoteRow[] = [];

  private context: common.Context | null = null;
  private notes: NoteRow[] = [];

  public setContext(context: common.Context): void {
    this.context = context;
  }

  /** 切换搜索模式并重置结果。 */
  public async setMode(vaultId: number, mode: number): Promise<void> {
    this.searchMode = mode;
    this.keyword = '';
    this.activeTag = '';
    this.hits = [];
    this.tagChips = [];
    await this.search(vaultId, '');
  }

  /** 执行搜索（按当前模式分发）。 */
  public async search(vaultId: number, keyword: string): Promise<void> {
    this.keyword = keyword;
    const context: common.Context | null = this.context;
    if (context === null) {
      return;
    }
    this.busy = true;
    try {
      if (this.searchMode === 1) {
        await this.searchTags(context, vaultId, keyword);
        return;
      }
      if (this.searchMode === 2) {
        await this.searchProps(vaultId, keyword);
        return;
      }
      const query: SearchQuery = new SearchQuery();
      query.text = keyword;
      this.hits = await SearchDao.search(context, vaultId, query);
    } finally {
      this.busy = false;
    }
  }

  /** 标签模式：刷新标签候选；已选中标签时展示该标签的笔记。 */
  private async searchTags(context: common.Context, vaultId: number, keyword: string): Promise<void> {
    const all: TagRef[] = await TagDao.listAll(context, vaultId);
    const filter: string = keyword.trim().toLowerCase();
    const filtered: TagRef[] = [];
    for (const ref of all) {
      if (filter.length === 0 || ref.tag.toLowerCase().includes(filter)) {
        filtered.push(ref);
      }
    }
    this.tagChips = filtered;
    if (this.activeTag.length === 0) {
      this.hits = [];
      return;
    }
    const query: SearchQuery = new SearchQuery();
    query.tag = this.activeTag;
    this.hits = await SearchDao.search(context, vaultId, query);
  }

  /** 属性模式：输入「属性名:属性值」（任一段可空）检索笔记。 */
  private async searchProps(vaultId: number, keyword: string): Promise<void> {
    const context: common.Context | null = this.context;
    if (context === null) {
      return;
    }
    const input: string = keyword.trim();
    const query: SearchQuery = new SearchQuery();
    const separator: number = input.indexOf(':');
    if (separator >= 0) {
      query.propKey = input.substring(0, separator).trim();
      query.propValue = input.substring(separator + 1).trim();
    } else {
      query.propValue = input;
    }
    if (query.propKey.length === 0 && query.propValue.length === 0) {
      this.hits = [];
      return;
    }
    this.hits = await SearchDao.search(context, vaultId, query);
  }

  /** 选中一个标签，展示使用该标签的笔记。 */
  public async selectTag(vaultId: number, tag: string): Promise<void> {
    this.activeTag = tag;
    await this.search(vaultId, this.keyword);
  }

  /** 载入仓库全部笔记，供快速切换器使用。 */
  public async loadNotes(vaultId: number): Promise<void> {
    const context: common.Context | null = this.context;
    if (context === null) {
      return;
    }
    this.notes = await NoteDao.listByVault(context, vaultId);
    this.applyQuickFilter();
  }

  /** 更新快速切换器关键字。 */
  public updateQuickKeyword(keyword: string): void {
    this.quickKeyword = keyword;
    this.applyQuickFilter();
  }

  private applyQuickFilter(): void {
    const keyword: string = this.quickKeyword.trim();
    if (keyword.length === 0) {
      this.quickItems = this.notes.slice(0, 20);
      return;
    }
    const scored: ScoredNote[] = [];
    for (const note of this.notes) {
      const score: number = Math.max(
        FuzzyMatcher.score(keyword, note.title),
        FuzzyMatcher.score(keyword, note.path) - 50);
      if (score >= 0) {
        const item: ScoredNote = new ScoredNote();
        item.note = note;
        item.score = score;
        scored.push(item);
      }
    }
    scored.sort((left: ScoredNote, right: ScoredNote): number => right.score - left.score);
    const result: NoteRow[] = [];
    for (const item of scored) {
      result.push(item.note);
      if (result.length >= 20) {
        break;
      }
    }
    this.quickItems = result;
  }
}

/** 模糊匹配打分项。 */
export class ScoredNote {
  note: NoteRow = new NoteRow();
  score: number = 0;
}
