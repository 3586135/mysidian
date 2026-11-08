import { common } from '@kit.AbilityKit';
import { NoteRow, SearchHit, SearchQuery } from '@ohos/domain';
import { FuzzyMatcher, NoteDao, SearchDao } from '@ohos/vault';

/**
 * 搜索与导航视图模型：全文搜索、快速切换器。
 */
@ObservedV2
export class SearchViewModel {
  @Trace keyword: string = '';
  @Trace hits: SearchHit[] = [];
  @Trace busy: boolean = false;
  @Trace quickKeyword: string = '';
  @Trace quickItems: NoteRow[] = [];

  private context: common.Context | null = null;
  private notes: NoteRow[] = [];

  public setContext(context: common.Context): void {
    this.context = context;
  }

  /** 执行全文搜索。 */
  public async search(vaultId: number, keyword: string): Promise<void> {
    this.keyword = keyword;
    const context: common.Context | null = this.context;
    if (context === null) {
      return;
    }
    const query: SearchQuery = new SearchQuery();
    query.text = keyword;
    this.busy = true;
    try {
      this.hits = await SearchDao.search(context, vaultId, query);
    } finally {
      this.busy = false;
    }
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
