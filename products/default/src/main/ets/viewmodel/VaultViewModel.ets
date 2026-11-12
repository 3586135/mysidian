import { common, Want } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { BacklinkItem, CalendarDay, DataViewEntry, DataViewResult, DataViewTask, FileNode,
  FlatFileNode, GraphData, GraphEdge, GraphNode, LinkRef, MdBlock, MdBlockType, MdDocument,
  MdFrontmatter, MdListItem, MdPropType, MdProperty, NoteRow, OutlineEntry, TagRef,
  UnlinkedMention, VaultInfo } from '@ohos/domain';
import { Logger } from '@ohos/common';
import { DataViewQuery, FrontmatterSerializer, MarkdownParser, TaskMetadata } from '@ohos/markdown';
import { AttachmentResolver, BlockDao, DiffLine, FileHistory, FileStatInfo, HistorySnapshot,
  IndexPipeline, LinkDao, LinkRewriter, NoteDao, NoteResolver, PropDao, TagDao, TemplateEngine,
  TemplateRenderResult, VaultManager, VaultPath } from '@ohos/vault';
import { AbilityContextHolder } from '../defaultability/AbilityContextHolder';

const LOG: Logger = new Logger('MySidianVM');
const PREFERENCE_STORE: string = 'mysidian_preferences';
const RECENT_LOG_KEY: string = 'recent_note_log';
const RECENT_LOG_LIMIT: number = 100;

/** 最近访问日志条目（持久化）。 */
export class RecentNoteEntry {
  vaultId: number = -1;
  path: string = '';
  openedAt: number = 0;
}

/** 最近访问列表展示项。 */
export class RecentNoteItem {
  path: string = '';
  title: string = '';
  openedAt: number = 0;
}

/**
 * 仓库视图模型：负责仓库列表、文件树、笔记读取编辑、索引与信息面板。
 */
@ObservedV2
export class VaultViewModel {
  @Trace vaults: VaultInfo[] = [];
  @Trace currentVault: VaultInfo = new VaultInfo();
  @Trace treeItems: FlatFileNode[] = [];
  @Trace selectedPath: string = '';
  @Trace noteTitle: string = '';
  @Trace noteContent: string = '';
  @Trace document: MdDocument = new MdDocument();
  @Trace busy: boolean = false;
  /** 是否有可返回的历史笔记（供底部迷你栏按钮禁用态）。 */
  @Trace canGoBack: boolean = false;
  /** 最近访问的笔记（当前仓库）。 */
  @Trace recentNotes: RecentNoteItem[] = [];

  /** 编辑态。 */
  @Trace editMode: boolean = false;
  /** 编辑器缓冲区（非响应式，避免输入时重建 TextArea 造成光标跳动）。 */
  draftBuffer: string = '';
  /** 待应用的光标位置（模板渲染后的 {{cursor}} 位置，-1 表示无）。 */
  @Trace pendingCaret: number = -1;
  /** 信息面板。 */
  @Trace infoTabIndex: number = 0;
  @Trace outline: OutlineEntry[] = [];
  @Trace backlinks: BacklinkItem[] = [];
  @Trace noteTags: string[] = [];
  @Trace noteProperties: MdProperty[] = [];
  /** 正文字号。 */
  @Trace fontSize: number = 16;

  /** 反向链接面板增强：未链接提及。 */
  @Trace unlinked: UnlinkedMention[] = [];
  /** 仓库内全部标签（# 标签补全候选）。 */
  @Trace allTagNames: string[] = [];
  /** 局部关系图谱数据。 */
  @Trace graph: GraphData = new GraphData();
  /** 分屏第二栏的笔记路径（宽屏分屏双开）。 */
  @Trace secondaryPath: string = '';
  @Trace secondaryContent: string = '';
  @Trace secondaryDocument: MdDocument = new MdDocument();

  private manager: VaultManager | null = null;
  private context: common.Context | null = null;
  private uiContext: UIContext | null = null;
  private tree: FileNode[] = [];
  private expandedPaths: string[] = [];
  private noteHistory: string[] = [];
  /** 笔记打开令牌：快速连续打开时旧请求据此放弃，防止竞态覆盖。 */
  private openToken: number = 0;
  /** Dataview 查询结果缓存（key: 查询文本|当前笔记路径）。 */
  private dataViewCache: Map<string, DataViewResult> = new Map();
  /** 仓库内全部文件的相对路径（附件解析用）。 */
  private vaultFiles: string[] = [];

  /** 锚点跳转回调：由页面注入（负责滚动到目标标题块）。 */
  public onScrollToHeading: (heading: string) => void = (heading: string): void => {};
  /** 自动创建笔记回调：由页面注入（用于提示用户）。 */
  public onNoteCreated: (path: string) => void = (path: string): void => {};

  /** 绑定 UI 上下文，用于驱动界面过渡动画。 */
  public attachUi(ui: UIContext): void {
    this.uiContext = ui;
  }

  /** 初始化存储层并加载仓库列表。 */
  public async init(context: common.Context): Promise<void> {
    try {
      this.context = context;
      this.manager = await VaultManager.create(context);
      await this.loadPreferences(context);
      await this.refreshVaults();
      if (this.vaults.length > 0) {
        await this.restoreLastSession();
      }
    } catch (error) {
      LOG.error('vault view model init failed');
    }
  }

  /** 恢复上次会话：优先打开上次使用的仓库与笔记。 */
  private async restoreLastSession(): Promise<void> {
    const context: common.Context | null = this.context;
    if (context === null) {
      return;
    }
    const lastVaultId: number = await this.readNumberPref(context, 'lastVaultId', -1);
    let target: VaultInfo = this.vaults[0];
    for (const vault of this.vaults) {
      if (vault.id === lastVaultId) {
        target = vault;
        break;
      }
    }
    await this.selectVault(target);
    const lastNotePath: string = await this.readStringPref(context, 'lastNotePath', '');
    if (lastNotePath.length === 0) {
      return;
    }
    const note: NoteRow | null = await NoteDao.findByPath(context, this.currentVault.id,
      lastNotePath);
    if (note === null) {
      return;
    }
    await this.openNote(lastNotePath);
  }

  private async readNumberPref(context: common.Context, key: string, def: number):
    Promise<number> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context,
        PREFERENCE_STORE);
      const value: preferences.ValueType = await store.get(key, def);
      if (typeof value === 'number') {
        return value;
      }
    } catch (error) {
      LOG.error('read preference failed');
    }
    return def;
  }

  private async readStringPref(context: common.Context, key: string, def: string):
    Promise<string> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context,
        PREFERENCE_STORE);
      const value: preferences.ValueType = await store.get(key, def);
      if (typeof value === 'string') {
        return value;
      }
    } catch (error) {
      LOG.error('read preference failed');
    }
    return def;
  }

  private async writePref(key: string, value: preferences.ValueType): Promise<void> {
    const context: common.Context | null = this.context;
    if (context === null) {
      return;
    }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context,
        PREFERENCE_STORE);
      await store.put(key, value);
      await store.flush();
    } catch (error) {
      LOG.error('write preference failed');
    }
  }

  /** 更新正文字号并持久化。 */
  public async setFontSize(size: number): Promise<void> {
    this.fontSize = size;
    const context: common.Context | null = this.context;
    if (context === null) {
      return;
    }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context,
        PREFERENCE_STORE);
      await store.put('fontSize', size);
      await store.flush();
    } catch (error) {
      LOG.error('save font size failed');
    }
  }

  private async loadPreferences(context: common.Context): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context,
        PREFERENCE_STORE);
      const value: preferences.ValueType = await store.get('fontSize', 16);
      if (typeof value === 'number') {
        this.fontSize = value;
      }
    } catch (error) {
      LOG.error('load preferences failed');
    }
  }

  /** 重新加载仓库列表。 */
  public async refreshVaults(): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    this.vaults = await manager.listVaults();
  }

  /** 切换当前仓库。 */
  public async selectVault(vault: VaultInfo): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    this.currentVault = vault;
    this.expandedPaths = [];
    this.closeNote();
    this.writePref('lastVaultId', vault.id);
    await this.refreshTree();
    await this.ensureIndexed(vault);
    await this.loadRecentNotes();
  }

  /** 为尚未建立索引的笔记补建索引。 */
  private async ensureIndexed(vault: VaultInfo): Promise<void> {
    await this.syncIndex(vault);
  }

  /**
   * 增量同步索引：补建缺失索引，并重建被外部修改（同步 / 手动编辑）的笔记。
   *
   * 通过 mtime + size 比对判断文件是否变化，避免每次启动全量重建。
   */
  public async syncIndex(vault: VaultInfo): Promise<void> {
    const context: common.Context | null = this.context;
    const manager: VaultManager | null = this.manager;
    if (context === null || manager === null) {
      return;
    }
    const notes: NoteRow[] = await NoteDao.listByVault(context, vault.id);
    const known: Record<string, NoteRow> = {};
    for (const note of notes) {
      known[note.path] = note;
    }
    const files: string[] = await manager.listVaultFiles(vault);
    const fileSet: Record<string, boolean> = {};
    for (const path of files) {
      fileSet[path] = true;
    }
    let changed: number = 0;
    for (const path of files) {
      if (!path.toLowerCase().endsWith('.md')) {
        continue;
      }
      const row: NoteRow | undefined = known[path];
      if (row === undefined) {
        await this.indexNoteByPath(vault, path);
        changed++;
        continue;
      }
      const stat: FileStatInfo | null = manager.statFile(vault, path);
      if (stat === null) {
        continue;
      }
      const blockCount: number = await BlockDao.countOfNote(context, row.id);
      if (blockCount === 0 || stat.mtime !== row.mtime || stat.size !== row.size) {
        await this.indexNoteByPath(vault, path);
        changed++;
      }
    }
    // 清理幽灵行：文件已不存在（外部删除 / 同步删除）但索引仍残留的笔记。
    for (const note of notes) {
      if (fileSet[note.path] !== true) {
        await NoteDao.removeByPath(context, vault.id, note.path);
        changed++;
      }
    }
    if (changed > 0) {
      LOG.info(`sync index rebuilt ${changed} note(s)`);
      this.dataViewCache.clear();
    }
  }

  /** 重建单篇笔记的索引（外部改动后使用）。 */
  private async indexNoteByPath(vault: VaultInfo, path: string): Promise<void> {
    const context: common.Context | null = this.context;
    const manager: VaultManager | null = this.manager;
    if (context === null || manager === null) {
      return;
    }
    const row: NoteRow | null = await manager.refreshNote(vault, path);
    if (row === null) {
      return;
    }
    const content: string = await manager.readNote(vault, path);
    const document: MdDocument = MarkdownParser.parse(content);
    await IndexPipeline.indexNote(context, row, document);
  }

  /** 展开或折叠目录。 */
  public toggleDir(path: string): void {
    const index: number = this.expandedPaths.indexOf(path);
    if (index >= 0) {
      this.expandedPaths.splice(index, 1);
    } else {
      this.expandedPaths.push(path);
    }
    this.refreshTreeItems();
  }

  /** 打开笔记；索引已在导入/保存时建立，此处仅在缺失时补建。 */
  public async openNote(path: string): Promise<void> {
    await this.openNoteInternal(path, true);
  }

  /** 是否存在可返回的历史笔记。 */
  public canGoBackNote(): boolean {
    return this.noteHistory.length > 0;
  }

  /** 返回上一个打开的笔记；无历史时返回 false。 */
  public async goBackNote(): Promise<boolean> {
    const previous: string = this.noteHistory.length > 0
      ? this.noteHistory[this.noteHistory.length - 1] : '';
    if (previous.length === 0) {
      return false;
    }
    this.noteHistory.pop();
    this.canGoBack = this.noteHistory.length > 0;
    await this.openNoteInternal(previous, false);
    return true;
  }

  /** 加载当前仓库最近访问的笔记列表。 */
  public async loadRecentNotes(): Promise<void> {
    const entries: RecentNoteEntry[] = await this.readRecentLog();
    const items: RecentNoteItem[] = [];
    for (const entry of entries) {
      if (entry.vaultId !== this.currentVault.id || items.length >= 20) {
        continue;
      }
      const item: RecentNoteItem = new RecentNoteItem();
      item.path = entry.path;
      item.title = this.noteDisplayName(entry.path);
      item.openedAt = entry.openedAt;
      items.push(item);
    }
    this.recentNotes = items;
  }

  /** 切换任务勾选状态：按行号回写源文本并重建索引。 */
  public async toggleTask(rawLine: string, lineNumber: number, checked: boolean): Promise<void> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    if (manager === null || context === null || this.selectedPath.length === 0) {
      return;
    }
    const nextLine: string = TaskMetadata.toggle(rawLine, checked);
    if (nextLine === rawLine) {
      return;
    }
    const nextContent: string = VaultViewModel.replaceTaskLine(this.noteContent, rawLine, nextLine, lineNumber);
    await manager.writeNote(this.currentVault, this.selectedPath, nextContent);
    this.noteContent = nextContent;
    this.document = MarkdownParser.parse(nextContent);
    this.dataViewCache.clear();
    await manager.refreshNote(this.currentVault, this.selectedPath);
    await this.reindexCurrentNote();
    await this.refreshNoteInfo();
  }

  /** 按行号替换任务行；行号失配时回退首次精确匹配，避免重复任务行错改。 */
  private static replaceTaskLine(content: string, rawLine: string, nextLine: string,
    lineNumber: number): string {
    if (lineNumber >= 0) {
      const lines: string[] = content.split('\n');
      if (lineNumber < lines.length) {
        const current: string = lines[lineNumber];
        const endsCr: boolean = current.endsWith('\r');
        const body: string = endsCr ? current.substring(0, current.length - 1) : current;
        if (body === rawLine) {
          lines[lineNumber] = endsCr ? `${nextLine}\r` : nextLine;
          return lines.join('\n');
        }
      }
    }
    return content.replace(rawLine, nextLine);
  }

  /** 执行 Dataview 查询：TASK 任务聚合 / live TABLE/LIST 笔记条目（带缓存）。 */
  public async runDataViewQuery(query: string): Promise<DataViewResult> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    const result: DataViewResult = new DataViewResult();
    if (manager === null || context === null) {
      return result;
    }
    const cacheKey: string = `${query}|${this.selectedPath}`;
    const cached: DataViewResult | undefined = this.dataViewCache.get(cacheKey);
    if (cached !== undefined) {
      return cached;
    }
    const dvQuery: DataViewQuery = DataViewQuery.parse(query);
    if (dvQuery.isTaskQuery()) {
      const tasks: DataViewTask[] = [];
      const rows: NoteRow[] = await NoteDao.listByVault(context, this.currentVault.id);
      for (const row of rows) {
        if (row.ext !== 'md' || (dvQuery.excludeCurrent && row.path === this.selectedPath)) {
          continue;
        }
        const content: string = await manager.readNote(this.currentVault, row.path);
        const parsed: MdDocument = MarkdownParser.parse(content);
        // FROM #tag 为笔记级语义：先按页匹配来源标签，页内任务不再逐行检查。
        if (!dvQuery.matchesPageSourceTag(content, parsed.frontmatter.tags)) {
          continue;
        }
        this.collectTasks(parsed.blocks, dvQuery, row.path, tasks);
      }
      this.sortTasks(tasks, dvQuery);
      this.applyLimit(tasks, dvQuery);
      result.tasks = tasks;
    } else if (dvQuery.live && (dvQuery.isTableQuery() || dvQuery.isListQuery())) {
      result.entries = await this.collectEntries(dvQuery);
    } else {
      return result;
    }
    this.dataViewCache.set(cacheKey, result);
    return result;
  }

  /** 聚合 live TABLE/LIST 查询的笔记条目（按路径升序）。 */
  private async collectEntries(query: DataViewQuery): Promise<DataViewEntry[]> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    const entries: DataViewEntry[] = [];
    if (manager === null || context === null) {
      return entries;
    }
    const rows: NoteRow[] = await NoteDao.listByVault(context, this.currentVault.id);
    for (const row of rows) {
      if (row.ext !== 'md') {
        continue;
      }
      const content: string = await manager.readNote(this.currentVault, row.path);
      const parsed: MdDocument = MarkdownParser.parse(content);
      if (!query.matchesPage(content, parsed.frontmatter.tags, row.path, this.selectedPath)) {
        continue;
      }
      const entry: DataViewEntry = new DataViewEntry();
      entry.path = row.path;
      entry.fileName = this.noteDisplayName(row.path);
      entry.cells = this.extractEntryCells(query, parsed.frontmatter, entry.fileName);
      entries.push(entry);
    }
    entries.sort((a: DataViewEntry, b: DataViewEntry): number => a.path.localeCompare(b.path));
    this.sortEntries(entries, query);
    this.applyEntryLimit(entries, query);
    return entries;
  }

  /** 截断任务结果（LIMIT n）。 */
  private applyLimit(tasks: DataViewTask[], query: DataViewQuery): void {
    if (query.limit <= 0 || tasks.length <= query.limit) {
      return;
    }
    tasks.length = query.limit;
  }

  /** 截断笔记条目结果（LIMIT n）。 */
  private applyEntryLimit(entries: DataViewEntry[], query: DataViewQuery): void {
    if (query.limit <= 0 || entries.length <= query.limit) {
      return;
    }
    entries.length = query.limit;
  }

  /** 提取条目属性列值：LIST 取 listProp，TABLE 按 tableProps 顺序。 */
  private extractEntryCells(query: DataViewQuery, frontmatter: MdFrontmatter,
    fileName: string): string[] {
    const keys: string[] = query.isListQuery() ? [query.listProp] : query.tableProps;
    const cells: string[] = [];
    for (const key of keys) {
      if (key.length === 0) {
        continue;
      }
      if (key === 'file' || key === 'File') {
        cells.push(`[[${fileName}]]`);
        continue;
      }
      cells.push(this.frontmatterValue(frontmatter, key));
    }
    return cells;
  }

  /** 按 key 查找 frontmatter 属性值（列表值逗号拼接），缺失返回空串。 */
  private frontmatterValue(frontmatter: MdFrontmatter, key: string): string {
    for (const property of frontmatter.properties) {
      if (property.key === key) {
        if (property.type === MdPropType.LIST) {
          return property.listValue.join(', ');
        }
        return property.value;
      }
    }
    return '';
  }

  /** 从文档块中收集 LIST 任务。 */
  private collectTasks(blocks: MdBlock[], query: DataViewQuery, path: string,
    out: DataViewTask[]): void {
    for (const block of blocks) {
      if (block.type === MdBlockType.LIST) {
        this.collectTaskItems(block.items, query, path, out);
      }
    }
  }

  /** 递归收集列表项中的任务。 */
  private collectTaskItems(items: MdListItem[], query: DataViewQuery, path: string,
    out: DataViewTask[]): void {
    for (const item of items) {
      if (item.isTask && query.matchesItem(item)) {
        const task: DataViewTask = new DataViewTask();
        task.path = path;
        task.fileName = this.noteDisplayName(path);
        task.item = item;
        out.push(task);
      }
      this.collectTaskItems(item.children, query, path, out);
    }
  }

  /** 按查询字段排序任务。 */
  private sortTasks(tasks: DataViewTask[], query: DataViewQuery): void {
    if (query.sortField.length === 0) {
      return;
    }
    tasks.sort((a: DataViewTask, b: DataViewTask): number => {
      const left: string = this.taskFieldValue(a, query.sortField);
      const right: string = this.taskFieldValue(b, query.sortField);
      const result: number = left < right ? -1 : (left > right ? 1 : 0);
      return query.sortDesc ? -result : result;
    });
  }

  /** 取任务的排序字段值。 */
  private taskFieldValue(task: DataViewTask, field: string): string {
    const key: string = field.toLowerCase();
    if (key === 'due' || key === 'duedate') {
      return task.item.dueDate;
    }
    if (key === 'start' || key === 'startdate') {
      return task.item.startDate;
    }
    if (key === 'scheduled' || key === 'scheduleddate') {
      return task.item.scheduledDate;
    }
    if (key === 'priority') {
      return task.item.priority;
    }
    if (key === 'file' || key === 'file.name' || key === 'filename') {
      return task.fileName;
    }
    if (key === 'path') {
      return task.path;
    }
    return task.item.rawLine;
  }

  /** 按查询字段排序笔记条目。 */
  private sortEntries(entries: DataViewEntry[], query: DataViewQuery): void {
    if (query.sortField.length === 0) {
      return;
    }
    entries.sort((a: DataViewEntry, b: DataViewEntry): number => {
      const left: string = this.entryFieldValue(a, query, query.sortField);
      const right: string = this.entryFieldValue(b, query, query.sortField);
      const result: number = left < right ? -1 : (left > right ? 1 : 0);
      return query.sortDesc ? -result : result;
    });
  }

  /** 取笔记条目的排序字段值。 */
  private entryFieldValue(entry: DataViewEntry, query: DataViewQuery, field: string): string {
    const key: string = field.toLowerCase();
    if (key === 'file' || key === 'file.name' || key === 'filename') {
      return entry.fileName;
    }
    if (key === 'path') {
      return entry.path;
    }
    for (let index = 0; index < query.tableProps.length; index++) {
      if (query.tableProps[index].toLowerCase() === key) {
        return index < entry.cells.length ? entry.cells[index] : '';
      }
    }
    return '';
  }

  /** 跨笔记勾选 Dataview 任务：回写来源笔记并刷新索引。 */
  public async toggleTaskInNote(task: DataViewTask, checked: boolean): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    const rawLine: string = task.item.rawLine;
    const nextLine: string = TaskMetadata.toggle(rawLine, checked);
    if (nextLine === rawLine) {
      return;
    }
    // 同步本地缓存行文本，保证后续再次勾选时基于最新行内容计算。
    task.item.rawLine = nextLine;
    if (task.path === this.selectedPath) {
      await this.toggleTask(rawLine, task.item.lineNumber, checked);
      return;
    }
    const content: string = await manager.readNote(this.currentVault, task.path);
    const nextContent: string =
      VaultViewModel.replaceTaskLine(content, rawLine, nextLine, task.item.lineNumber);
    await manager.writeNote(this.currentVault, task.path, nextContent);
    this.dataViewCache.clear();
    await manager.refreshNote(this.currentVault, task.path);
  }

  private noteDisplayName(path: string): string {
    const name: string = VaultPath.basename(path);
    return name.endsWith('.md') ? name.substring(0, name.length - 3) : name;
  }

  /** 读取最近访问日志（全部仓库）。 */
  private async readRecentLog(): Promise<RecentNoteEntry[]> {
    const context: common.Context | null = this.context;
    if (context === null) {
      return [];
    }
    const raw: string = await this.readStringPref(context, RECENT_LOG_KEY, '[]');
    const entries: RecentNoteEntry[] = [];
    try {
      const parsed: object = JSON.parse(raw) as object;
      if (Array.isArray(parsed)) {
        const array: object[] = parsed as object[];
        for (const element of array) {
          const candidate: RecentNoteEntry = element as RecentNoteEntry;
          if (typeof candidate.vaultId === 'number' && typeof candidate.path === 'string' &&
            typeof candidate.openedAt === 'number' && candidate.path.length > 0) {
            const entry: RecentNoteEntry = new RecentNoteEntry();
            entry.vaultId = candidate.vaultId;
            entry.path = candidate.path;
            entry.openedAt = candidate.openedAt;
            entries.push(entry);
          }
        }
      }
    } catch (error) {
      LOG.error('parse recent note log failed');
    }
    return entries;
  }

  /** 记录一次笔记访问并持久化。 */
  private async recordRecent(path: string): Promise<void> {
    const entry: RecentNoteEntry = new RecentNoteEntry();
    entry.vaultId = this.currentVault.id;
    entry.path = path;
    entry.openedAt = new Date().getTime();
    const entries: RecentNoteEntry[] = await this.readRecentLog();
    const kept: RecentNoteEntry[] = [entry];
    for (const existing of entries) {
      if (existing.vaultId === entry.vaultId && existing.path === entry.path) {
        continue;
      }
      kept.push(existing);
      if (kept.length >= RECENT_LOG_LIMIT) {
        break;
      }
    }
    await this.writePref(RECENT_LOG_KEY, JSON.stringify(kept));
    await this.loadRecentNotes();
  }

  /** 重命名 / 移动后同步导航状态中的旧路径（返回历史 + 最近访问）。 */
  private async rewritePathRefs(oldPath: string, newPath: string): Promise<void> {
    for (let index = 0; index < this.noteHistory.length; index++) {
      if (this.noteHistory[index] === oldPath) {
        this.noteHistory[index] = newPath;
      }
    }
    if (this.context === null) {
      return;
    }
    const entries: RecentNoteEntry[] = await this.readRecentLog();
    let changed: boolean = false;
    for (const entry of entries) {
      if (entry.vaultId === this.currentVault.id && entry.path === oldPath) {
        entry.path = newPath;
        changed = true;
      }
    }
    if (changed) {
      await this.writePref(RECENT_LOG_KEY, JSON.stringify(entries));
      await this.loadRecentNotes();
    }
  }

  /** 打开今天的日记（不存在则以日期为名新建，支持日记模板）。 */
  public async openDailyNote(): Promise<boolean> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    if (manager === null || context === null) {
      return false;
    }
    const now: Date = new Date();
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    const name: string = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
    const path: string = `${name}.md`;
    const existing: NoteRow | null = await NoteDao.findByPath(context, this.currentVault.id, path);
    let cursor: number = -1;
    if (existing === null) {
      // 存在日记模板时套用模板，否则写默认标题。
      const template: string = await this.findTemplate(['日记', 'daily', 'Daily', 'Journal']);
      let content: string = `# ${name}\n\n`;
      if (template.length > 0) {
        const raw: string = await manager.readTemplate(this.currentVault, template);
        const rendered: TemplateRenderResult = TemplateEngine.render(raw, name, now);
        content = rendered.content;
        cursor = rendered.cursorOffset;
      }
      await manager.writeNote(this.currentVault, path, content);
      await manager.refreshNote(this.currentVault, path);
      await this.refreshTree();
    }
    await this.openNote(path);
    if (cursor >= 0) {
      this.pendingCaret = cursor;
      this.startEdit();
    }
    return true;
  }

  /** 打开本周周报（不存在则以 YYYY-Www.md 新建，支持周报模板）。 */
  public async openWeeklyNote(): Promise<boolean> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    if (manager === null || context === null) {
      return false;
    }
    const now: Date = new Date();
    const key: string = TemplateEngine.weekKey(now);
    const path: string = `${key}.md`;
    const existing: NoteRow | null = await NoteDao.findByPath(context, this.currentVault.id, path);
    let cursor: number = -1;
    if (existing === null) {
      const template: string = await this.findTemplate(['周报', 'weekly', 'Weekly']);
      let content: string = `# ${key}\n\n`;
      if (template.length > 0) {
        const raw: string = await manager.readTemplate(this.currentVault, template);
        const rendered: TemplateRenderResult = TemplateEngine.render(raw, key, now);
        content = rendered.content;
        cursor = rendered.cursorOffset;
      }
      await manager.writeNote(this.currentVault, path, content);
      await manager.refreshNote(this.currentVault, path);
      await this.refreshTree();
    }
    await this.openNote(path);
    if (cursor >= 0) {
      this.pendingCaret = cursor;
      this.startEdit();
    }
    return true;
  }

  private async openNoteInternal(path: string, recordHistory: boolean): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    // 打开令牌：快速连续切换笔记时，旧请求在任意 await 后发现令牌已更新即放弃，
    // 防止慢的旧读取覆盖新笔记内容。
    const token: number = ++this.openToken;
    // 切换笔记前先落盘当前草稿，避免未保存内容被静默丢弃（同系统返回键处理）。
    if (this.editMode && this.draftBuffer !== this.noteContent) {
      await this.saveDraft();
    }
    if (token !== this.openToken) {
      return;
    }
    if (recordHistory && this.selectedPath.length > 0 && this.selectedPath !== path) {
      this.noteHistory.push(this.selectedPath);
      if (this.noteHistory.length > 50) {
        this.noteHistory.shift();
      }
      this.canGoBack = true;
    }
    const content: string = await manager.readNote(this.currentVault, path);
    if (token !== this.openToken) {
      return;
    }
    const document: MdDocument = MarkdownParser.parse(content);
    const title: string = document.title.length > 0 ? document.title : VaultPath.basename(path);
    this.applyDocument(path, content, document, title);
    await this.writePref('lastNotePath', path);
    if (token !== this.openToken) {
      return;
    }
    await this.recordRecent(path);
    if (token !== this.openToken) {
      return;
    }
    await this.ensureNoteIndexed();
    await this.refreshNoteInfo();
  }

  /** 以过渡动画应用新文档，避免正文生硬切换。 */
  private applyDocument(path: string, content: string, document: MdDocument, title: string): void {
    const ui: UIContext | null = this.uiContext;
    if (ui === null) {
      this.selectedPath = path;
      this.noteTitle = title;
      this.noteContent = content;
      this.document = document;
      this.editMode = false;
      this.draftBuffer = '';
      return;
    }
    ui.animateTo({ duration: 240, curve: Curve.Friction }, (): void => {
      this.selectedPath = path;
      this.noteTitle = title;
      this.noteContent = content;
      this.document = document;
      this.editMode = false;
      this.draftBuffer = '';
    });
  }

  /** 仅为尚未建立索引的当前笔记补建索引，避免每次打开全量重建。 */
  private async ensureNoteIndexed(): Promise<void> {
    const context: common.Context | null = this.context;
    if (context === null || this.selectedPath.length === 0) {
      return;
    }
    const note: NoteRow | null = await NoteDao.findByPath(context, this.currentVault.id,
      this.selectedPath);
    if (note === null) {
      return;
    }
    const count: number = await BlockDao.countOfNote(context, note.id);
    if (count > 0) {
      return;
    }
    await IndexPipeline.indexNote(context, note, this.document);
  }

  /**
   * 处理正文中的链接点击。
   * wiki 链接在仓库内跳转（支持 #标题 锚点）；url 交由系统浏览器打开。
   */
  public async openLink(target: string, kind: string): Promise<void> {
    if (kind === 'url') {
      this.openExternalLink(target);
      return;
    }
    const context: common.Context | null = this.context;
    if (context === null) {
      return;
    }
    // 拆分锚点：[[笔记#标题]] → 笔记目标 + 标题锚点。
    let noteTarget: string = target;
    let anchor: string = '';
    const hash: number = target.indexOf('#');
    if (hash >= 0) {
      noteTarget = target.substring(0, hash).trim();
      anchor = target.substring(hash + 1).trim();
    }
    if (noteTarget.length === 0) {
      // 本页锚点：无需重新打开笔记，直接滚动到目标标题。
      if (anchor.length > 0) {
        this.onScrollToHeading(anchor);
      }
      return;
    }
    const note = await NoteResolver.resolve(context, this.currentVault.id, noteTarget);
    if (note === null) {
      // 双链工作流：目标笔记不存在时自动创建同名笔记并打开（先写链接，后填内容）。
      const created: string = await this.createNoteByTitle(noteTarget);
      if (created.length === 0) {
        LOG.info(`unresolved wiki link: ${target}`);
        return;
      }
      await this.openNote(created);
      this.onNoteCreated(created);
      if (anchor.length > 0) {
        this.onScrollToHeading(anchor);
      }
      return;
    }
    await this.openNote(note.path);
    if (anchor.length > 0) {
      this.onScrollToHeading(anchor);
    }
  }

  /**
   * 按链接目标创建笔记（双链「先写链接、后填内容」）。
   *
   * @param title 链接目标（可含子目录，如 books/读书笔记）
   * @returns 新建笔记的相对路径；失败返回空串
   */
  private async createNoteByTitle(title: string): Promise<string> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    if (manager === null || context === null || title.length === 0) {
      return '';
    }
    const segments: string[] = title.split('/');
    const names: string[] = [];
    for (const segment of segments) {
      const trimmed: string = segment.trim();
      if (trimmed.length === 0) {
        return '';
      }
      const safe: string = VaultPath.sanitizeName(trimmed);
      if (safe.length === 0) {
        return '';
      }
      names.push(safe);
    }
    const joined: string = names.join('/');
    const path: string = joined.endsWith('.md') ? joined : `${joined}.md`;
    // 已存在同名笔记：直接打开，绝不覆盖用户已有内容。
    const existing: NoteRow | null = await NoteDao.findByPath(context, this.currentVault.id, path);
    if (existing !== null) {
      return existing.path;
    }
    await manager.writeNote(this.currentVault, path, '');
    await manager.refreshNote(this.currentVault, path);
    await this.refreshTree();
    return path;
  }

  /** 用系统默认应用打开外部链接。 */
  public openExternalLink(url: string): void {
    const trimmed: string = url.trim();
    if (trimmed.length === 0) {
      return;
    }
    const abilityContext: common.UIAbilityContext | undefined = AbilityContextHolder.context;
    if (abilityContext === undefined) {
      LOG.error('ability context is unavailable, cannot open external link');
      return;
    }
    const want: Want = { uri: trimmed };
    abilityContext.startAbility(want).then((): void => {
      LOG.info(`opened external link: ${trimmed}`);
    }).catch((error: BusinessError): void => {
      LOG.error(`open external link failed, code=${error.code}, message=${error.message}`);
    });
  }

  /** 删除笔记：移入回收站（.trash）。 */
  public async trashNote(path: string): Promise<boolean> {
    const manager: VaultManager | null = this.manager;
    if (manager === null || path.length === 0) {
      return false;
    }
    const trashPath: string = await manager.trashNote(this.currentVault, path);
    if (trashPath.length === 0) {
      return false;
    }
    if (this.selectedPath === path) {
      this.closeNote();
    }
    await this.refreshTree();
    return true;
  }

  /** 从回收站恢复笔记到仓库根目录。 */
  public async restoreNote(trashPath: string): Promise<boolean> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return false;
    }
    const restored: string = await manager.restoreNote(this.currentVault, trashPath);
    if (restored.length === 0) {
      return false;
    }
    await this.refreshTree();
    return true;
  }

  /** 清空回收站，返回删除的文件数。 */
  public async emptyTrash(): Promise<number> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return 0;
    }
    const removed: number = await manager.emptyTrash(this.currentVault);
    await this.refreshTree();
    return removed;
  }

  /** 列出回收站内的文件相对路径。 */
  public async listTrash(): Promise<string[]> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return [];
    }
    return manager.listTrash(this.currentVault);
  }

  /** 在仓库内新建文件夹。 */
  public async createFolder(path: string): Promise<boolean> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return false;
    }
    const created: boolean = await manager.createFolder(this.currentVault, path);
    if (created) {
      await this.refreshTree();
    }
    return created;
  }

  /**
   * 重命名笔记，并把指向旧名的双链重写为新名。
   * 仓库内链接按文件名解析，因此改名是唯一会影响既有链接的操作。
   */
  public async renameNote(path: string, newName: string): Promise<boolean> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    if (manager === null || context === null) {
      return false;
    }
    const trimmed: string = newName.trim();
    if (trimmed.length === 0) {
      return false;
    }
    const dir: string = VaultPath.dirname(path);
    const fileName: string = trimmed.endsWith('.md') ? trimmed : `${trimmed}.md`;
    const newPath: string = dir.length === 0 ? fileName : `${dir}/${fileName}`;
    if (newPath === path) {
      return false;
    }
    const renamed: boolean = await manager.renameNote(this.currentVault, path, newPath);
    if (!renamed) {
      return false;
    }
    const affected: string[] = await LinkRewriter.rewriteForRename(context, path, newPath,
      (source: string): Promise<string> => {
        return manager.readNote(this.currentVault, source);
      },
      async (source: string, content: string): Promise<void> => {
        await manager.writeNote(this.currentVault, source, content);
        await manager.refreshNote(this.currentVault, source);
      });
    let rewritten: string[] = affected;
    if (rewritten.length === 0) {
      // 链接索引可能尚未建立或已过期：退回按文件扫描，保证引用不被漏改。
      rewritten = await this.rewriteLinksByScan(path, newPath);
    }
    await this.reindexPaths(rewritten);
    await this.rewritePathRefs(path, newPath);
    if (this.selectedPath === path) {
      await this.openNote(newPath);
    }
    await this.refreshTree();
    return true;
  }

  /** 扫描仓库内全部笔记，把指向旧名的 wiki 链接改写为新名。 */
  private async rewriteLinksByScan(oldPath: string, newPath: string): Promise<string[]> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return [];
    }
    const oldName: string = VaultPath.basenameWithoutExt(oldPath);
    const newName: string = VaultPath.basenameWithoutExt(newPath);
    if (oldName.length === 0 || newName.length === 0 || oldName === newName) {
      return [];
    }
    const rewritten: string[] = [];
    for (const file of this.vaultFiles) {
      if (!VaultPath.isMarkdown(file) || file === oldPath) {
        continue;
      }
      const content: string = await manager.readNote(this.currentVault, file);
      if (content.length === 0) {
        continue;
      }
      const next: string = LinkRewriter.rewriteWikiLinks(content, oldName, newName);
      if (next === content) {
        continue;
      }
      await manager.writeNote(this.currentVault, file, next);
      await manager.refreshNote(this.currentVault, file);
      rewritten.push(file);
    }
    if (rewritten.length > 0) {
      LOG.info(`rewrote ${rewritten.length} reference(s) by scan: ${oldName} -> ${newName}`);
    }
    return rewritten;
  }

  /** 移动笔记到目标目录（目录为空表示根目录）。 */
  public async moveNote(path: string, destDir: string): Promise<boolean> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return false;
    }
    const name: string = VaultPath.basename(path);
    const target: string = destDir.length === 0 ? name : `${destDir}/${name}`;
    if (target === path) {
      return false;
    }
    const moved: boolean = await manager.moveNote(this.currentVault, path, target);
    if (!moved) {
      return false;
    }
    await this.rewritePathRefs(path, target);
    if (this.selectedPath === path) {
      await this.openNote(target);
    }
    await this.refreshTree();
    return true;
  }

  /** 导入图片附件到仓库 attachments 目录，返回附件相对路径。 */
  public async importAttachment(uri: string, extension: string): Promise<string> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return '';
    }
    const relative: string = await manager.importAttachment(this.currentVault, uri, extension);
    if (relative.length > 0) {
      await this.refreshTree();
    }
    return relative;
  }

  /** 解析图片目标为可加载的 file URI；未命中返回空串。 */
  public resolveAsset(target: string): string {
    const relative: string = AttachmentResolver.resolve(target, this.selectedPath, this.vaultFiles);
    if (relative.length === 0) {
      return '';
    }
    return `file://${this.currentVault.rootPath}/${relative}`;
  }

  /** 加载嵌入笔记的正文（只读渲染用）；支持 #章节 锚点。 */
  public async loadEmbed(target: string): Promise<string> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    if (manager === null || context === null) {
      return '';
    }
    let noteTarget: string = target.trim();
    let anchor: string = '';
    const hash: number = noteTarget.indexOf('#');
    if (hash >= 0) {
      anchor = noteTarget.substring(hash + 1).trim();
      noteTarget = noteTarget.substring(0, hash).trim();
    }
    if (noteTarget.length === 0) {
      return '';
    }
    const note = await NoteResolver.resolve(context, this.currentVault.id, noteTarget);
    if (note === null) {
      return '';
    }
    const content: string = await manager.readNote(this.currentVault, note.path);
    if (anchor.length === 0) {
      return content;
    }
    return this.extractSection(content, anchor);
  }

  /**
   * 抽取标题锚点对应的章节正文。
   *
   * 从目标标题行开始，收集到下一个同级或更高级标题为止（不含该标题）。
   *
   * @param content 笔记全文
   * @param anchor 标题文本
   * @returns 章节正文；找不到标题时返回全文
   */
  private extractSection(content: string, anchor: string): string {
    const lines: string[] = content.split('\n');
    let start: number = -1;
    let level: number = 0;
    let inFence: boolean = false;
    for (let index = 0; index < lines.length; index++) {
      const trimmed: string = lines[index].trim();
      if (trimmed.startsWith('```')) {
        // 围栏代码块内的 # 不是标题。
        inFence = !inFence;
        continue;
      }
      if (inFence) {
        continue;
      }
      const match: RegExpExecArray | null = /^(#{1,6})\s+(.*)$/.exec(lines[index]);
      if (match === null) {
        continue;
      }
      if (match[2].trim() === anchor || match[2].trim().toLowerCase() === anchor.toLowerCase()) {
        start = index + 1;
        level = match[1].length;
        break;
      }
    }
    if (start < 0) {
      return content;
    }
    const collected: string[] = [];
    let fence: boolean = false;
    for (let index = start; index < lines.length; index++) {
      const trimmed: string = lines[index].trim();
      if (trimmed.startsWith('```')) {
        fence = !fence;
        collected.push(lines[index]);
        continue;
      }
      if (!fence) {
        const match: RegExpExecArray | null = /^(#{1,6})\s+/.exec(lines[index]);
        if (match !== null && match[1].length <= level) {
          break;
        }
      }
      collected.push(lines[index]);
    }
    return collected.join('\n').trim();
  }

  /** 仓库内笔记标题列表（供 wiki 链接补全候选）。 */
  public noteTitles(): string[] {
    const titles: string[] = [];
    for (const file of this.vaultFiles) {
      if (!VaultPath.isMarkdown(file)) {
        continue;
      }
      const title: string = VaultPath.basenameWithoutExt(file);
      if (title.length > 0 && !titles.includes(title)) {
        titles.push(title);
      }
    }
    return titles;
  }

  /** 当前笔记的文件名（不含扩展名）。 */
  public selectedNoteName(): string {
    return VaultPath.basenameWithoutExt(this.selectedPath);
  }

  /** 仓库内的目录列表（移动目标选择用）。 */
  public listDirs(): string[] {
    const dirs: string[] = [];
    this.collectDirs(this.tree, dirs);
    return dirs;
  }

  /** 递归收集目录路径。 */
  private collectDirs(nodes: FileNode[], output: string[]): void {
    for (const node of nodes) {
      if (!node.isDir) {
        continue;
      }
      output.push(node.path);
      this.collectDirs(node.children, output);
    }
  }

  /** 保存图片二进制为仓库附件，返回相对路径。 */
  public async saveImageAttachment(data: ArrayBuffer, extension: string): Promise<string> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return '';
    }
    const relative: string = await manager.importImageBuffer(this.currentVault, data, extension);
    if (relative.length > 0) {
      await this.refreshTree();
    }
    return relative;
  }

  /** 快速闪念：把一段文字追加到当天的日记。 */
  public async appendQuickNote(text: string): Promise<boolean> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    if (manager === null || context === null || text.trim().length === 0) {
      return false;
    }
    const now: Date = new Date();
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    const name: string = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
    const path: string = `${name}.md`;
    const existing: NoteRow | null = await NoteDao.findByPath(context, this.currentVault.id, path);
    let content: string = '';
    if (existing !== null) {
      content = await manager.readNote(this.currentVault, path);
    } else {
      content = `# ${name}\n\n`;
    }
    let base: string = content;
    // 已有日记末行可能无换行符，直接追加会黏到上一行，先补齐。
    if (base.length > 0 && !base.endsWith('\n')) {
      base = `${base}\n`;
    }
    const next: string = `${base}- ${new Date().toTimeString().substring(0, 5)} ${text.trim()}\n`;
    await manager.writeNote(this.currentVault, path, next);
    await manager.refreshNote(this.currentVault, path);
    await this.refreshTree();
    return true;
  }

  /** 打开指定日期的日记（不存在则以该日期命名创建，支持日记模板）。 */
  public async openDailyNoteByDate(date: string): Promise<boolean> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    if (manager === null || context === null || date.length === 0) {
      return false;
    }
    const path: string = `${date}.md`;
    const existing: NoteRow | null = await NoteDao.findByPath(context, this.currentVault.id, path);
    let cursor: number = -1;
    if (existing === null) {
      const template: string = await this.findTemplate(['日记', 'daily', 'Daily', 'Journal']);
      let content: string = `# ${date}\n\n`;
      if (template.length > 0) {
        const raw: string = await manager.readTemplate(this.currentVault, template);
        const parsed: Date = new Date(`${date}T00:00:00`);
        const rendered: TemplateRenderResult = TemplateEngine.render(raw, date, parsed);
        content = rendered.content;
        cursor = rendered.cursorOffset;
      }
      await manager.writeNote(this.currentVault, path, content);
      await manager.refreshNote(this.currentVault, path);
      await this.refreshTree();
    }
    await this.openNote(path);
    if (cursor >= 0) {
      this.pendingCaret = cursor;
      this.startEdit();
    }
    return true;
  }

  /** 加载未链接提及（反链面板打开时按需加载）。 */
  public async loadUnlinked(): Promise<void> {
    if (this.selectedPath.length === 0) {
      this.unlinked = [];
      return;
    }
    this.unlinked = await this.unlinkedMentions(this.selectedPath);
  }

  /** 加载局部关系图谱（图谱页签打开时按需加载）。 */
  public async loadGraph(): Promise<void> {
    if (this.selectedPath.length === 0) {
      this.graph = new GraphData();
      return;
    }
    this.graph = await this.localGraph(this.selectedPath);
  }

  /** 打开分屏第二栏的笔记。 */
  public async openSecondary(path: string): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    const content: string = await manager.readNote(this.currentVault, path);
    this.secondaryPath = path;
    this.secondaryContent = content;
    this.secondaryDocument = MarkdownParser.parse(content);
  }

  /** 关闭分屏第二栏。 */
  public closeSecondary(): void {
    this.secondaryPath = '';
    this.secondaryContent = '';
    this.secondaryDocument = new MdDocument();
  }

  /** 重建文件树并刷新附件文件列表。 */
  private async refreshTree(): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    this.tree = await manager.buildTree(this.currentVault);
    this.refreshTreeItems();
    this.vaultFiles = await manager.listVaultFiles(this.currentVault);
    await this.refreshAllTags();
  }

  /** 刷新仓库内全部标签（供 # 标签补全使用）。 */
  private async refreshAllTags(): Promise<void> {
    const context: common.Context | null = this.context;
    if (context === null) {
      return;
    }
    try {
      const refs: TagRef[] = await TagDao.listAll(context, this.currentVault.id);
      const names: string[] = [];
      for (const ref of refs) {
        if (ref.tag.length > 0 && !names.includes(ref.tag)) {
          names.push(ref.tag);
        }
      }
      this.allTagNames = names;
    } catch (error) {
      LOG.error(`load tags failed, message=${error}`);
    }
  }

  /** 重建指定笔记的索引（改名后链接目标路径会变化）。 */
  private async reindexPaths(paths: string[]): Promise<void> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    if (manager === null || context === null) {
      return;
    }
    for (const path of paths) {
      const note: NoteRow | null = await NoteDao.findByPath(context, this.currentVault.id, path);
      if (note === null) {
        continue;
      }
      const content: string = await manager.readNote(this.currentVault, path);
      const document: MdDocument = MarkdownParser.parse(content);
      await IndexPipeline.indexNote(context, note, document);
    }
  }

  /** 关闭当前笔记。 */
  public closeNote(): void {
    this.selectedPath = '';
    this.noteTitle = '';
    this.noteContent = '';
    this.document = new MdDocument();
    this.editMode = false;
    this.draftBuffer = '';
    this.outline = [];
    this.backlinks = [];
    this.noteTags = [];
    this.noteProperties = [];
  }

  /** 进入编辑模式。 */
  public startEdit(): void {
    this.draftBuffer = this.noteContent;
    this.editMode = true;
  }

  /** 取消编辑。 */
  public cancelEdit(): void {
    this.editMode = false;
    this.draftBuffer = '';
  }

  /** 更新编辑草稿。 */
  public updateDraft(value: string): void {
    this.draftBuffer = value;
  }

  /** 保存编辑内容并重建索引。 */
  public async saveDraft(): Promise<void> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    if (manager === null || context === null) {
      return;
    }
    await manager.writeNote(this.currentVault, this.selectedPath, this.draftBuffer);
    this.noteContent = this.draftBuffer;
    this.document = MarkdownParser.parse(this.noteContent);
    this.editMode = false;
    this.draftBuffer = '';
    this.dataViewCache.clear();
    await this.refreshNoteMeta();
    await this.reindexCurrentNote();
    await this.refreshNoteInfo();
  }

  /** 切换信息面板页签。 */
  public setInfoTab(index: number): void {
    this.infoTabIndex = index;
  }

  /** 打开标签检索（M4 接入搜索页）。 */
  public onTagSelected(tag: string): void {
    LOG.info(`tag selected: ${tag}`);
  }

  /** 在当前仓库根目录新建空笔记并打开。 */
  public async createNote(): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    const now: Date = new Date();
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    const stamp: string = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}` +
      `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
    const title: string = `未命名-${stamp}`;
    // 存在默认模板时套用模板。
    const template: string = await this.findTemplate(['默认', 'default', 'Default', '笔记']);
    if (template.length > 0) {
      await this.createNoteWithTemplate(template, title);
      return;
    }
    const path: string = `${title}.md`;
    await manager.writeNote(this.currentVault, path, '');
    await manager.refreshNote(this.currentVault, path);
    await this.refreshTree();
    await this.openNote(path);
  }

  /** 列出仓库内的模板文件。 */
  public async listTemplates(): Promise<string[]> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return [];
    }
    return manager.listTemplates(this.currentVault);
  }

  /** 用模板创建笔记并打开（进入编辑态并把光标放到 {{cursor}} 位置）。 */
  public async createNoteWithTemplate(templatePath: string, title: string): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    const template: string = await manager.readTemplate(this.currentVault, templatePath);
    const rendered: TemplateRenderResult = TemplateEngine.render(template, title, new Date());
    const path: string = `${title}.md`;
    await manager.writeNote(this.currentVault, path, rendered.content);
    await manager.refreshNote(this.currentVault, path);
    await this.refreshTree();
    await this.openNote(path);
    // 模板光标占位符：进入编辑态并定位光标。
    this.pendingCaret = rendered.cursorOffset;
    this.startEdit();
  }

  /** 按文件名查找模板（Templates 目录内）。 */
  private async findTemplate(names: string[]): Promise<string> {
    const templates: string[] = await this.listTemplates();
    for (const name of names) {
      for (const template of templates) {
        if (VaultPath.basenameWithoutExt(template) === name) {
          return template;
        }
      }
    }
    return '';
  }

  /** 列出当前笔记的历史快照。 */
  public async listHistory(): Promise<HistorySnapshot[]> {
    const manager: VaultManager | null = this.manager;
    if (manager === null || this.selectedPath.length === 0) {
      return [];
    }
    return FileHistory.list(this.currentVault, this.selectedPath);
  }

  /** 读取历史快照内容。 */
  public async readHistory(name: string): Promise<string> {
    const manager: VaultManager | null = this.manager;
    if (manager === null || this.selectedPath.length === 0) {
      return '';
    }
    return FileHistory.read(this.currentVault, this.selectedPath, name);
  }

  /** 计算当前内容与历史快照的行级差异。 */
  public async diffHistory(name: string): Promise<DiffLine[]> {
    const snapshot: string = await this.readHistory(name);
    return FileHistory.diff(snapshot, this.noteContent);
  }

  /** 查询未链接提及：正文出现笔记标题但尚未建立双链的位置。 */
  public async unlinkedMentions(path: string): Promise<UnlinkedMention[]> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    const items: UnlinkedMention[] = [];
    if (manager === null || context === null || path.length === 0) {
      return items;
    }
    const title: string = VaultPath.basenameWithoutExt(path);
    if (title.length < 2) {
      return items;
    }
    const linked: Set<string> = new Set<string>();
    const backlinks: BacklinkItem[] = await LinkDao.backlinks(context, path);
    for (const item of backlinks) {
      linked.add(item.sourcePath);
    }
    for (const file of this.vaultFiles) {
      if (!VaultPath.isMarkdown(file) || file === path || linked.has(file)) {
        continue;
      }
      const content: string = await manager.readNote(this.currentVault, file);
      if (content.length === 0) {
        continue;
      }
      const index: number = content.indexOf(title);
      if (index < 0) {
        continue;
      }
      const item: UnlinkedMention = new UnlinkedMention();
      item.path = file;
      item.title = this.noteDisplayName(file);
      const start: number = Math.max(0, index - 20);
      const end: number = Math.min(content.length, index + title.length + 20);
      item.context = content.substring(start, end).replace(/\n/g, ' ');
      items.push(item);
    }
    return items;
  }

  /** 更新笔记属性（可视化属性编辑器），回写 frontmatter 并保存。 */
  public async updateProperty(key: string, value: string, listValue: string[]): Promise<void> {
    const properties: MdProperty[] = await this.currentProperties();
    let target: MdProperty | null = null;
    for (const property of properties) {
      if (property.key === key) {
        target = property;
        break;
      }
    }
    if (target === null) {
      // 属性不存在：按标量 / 列表新建一条。
      const created: MdProperty = new MdProperty();
      created.key = key;
      if (listValue.length > 0) {
        created.type = MdPropType.LIST;
        created.listValue = listValue;
      } else {
        created.type = MdPropType.STRING;
        created.value = value;
      }
      properties.push(created);
      await this.saveProperties(properties);
      return;
    }
    if (target.type === MdPropType.MAP) {
      // 嵌套 map 以原始块保留，不支持标量/列表方式改写，避免覆盖丢内容。
      return;
    }
    if (target.type === MdPropType.LIST || listValue.length > 0) {
      target.type = MdPropType.LIST;
      target.listValue = listValue;
      target.value = '';
    } else {
      target.value = value;
    }
    await this.saveProperties(properties);
  }

  /** 新增属性（可视化属性编辑器）。 */
  public async addProperty(key: string, type: MdPropType): Promise<void> {
    const trimmed: string = key.trim();
    if (trimmed.length === 0) {
      return;
    }
    const properties: MdProperty[] = await this.currentProperties();
    for (const property of properties) {
      if (property.key === trimmed) {
        return;
      }
    }
    const created: MdProperty = new MdProperty();
    created.key = trimmed;
    created.type = type;
    if (type === MdPropType.LIST) {
      created.listValue = [];
    }
    properties.push(created);
    await this.saveProperties(properties);
  }

  /** 删除属性（可视化属性编辑器），嵌套 map 块整块移除。 */
  public async removeProperty(key: string): Promise<void> {
    const properties: MdProperty[] = await this.currentProperties();
    const kept: MdProperty[] = [];
    for (const property of properties) {
      if (property.key !== key) {
        kept.push(property);
      }
    }
    await this.saveProperties(kept, [key]);
  }

  /** 读取当前笔记的属性集合（副本，可修改后回写）。 */
  private async currentProperties(): Promise<MdProperty[]> {
    const manager: VaultManager | null = this.manager;
    if (manager === null || this.selectedPath.length === 0) {
      return [];
    }
    const content: string = await manager.readNote(this.currentVault, this.selectedPath);
    const document: MdDocument = MarkdownParser.parse(content);
    return document.frontmatter.properties;
  }

  /** 把属性集合写回 frontmatter 并保存笔记。 */
  private async saveProperties(properties: MdProperty[], removedKeys: string[] = []): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null || this.selectedPath.length === 0) {
      return;
    }
    const content: string = await manager.readNote(this.currentVault, this.selectedPath);
    const next: string = FrontmatterSerializer.rebuild(content, properties, removedKeys);
    await manager.writeNote(this.currentVault, this.selectedPath, next);
    this.noteContent = next;
    this.document = MarkdownParser.parse(next);
    // 编辑模式下的草稿仍持有旧 frontmatter，需同步，否则下次落盘会回滚属性修改。
    if (this.editMode) {
      this.draftBuffer = next;
    }
    await manager.refreshNote(this.currentVault, this.selectedPath);
    await this.reindexCurrentNote();
    await this.refreshNoteInfo();
  }

  /** 把未链接提及转为双链：把正文中的首次出现替换为 [[标题]]。 */
  public async linkMention(path: string, title: string): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null || path.length === 0 || title.length === 0) {
      return;
    }
    const content: string = await manager.readNote(this.currentVault, path);
    const index: number = content.indexOf(title);
    if (index < 0) {
      return;
    }
    const next: string = content.substring(0, index) + `[[${title}]]` +
      content.substring(index + title.length);
    await manager.writeNote(this.currentVault, path, next);
    await manager.refreshNote(this.currentVault, path);
    if (path === this.selectedPath) {
      this.noteContent = next;
      this.document = MarkdownParser.parse(next);
      await this.reindexCurrentNote();
    }
    await this.refreshNoteInfo();
  }

  /** 回滚到历史快照，并重新加载笔记。 */
  public async rollbackHistory(name: string): Promise<boolean> {
    const manager: VaultManager | null = this.manager;
    if (manager === null || this.selectedPath.length === 0) {
      return false;
    }
    const ok: boolean = await FileHistory.rollback(this.currentVault, this.selectedPath, name);
    if (!ok) {
      return false;
    }
    // 回滚前丢弃未保存草稿，避免旧草稿在重新打开时覆盖刚回滚的内容。
    this.cancelEdit();
    await manager.refreshNote(this.currentVault, this.selectedPath);
    await this.openNote(this.selectedPath);
    return true;
  }

  /** 查询某月的日历数据（有日记标记 + 未完成任务角标）。 */
  public async calendarMonth(year: number, month: number): Promise<CalendarDay[]> {
    const manager: VaultManager | null = this.manager;
    const days: CalendarDay[] = [];
    if (manager === null) {
      return days;
    }
    const now: Date = new Date();
    const todayKey: string = VaultViewModel.dateKey(now.getFullYear(), now.getMonth() + 1,
      now.getDate());
    const total: number = new Date(year, month, 0).getDate();
    for (let day = 1; day <= total; day++) {
      const item: CalendarDay = new CalendarDay();
      item.day = day;
      item.date = VaultViewModel.dateKey(year, month, day);
      item.today = item.date === todayKey;
      const path: string = `${item.date}.md`;
      if (this.vaultFiles.includes(path)) {
        item.hasNote = true;
        const content: string = await manager.readNote(this.currentVault, path);
        item.openTasks = VaultViewModel.countOpenTasks(content);
      }
      days.push(item);
    }
    return days;
  }

  /** 日期键（YYYY-MM-DD）。 */
  public static dateKey(year: number, month: number, day: number): string {
    const monthText: string = month < 10 ? `0${month}` : `${month}`;
    const dayText: string = day < 10 ? `0${day}` : `${day}`;
    return `${year}-${monthText}-${dayText}`;
  }

  /** 统计未完成任务数量。 */
  private static countOpenTasks(content: string): number {
    let count: number = 0;
    const lines: string[] = content.split('\n');
    for (const line of lines) {
      if (/^\s*[-*+]\s+\[ \]\s/.test(line)) {
        count++;
      }
    }
    return count;
  }

  /**
   * 构建局部关系图谱：当前笔记及其 1~2 跳关联笔记。
   */
  public async localGraph(path: string): Promise<GraphData> {
    const context: common.Context | null = this.context;
    const graph: GraphData = new GraphData();
    if (context === null || path.length === 0) {
      return graph;
    }
    const depths: Map<string, number> = new Map<string, number>();
    const nodeMap: Map<string, GraphNode> = new Map<string, GraphNode>();
    const queue: string[] = [path];
    depths.set(path, 0);
    const root: GraphNode = new GraphNode();
    root.path = path;
    root.title = this.noteDisplayName(path);
    root.root = true;
    nodeMap.set(path, root);
    graph.nodes.push(root);

    const maxDepth: number = 2;
    while (queue.length > 0) {
      const current: string | undefined = queue.shift();
      if (current === undefined) {
        break;
      }
      const depth: number = depths.get(current) ?? 0;
      if (depth >= maxDepth) {
        continue;
      }
      const note: NoteRow | null = await NoteDao.findByPath(context, this.currentVault.id, current);
      if (note === null) {
        continue;
      }
      const outgoing: LinkRef[] = await LinkDao.outgoing(context, note.id);
      for (const link of outgoing) {
        if (link.targetPath.length === 0) {
          continue;
        }
        this.addGraphNode(graph, nodeMap, depths, queue, current, link.targetPath, depth + 1);
      }
      const backlinks: BacklinkItem[] = await LinkDao.backlinks(context, current);
      for (const item of backlinks) {
        this.addGraphNode(graph, nodeMap, depths, queue, item.sourcePath, current, depth + 1);
      }
    }
    return graph;
  }

  /** 登记图谱节点与连线。 */
  private addGraphNode(graph: GraphData, nodeMap: Map<string, GraphNode>,
    depths: Map<string, number>, queue: string[], from: string, to: string, depth: number): void {
    const edge: GraphEdge = new GraphEdge();
    edge.from = from;
    edge.to = to;
    graph.edges.push(edge);
    if (!nodeMap.has(to)) {
      const node: GraphNode = new GraphNode();
      node.path = to;
      node.title = this.noteDisplayName(to);
      node.depth = depth;
      nodeMap.set(to, node);
      graph.nodes.push(node);
    }
    if (!depths.has(to) && depth < 3) {
      depths.set(to, depth);
      queue.push(to);
    }
  }

  /** 新建空仓库；首个仓库（引导页新建）预填示例笔记。 */
  public async createVault(name: string): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    this.busy = true;
    try {
      const firstVault: boolean = this.vaults.length === 0;
      const vault: VaultInfo = firstVault
        ? await manager.createDemoVault(name)
        : await manager.createVault(name);
      await this.refreshVaults();
      await this.selectVault(vault);
    } finally {
      this.busy = false;
    }
  }

  /** 导入 zip 仓库。 */
  public async importVault(uri: string, name: string): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    this.busy = true;
    try {
      const vault: VaultInfo = await manager.importVault(uri, name);
      await this.refreshVaults();
      await this.selectVault(vault);
    } finally {
      this.busy = false;
    }
  }

  /** 导出指定仓库为 zip。 */
  public async exportVault(vault: VaultInfo, uri: string): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    this.busy = true;
    try {
      await manager.exportVault(vault, uri);
    } finally {
      this.busy = false;
    }
  }

  /** 删除仓库（含磁盘目录与索引记录）。 */
  public async deleteVault(vault: VaultInfo): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    this.busy = true;
    try {
      await manager.deleteVault(vault);
      await this.refreshVaults();
      if (this.currentVault.id === vault.id) {
        this.closeNote();
        this.tree = [];
        this.treeItems = [];
        if (this.vaults.length > 0) {
          await this.selectVault(this.vaults[0]);
        } else {
          this.currentVault = new VaultInfo();
        }
      }
    } finally {
      this.busy = false;
    }
  }

  /** 重建整个仓库的索引。 */
  public async rescanVault(): Promise<void> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    if (manager === null || context === null) {
      return;
    }
    await manager.scanVault(this.currentVault);
    const notes: NoteRow[] = await NoteDao.listByVault(context, this.currentVault.id);
    for (const note of notes) {
      const content: string = await manager.readNote(this.currentVault, note.path);
      const document: MdDocument = MarkdownParser.parse(content);
      await IndexPipeline.indexNote(context, note, document);
    }
    await this.refreshTree();
    await this.refreshNoteInfo();
  }

  private async refreshNoteMeta(): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    await manager.refreshNote(this.currentVault, this.selectedPath);
  }

  private async reindexCurrentNote(): Promise<void> {
    const context: common.Context | null = this.context;
    if (context === null || this.selectedPath.length === 0) {
      return;
    }
    const note: NoteRow | null = await NoteDao.findByPath(context, this.currentVault.id,
      this.selectedPath);
    if (note === null) {
      return;
    }
    await IndexPipeline.indexNote(context, note, this.document);
  }

  private async refreshNoteInfo(): Promise<void> {
    const context: common.Context | null = this.context;
    if (context === null || this.selectedPath.length === 0) {
      return;
    }
    const note: NoteRow | null = await NoteDao.findByPath(context, this.currentVault.id,
      this.selectedPath);
    if (note === null) {
      return;
    }
    this.outline = await BlockDao.outline(context, note.id);
    this.backlinks = await LinkDao.backlinks(context, this.selectedPath);
    this.noteTags = await TagDao.tagsOfNote(context, note.id);
    // 属性以「文件解析结果」为准：与写回链路同源，避免面板顺序与列表值漂移。
    this.noteProperties = this.document.frontmatter.properties;
  }

  private refreshTreeItems(): void {
    const items: FlatFileNode[] = [];
    this.flatten(this.tree, 0, items);
    this.treeItems = items;
  }

  private flatten(nodes: FileNode[], depth: number, output: FlatFileNode[]): void {
    for (const node of nodes) {
      const flat: FlatFileNode = new FlatFileNode();
      flat.node = node;
      flat.depth = depth;
      flat.expanded = this.expandedPaths.indexOf(node.path) >= 0;
      output.push(flat);
      if (node.isDir && flat.expanded) {
        this.flatten(node.children, depth + 1, output);
      }
    }
  }
}
