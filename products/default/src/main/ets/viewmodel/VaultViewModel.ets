import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { BacklinkItem, DataViewTask, FileNode, FlatFileNode, MdBlock, MdBlockType, MdDocument,
  MdListItem, MdProperty, NoteRow, OutlineEntry, VaultInfo } from '@ohos/domain';
import { Logger } from '@ohos/common';
import { DataViewQuery, MarkdownParser, TaskMetadata } from '@ohos/markdown';
import { BlockDao, IndexPipeline, LinkDao, NoteDao, NoteResolver, PropDao, TagDao, VaultManager,
  VaultPath } from '@ohos/vault';

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
  /** 信息面板。 */
  @Trace infoTabIndex: number = 0;
  @Trace outline: OutlineEntry[] = [];
  @Trace backlinks: BacklinkItem[] = [];
  @Trace noteTags: string[] = [];
  @Trace noteProperties: MdProperty[] = [];
  /** 正文字号。 */
  @Trace fontSize: number = 16;

  private manager: VaultManager | null = null;
  private context: common.Context | null = null;
  private uiContext: UIContext | null = null;
  private tree: FileNode[] = [];
  private expandedPaths: string[] = [];
  private noteHistory: string[] = [];
  /** Dataview 查询结果缓存（key: 查询文本|当前笔记路径）。 */
  private dataViewCache: Map<string, DataViewTask[]> = new Map();

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
    this.tree = await manager.buildTree(vault);
    this.refreshTreeItems();
    await this.ensureIndexed(vault);
    await this.loadRecentNotes();
  }

  /** 为尚未建立索引的笔记补建索引。 */
  private async ensureIndexed(vault: VaultInfo): Promise<void> {
    const context: common.Context | null = this.context;
    const manager: VaultManager | null = this.manager;
    if (context === null || manager === null) {
      return;
    }
    const notes: NoteRow[] = await NoteDao.listByVault(context, vault.id);
    for (const note of notes) {
      const count: number = await BlockDao.countOfNote(context, note.id);
      if (count > 0) {
        continue;
      }
      const content: string = await manager.readNote(vault, note.path);
      const document: MdDocument = MarkdownParser.parse(content);
      await IndexPipeline.indexNote(context, note, document);
    }
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

  /** 切换任务勾选状态：回写源文本并重建索引。 */
  public async toggleTask(rawLine: string, checked: boolean): Promise<void> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    if (manager === null || context === null || this.selectedPath.length === 0) {
      return;
    }
    const nextLine: string = TaskMetadata.toggle(rawLine, checked);
    if (nextLine === rawLine) {
      return;
    }
    const nextContent: string = this.noteContent.replace(rawLine, nextLine);
    await manager.writeNote(this.currentVault, this.selectedPath, nextContent);
    this.noteContent = nextContent;
    this.document = MarkdownParser.parse(nextContent);
    this.dataViewCache.clear();
    await manager.refreshNote(this.currentVault, this.selectedPath);
    await this.reindexCurrentNote();
    await this.refreshNoteInfo();
  }

  /** 执行 Dataview TASK 查询：聚合当前仓库全部笔记的任务（带缓存）。 */
  public async runDataViewQuery(query: string): Promise<DataViewTask[]> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    if (manager === null || context === null) {
      return [];
    }
    const cacheKey: string = `${query}|${this.selectedPath}`;
    const cached: DataViewTask[] | undefined = this.dataViewCache.get(cacheKey);
    if (cached !== undefined) {
      return cached;
    }
    const dvQuery: DataViewQuery = DataViewQuery.parse(query);
    if (!dvQuery.isTaskQuery()) {
      return [];
    }
    const tasks: DataViewTask[] = [];
    const rows: NoteRow[] = await NoteDao.listByVault(context, this.currentVault.id);
    for (const row of rows) {
      if (row.ext !== 'md' || (dvQuery.excludeCurrent && row.path === this.selectedPath)) {
        continue;
      }
      const content: string = await manager.readNote(this.currentVault, row.path);
      const parsed: MdDocument = MarkdownParser.parse(content);
      this.collectTasks(parsed.blocks, dvQuery, row.path, tasks);
    }
    this.dataViewCache.set(cacheKey, tasks);
    return tasks;
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
      if (item.isTask && query.matches(item.rawLine, item.checked)) {
        const task: DataViewTask = new DataViewTask();
        task.path = path;
        task.fileName = this.noteDisplayName(path);
        task.item = item;
        out.push(task);
      }
      this.collectTaskItems(item.children, query, path, out);
    }
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
      await this.toggleTask(rawLine, checked);
      return;
    }
    const content: string = await manager.readNote(this.currentVault, task.path);
    const nextContent: string = content.replace(rawLine, nextLine);
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

  /** 打开今天的日记（不存在则以日期为名新建）。 */
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
    if (existing === null) {
      await manager.writeNote(this.currentVault, path, `# ${name}\n\n`);
      await manager.refreshNote(this.currentVault, path);
      this.tree = await manager.buildTree(this.currentVault);
      this.refreshTreeItems();
    }
    await this.openNote(path);
    return true;
  }

  private async openNoteInternal(path: string, recordHistory: boolean): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
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
    const document: MdDocument = MarkdownParser.parse(content);
    const title: string = document.title.length > 0 ? document.title : VaultPath.basename(path);
    this.applyDocument(path, content, document, title);
    await this.writePref('lastNotePath', path);
    await this.recordRecent(path);
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

  /** 处理正文中的链接点击：wiki 链接在仓库内跳转。 */
  public async openLink(target: string, kind: string): Promise<void> {
    if (kind === 'url') {
      LOG.info(`external link ignored: ${target}`);
      return;
    }
    const context: common.Context | null = this.context;
    if (context === null) {
      return;
    }
    const note = await NoteResolver.resolve(context, this.currentVault.id, target);
    if (note === null) {
      LOG.info(`unresolved wiki link: ${target}`);
      return;
    }
    await this.openNote(note.path);
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
    const path: string = `未命名-${stamp}.md`;
    await manager.writeNote(this.currentVault, path, '');
    await manager.refreshNote(this.currentVault, path);
    this.tree = await manager.buildTree(this.currentVault);
    this.refreshTreeItems();
    await this.openNote(path);
  }

  /** 新建空仓库。 */
  public async createVault(name: string): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    this.busy = true;
    try {
      const vault: VaultInfo = await manager.createVault(name);
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
    this.tree = await manager.buildTree(this.currentVault);
    this.refreshTreeItems();
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
    this.noteProperties = await PropDao.ofNote(context, note.id);
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
