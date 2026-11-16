import { common, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { BacklinkItem, CalendarDay, DataViewEntry, DataViewResult, DataViewTask, FileNode,
  FlatFileNode, GraphData, GraphEdge, GraphNode, LinkRef, MdBlock, MdBlockType, MdDocument,
  MdFrontmatter, MdListItem, MdPropType, MdProperty, NoteRow, OutlineEntry, TagRef,
  UnlinkedMention, VaultInfo } from '@ohos/domain';
import { Logger } from '@ohos/common';
import { DataViewQuery, FrontmatterSerializer, MarkdownParser, TaskMetadata } from '@ohos/markdown';
import { AttachmentResolver, BlockDao, DbHelper, DiffLine, FileHistory, FileStatInfo, HistorySnapshot,
  IndexPipeline, LinkDao, LinkRewriter, NoteDao, NoteResolver, PropDao, TagDao, TemplateEngine,
  TemplateRenderResult, TrashFolderResult, VaultBackupInfo, VaultManager, VaultPath } from '@ohos/vault';
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

/** 根级目录摘要（首页文件页展示）。 */
export class RootFolderSummary {
  name: string = '';
  path: string = '';
  noteCount: number = 0;
}

/**
 * 仓库视图模型：负责仓库列表、文件树、笔记读取编辑、索引与信息面板。
 */
@ObservedV2
export class VaultViewModel {
  @Trace vaults: VaultInfo[] = [];
  @Trace currentVault: VaultInfo = new VaultInfo();
  @Trace treeItems: FlatFileNode[] = [];
  /** 全仓库笔记 path → 最后修改时间（秒）映射（首页笔记列表排序用）。 */
  @Trace mtimeByPath: Map<string, number> = new Map<string, number>();
  /** 根级目录摘要（首页文件页展示）。 */
  @Trace rootFolders: RootFolderSummary[] = [];
  @Trace selectedPath: string = '';
  /** 当前打开的外部文件 URI（非空且 selectedPath 为空时表示外部只读预览态）。 */
  @Trace externalUri: string = '';
  /** 外部打开的文件名（含扩展名）。 */
  @Trace externalFileName: string = '';
  @Trace noteTitle: string = '';

  /** 是否处于外部文件只读预览模式。 */
  public get isExternalMode(): boolean {
    return this.externalUri.length > 0 && this.selectedPath.length === 0;
  }
  @Trace noteContent: string = '';
  @Trace document: MdDocument = new MdDocument();
  @Trace busy: boolean = false;
  /** 是否有可返回的历史笔记（供底部迷你栏按钮禁用态）。 */
  @Trace canGoBack: boolean = false;
  /** 最近访问的笔记（当前仓库）。 */
  @Trace recentNotes: RecentNoteItem[] = [];
  /** 当前仓库的书签置顶笔记相对路径列表。 */
  @Trace bookmarks: string[] = [];
  /** 当前仓库的本地 zip 备份快照列表。 */
  @Trace backups: VaultBackupInfo[] = [];

  /** 编辑态。 */
  @Trace editMode: boolean = false;
  /** 编辑器缓冲区（非响应式，避免输入时重建 TextArea 造成光标跳动）。 */
  draftBuffer: string = '';
  /** 待应用的光标位置（模板渲染后的 {{cursor}} 位置，-1 表示无）。 */
  @Trace pendingCaret: number = -1;
  /** 新建文件夹对话框预填路径前缀（在目录下新建子文件夹时使用）。 */
  pendingFolderPrefix: string = '';
  /** 信息面板。 */
  @Trace infoTabIndex: number = 0;
  @Trace outline: OutlineEntry[] = [];
  @Trace backlinks: BacklinkItem[] = [];
  @Trace noteTags: string[] = [];
  @Trace noteProperties: MdProperty[] = [];
  /** 正文字号。 */
  @Trace fontSize: number = 16;
  @Trace themeMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;

  /** 反向链接面板增强：未链接提及。 */
  @Trace unlinked: UnlinkedMention[] = [];
  /** 仓库内全部标签（# 标签补全候选）。 */
  @Trace allTagNames: string[] = [];
  /** 局部关系图谱数据（信息面板页签用）。 */
  @Trace graph: GraphData = new GraphData();
  /** 整库关系图谱数据（首页图谱页用）：仓库内全部笔记为节点、链接为边。 */
  @Trace vaultGraph: GraphData = new GraphData();
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
  @Trace vaultFiles: string[] = [];

  /** 锚点跳转回调：由页面注入（负责滚动到目标标题块）。 */
  public onScrollToHeading: (heading: string) => void = (heading: string): void => {};
  /** 自动创建笔记回调：由页面注入（用于提示用户）。 */
  public onNoteCreated: (path: string) => void = (path: string): void => {};
  /** 在光标处插入文本回调：由编辑器注入（手写图片插入用；atEnd 表示追加到文末）。 */
  public onInsertTextAtCaret: (text: string, atEnd: boolean) => void =
    (text: string, atEnd: boolean): void => {};

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

  /** 恢复上次会话的仓库与笔记（首页从工作台返回时刷新状态）。 */
  public async restoreSession(): Promise<void> {
    if (this.vaults.length === 0) {
      return;
    }
    await this.restoreLastSession();
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

  /** 更新主题模式（-1 跟随系统 / 0 深色 / 1 浅色）并持久化。 */
  public async setThemeMode(mode: number): Promise<void> {
    this.themeMode = mode;
    this.applyThemeMode(mode);
    await this.writePref('themeMode', mode);
  }

  private applyThemeMode(mode: number): void {
    const context: common.Context | null = this.context;
    if (context === null) {
      return;
    }
    try {
      if (mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else if (mode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
    } catch (error) {
      LOG.warn('apply theme mode failed');
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
      const theme: preferences.ValueType = await store.get('themeMode',
        ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      if (typeof theme === 'number') {
        this.themeMode = theme;
        this.applyThemeMode(theme);
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
    await this.loadBookmarks();
    this.refreshBackups();
    await this.autoBackupIfNeeded();
    // 整库图谱随仓库切换刷新（首页图谱页数据源）。
    await this.loadVaultGraph();
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
    // FTS 自愈：历史版本存在 FTS 行缺失（ftsReady 误判 false 期间未写入），
    // 对缺失行强制重建，保证全文检索可命中全部笔记。
    const ftsReady: boolean = DbHelper.isFtsReady();
    const ftsIds: Set<number> = ftsReady ? await NoteDao.listFtsRowIds(context) : new Set<number>();
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
      if (blockCount === 0 || stat.mtime !== row.mtime || stat.size !== row.size ||
        (ftsReady && !ftsIds.has(row.id))) {
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
      let tagFilterPaths: Set<string> | null = null;
      if (dvQuery.fromTag.length > 0) {
        const matchedPaths: string[] = await TagDao.notesByTag(
          context, this.currentVault.id, dvQuery.fromTag);
        if (matchedPaths.length > 0) {
          tagFilterPaths = new Set<string>(matchedPaths);
        }
      }
      for (const row of rows) {
        if (row.ext !== 'md' || (dvQuery.excludeCurrent && row.path === this.selectedPath)) {
          continue;
        }
        if (tagFilterPaths !== null && !tagFilterPaths.has(row.path)) {
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

  /**
   * 聚合 live TABLE/LIST 查询的笔记条目（按路径升序）。
   * 优先使用 RDB 中的 tag / prop 批量索引完成过滤与属性提取，仅在查询含正文关键词或未建索引时回退读文件。
   */
  private async collectEntries(query: DataViewQuery): Promise<DataViewEntry[]> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    const entries: DataViewEntry[] = [];
    if (manager === null || context === null) {
      return entries;
    }
    const rows: NoteRow[] = await NoteDao.listByVault(context, this.currentVault.id);
    const tagMap: Map<number, string[]> = await TagDao.tagsByVault(context, this.currentVault.id);
    const propMap: Map<number, MdProperty[]> = await PropDao.propsByVault(context, this.currentVault.id);
    const useRdbOnly: boolean = query.containsText.length === 0 &&
      (tagMap.size > 0 || propMap.size > 0);
    for (const row of rows) {
      if (row.ext !== 'md') {
        continue;
      }
      if (query.excludeCurrent && row.path === this.selectedPath) {
        continue;
      }
      if (query.fromFolder.length > 0 &&
        !(row.path === query.fromFolder || row.path.startsWith(`${query.fromFolder}/`))) {
        continue;
      }
      if (useRdbOnly && (tagMap.has(row.id) || propMap.has(row.id) ||
        (query.fromTag.length === 0 && query.requiredTags.length === 0))) {
        const noteTags: string[] = tagMap.get(row.id) ?? [];
        if (query.fromTag.length > 0 && !noteTags.includes(query.fromTag)) {
          continue;
        }
        let allTagsMatched: boolean = true;
        for (const reqTag of query.requiredTags) {
          if (!noteTags.includes(reqTag)) {
            allTagsMatched = false;
            break;
          }
        }
        if (!allTagsMatched) {
          continue;
        }
        const fm: MdFrontmatter = new MdFrontmatter();
        fm.tags = noteTags;
        fm.properties = propMap.get(row.id) ?? [];
        const entry: DataViewEntry = new DataViewEntry();
        entry.path = row.path;
        entry.fileName = this.noteDisplayName(row.path);
        entry.cells = this.extractEntryCells(query, fm, entry.fileName);
        entries.push(entry);
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
    const bmIndex: number = this.bookmarks.indexOf(oldPath);
    if (bmIndex >= 0) {
      const nextBookmarks: string[] = this.bookmarks.slice();
      nextBookmarks[bmIndex] = newPath;
      await this.saveBookmarks(nextBookmarks);
    }
  }

  /** 移除被删除笔记或目录下的导航历史、书签与最近访问残留记录。 */
  private async removePathRefs(paths: Set<string>, dirPrefix: string = ''): Promise<void> {
    const matches = (target: string): boolean => {
      return paths.has(target) || (dirPrefix.length > 0 && target.startsWith(dirPrefix));
    };
    const nextHistory: string[] = this.noteHistory.filter((item: string): boolean => !matches(item));
    if (nextHistory.length !== this.noteHistory.length) {
      this.noteHistory = nextHistory;
      this.canGoBack = nextHistory.length > 0;
    }
    const nextBookmarks: string[] = this.bookmarks.filter((item: string): boolean => !matches(item));
    if (nextBookmarks.length !== this.bookmarks.length) {
      await this.saveBookmarks(nextBookmarks);
    }
    if (this.context === null) {
      return;
    }
    const entries: RecentNoteEntry[] = await this.readRecentLog();
    const kept: RecentNoteEntry[] = [];
    let changed: boolean = false;
    for (const entry of entries) {
      if (entry.vaultId === this.currentVault.id && matches(entry.path)) {
        changed = true;
        continue;
      }
      kept.push(entry);
    }
    if (changed) {
      await this.writePref(RECENT_LOG_KEY, JSON.stringify(kept));
      await this.loadRecentNotes();
    }
  }

  /** 判断指定笔记是否已加入书签。 */
  public isBookmarked(path: string): boolean {
    return path.length > 0 && this.bookmarks.includes(path);
  }

  /** 切换指定笔记的书签状态（返回切换后是否已加书签）。 */
  public async toggleBookmark(path: string): Promise<boolean> {
    if (path.length === 0) {
      return false;
    }
    const next: string[] = [];
    let removed: boolean = false;
    for (const item of this.bookmarks) {
      if (item === path) {
        removed = true;
      } else {
        next.push(item);
      }
    }
    if (!removed) {
      next.unshift(path);
    }
    await this.saveBookmarks(next);
    return !removed;
  }

  private async loadBookmarks(): Promise<void> {
    const context: common.Context | null = this.context;
    if (context === null || this.currentVault.id < 0) {
      this.bookmarks = [];
      return;
    }
    const raw: string = await this.readStringPref(
      context, `bookmarks_${this.currentVault.id}`, '[]');
    const loaded: string[] = [];
    try {
      const arr: string[] = JSON.parse(raw) as string[];
      if (Array.isArray(arr)) {
        for (const el of arr) {
          if (el.length > 0 && this.vaultFiles.includes(el) && !loaded.includes(el)) {
            loaded.push(el);
          }
        }
      }
    } catch (error) {
      LOG.warn('parse bookmarks failed');
    }
    this.bookmarks = loaded;
  }

  private async saveBookmarks(list: string[]): Promise<void> {
    this.bookmarks = list.slice();
    if (this.currentVault.id >= 0) {
      await this.writePref(`bookmarks_${this.currentVault.id}`, JSON.stringify(this.bookmarks));
    }
  }

  /** 刷新当前仓库的本地备份快照列表。 */
  public refreshBackups(): void {
    const manager: VaultManager | null = this.manager;
    if (manager === null || this.currentVault.id < 0) {
      this.backups = [];
      return;
    }
    this.backups = manager.listBackups(this.currentVault);
  }

  /** 立即创建一份当前仓库的本地备份快照（最多保留 5 份）。 */
  public async createBackup(): Promise<string> {
    const manager: VaultManager | null = this.manager;
    if (manager === null || this.currentVault.id < 0) {
      return '';
    }
    try {
      const name: string = await manager.createBackup(this.currentVault, 5);
      this.refreshBackups();
      return name;
    } catch (error) {
      LOG.warn('create backup failed');
      return '';
    }
  }

  /** 从指定的本地备份快照恢复当前仓库。 */
  public async restoreBackup(backupName: string): Promise<boolean> {
    const manager: VaultManager | null = this.manager;
    if (manager === null || this.currentVault.id < 0 || backupName.length === 0) {
      return false;
    }
    const ok: boolean = await manager.restoreBackup(this.currentVault, backupName);
    if (ok) {
      this.closeNote();
      await this.rescanVault();
      this.refreshBackups();
    }
    return ok;
  }

  /** 每日自动快照备份：距上次备份超过 24 小时且仓库非空时静默生成一份快照。 */
  private async autoBackupIfNeeded(): Promise<void> {
    if (this.vaultFiles.length === 0) {
      return;
    }
    const dayMs: number = 24 * 60 * 60 * 1000;
    if (this.backups.length === 0 || Date.now() - this.backups[0].createdAt >= dayMs) {
      await this.createBackup();
    }
  }

  /** 打开今天的日记（默认 `日记/YYYY-MM/YYYY-MM-DD.md`）；不存在时先用模板或默认标题创建。 */
  public async openDailyNote(): Promise<boolean> {
    const now: Date = new Date();
    const todayKey: string = VaultViewModel.dateKey(now.getFullYear(), now.getMonth() + 1, now.getDate());
    return this.openDailyNoteByDate(todayKey);
  }

  private findExistingDailyPathFromTree(dateKey: string): string {
    const candidates: string[] = VaultPath.dailyNoteCandidates(dateKey);
    for (const candidate of candidates) {
      if (this.vaultFiles.includes(candidate)) {
        return candidate;
      }
    }
    return '';
  }

  private async findExistingDailyPath(context: common.Context, dateKey: string): Promise<string> {
    const candidates: string[] = VaultPath.dailyNoteCandidates(dateKey);
    for (const candidate of candidates) {
      const existing: NoteRow | null = await NoteDao.findByPath(context, this.currentVault.id, candidate);
      if (existing !== null || this.vaultFiles.includes(candidate)) {
        return candidate;
      }
    }
    return '';
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

  /**
   * 从外部文件 URI（文件管理器或其他应用的打开方式）直接只读预览 Markdown，
   * 不自动写入任何仓库，避免污染 WebDAV 远端库。
   */
  public openExternalUri(uri: string): boolean {
    const trimmed: string = uri.trim();
    if (trimmed.length === 0) {
      return false;
    }
    this.openToken++;
    const content: string | null = VaultManager.readUriText(trimmed);
    if (content === null) {
      return false;
    }
    const fileName: string = VaultManager.extractUriFileName(trimmed);
    const baseName: string = fileName.replace(/\.(md|markdown)$/i, '').trim();
    const document: MdDocument = MarkdownParser.parse(content);
    const title: string = document.title.length > 0 ? document.title :
      (baseName.length > 0 ? baseName : fileName);
    this.applyExternalDocument(trimmed, fileName, content, document, title);
    return true;
  }

  /** 将当前外部只读预览的 Markdown 导入当前仓库（同名时自动追加时间戳防覆盖），返回新笔记路径。 */
  public async importExternalToVault(): Promise<string> {
    const manager: VaultManager | null = this.manager;
    if (!this.isExternalMode || manager === null || this.currentVault.rootPath.length === 0) {
      return '';
    }
    const baseRaw: string = this.externalFileName.replace(/\.(md|markdown)$/i, '').trim();
    let safeTitle: string = baseRaw.replace(/[\\/:*?"<>|#\[\]]/g, '').trim();
    if (safeTitle.length === 0) {
      safeTitle = '外部笔记';
    }
    let path: string = `${safeTitle}.md`;
    if (this.vaultFiles.includes(path)) {
      const now: Date = new Date();
      const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
      const stamp: string = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}` +
        `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
      path = `${safeTitle}-${stamp}.md`;
    }
    await manager.writeNote(this.currentVault, path, this.noteContent);
    await manager.refreshNote(this.currentVault, path);
    await this.refreshTree();
    await this.openNote(path);
    return path;
  }

  /** 以过渡动画应用新文档，避免正文生硬切换。 */
  private applyDocument(path: string, content: string, document: MdDocument, title: string): void {
    const ui: UIContext | null = this.uiContext;
    if (ui === null) {
      this.externalUri = '';
      this.externalFileName = '';
      this.selectedPath = path;
      this.noteTitle = title;
      this.noteContent = content;
      this.document = document;
      this.editMode = false;
      this.draftBuffer = '';
      return;
    }
    ui.animateTo({ duration: 240, curve: Curve.Friction }, (): void => {
      this.externalUri = '';
      this.externalFileName = '';
      this.selectedPath = path;
      this.noteTitle = title;
      this.noteContent = content;
      this.document = document;
      this.editMode = false;
      this.draftBuffer = '';
    });
  }

  /** 应用外部文件只读预览文档（不入库、不记录最近访问，仅在内存提取大纲/标签/属性）。 */
  private applyExternalDocument(uri: string, fileName: string, content: string,
    document: MdDocument, title: string): void {
    const outline: OutlineEntry[] = IndexPipeline.collectOutline(document);
    const tags: string[] = IndexPipeline.collectTags(document);
    const properties: MdProperty[] = document.frontmatter.properties;
    const assignState = (): void => {
      this.selectedPath = '';
      this.externalUri = uri;
      this.externalFileName = fileName;
      this.noteTitle = title;
      this.noteContent = content;
      this.document = document;
      this.editMode = false;
      this.draftBuffer = '';
      this.outline = outline;
      this.backlinks = [];
      this.unlinked = [];
      this.graph = new GraphData();
      this.noteTags = tags;
      this.noteProperties = properties;
    };
    const ui: UIContext | null = this.uiContext;
    if (ui === null) {
      assignState();
      return;
    }
    ui.animateTo({ duration: 240, curve: Curve.Friction }, assignState);
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
    if (this.isExternalMode) {
      // 外部只读预览模式下不跳转也不自动在仓库新建双链笔记。
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

  /** 删除笔记：移入回收站（.trash），并清理导航历史/书签/最近访问记录。 */
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
    if (this.secondaryPath === path) {
      this.closeSecondary();
    }
    await this.removePathRefs(new Set<string>([path]));
    await this.refreshTree();
    return true;
  }

  /** 删除文件夹：目录内文件移入 .trash 回收站并移除文件夹。 */
  public async trashFolder(dirPath: string): Promise<boolean> {
    const manager: VaultManager | null = this.manager;
    const normalized: string = VaultPath.normalize(dirPath).replace(/\/+$/, '');
    if (manager === null || normalized.length === 0) {
      return false;
    }
    const result: TrashFolderResult = await manager.trashFolder(this.currentVault, normalized);
    if (!result.ok) {
      return false;
    }
    const prefix: string = `${normalized}/`;
    if (this.selectedPath === normalized || this.selectedPath.startsWith(prefix)) {
      this.closeNote();
    }
    if (this.secondaryPath === normalized || this.secondaryPath.startsWith(prefix)) {
      this.closeSecondary();
    }
    this.expandedPaths = this.expandedPaths.filter((p: string): boolean => {
      return p !== normalized && !p.startsWith(prefix);
    });
    await this.removePathRefs(new Set<string>(result.files), prefix);
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
    if (this.selectedPath.length === 0) {
      if (target.startsWith('http://') || target.startsWith('https://') ||
        target.startsWith('file://')) {
        return target;
      }
      return '';
    }
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
    const name: string = VaultViewModel.dateKey(now.getFullYear(), now.getMonth() + 1, now.getDate());
    const existingPath: string = await this.findExistingDailyPath(context, name);
    const path: string = existingPath.length > 0 ? existingPath : VaultPath.dailyNotePath(name);
    let content: string = '';
    if (existingPath.length > 0) {
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

  /** 打开指定日期的日记（默认 `日记/YYYY-MM/YYYY-MM-DD.md`，兼容历史根目录日记，不存在则创建）。 */
  public async openDailyNoteByDate(date: string): Promise<boolean> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    if (manager === null || context === null || date.length === 0) {
      return false;
    }
    const existingPath: string = await this.findExistingDailyPath(context, date);
    const path: string = existingPath.length > 0 ? existingPath : VaultPath.dailyNotePath(date);
    let cursor: number = -1;
    if (existingPath.length === 0) {
      const template: string = await this.findTemplate(['日记', 'daily', 'Daily', 'Journal']);
      let content: string = `# ${date}\n\n`;
      if (template.length > 0) {
        const raw: string = await manager.readTemplate(this.currentVault, template);
        const now: Date = new Date();
        const todayKey: string = VaultViewModel.dateKey(now.getFullYear(), now.getMonth() + 1, now.getDate());
        const targetDate: Date = date === todayKey ? now : new Date(`${date}T00:00:00`);
        const rendered: TemplateRenderResult = TemplateEngine.render(raw, date, targetDate);
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

  /** 加载整库关系图谱（首页图谱页）。 */
  public async loadVaultGraph(): Promise<void> {
    this.vaultGraph = await this.buildVaultGraph();
  }

  /**
   * 构建整库关系图谱：仓库内全部笔记为节点，笔记间链接为边。
   * 孤立笔记（无任何链接）也作为节点呈现；同一对笔记间多条链接只画一条边。
   */
  private async buildVaultGraph(): Promise<GraphData> {
    const context: common.Context | null = this.context;
    const graph: GraphData = new GraphData();
    if (context === null) {
      return graph;
    }
    const notes: NoteRow[] = await NoteDao.listByVault(context, this.currentVault.id);
    const idToPath: Map<number, string> = new Map<number, string>();
    const nodeMap: Map<string, GraphNode> = new Map<string, GraphNode>();
    for (const note of notes) {
      const node: GraphNode = new GraphNode();
      node.path = note.path;
      node.title = note.title.length > 0 ? note.title : this.noteDisplayName(note.path);
      idToPath.set(note.id, note.path);
      nodeMap.set(note.path, node);
      graph.nodes.push(node);
    }
    const links: LinkRef[] = await LinkDao.listByVault(context, this.currentVault.id);
    const edgeKeys: Set<string> = new Set<string>();
    for (const link of links) {
      if (link.targetPath.length === 0) {
        continue;
      }
      const fromPath: string | undefined = idToPath.get(link.sourceNoteId);
      if (fromPath === undefined) {
        continue;
      }
      // 目标不在本仓库（跨仓库 / 未解析链接）：不出边，仅保留源节点。
      if (!nodeMap.has(link.targetPath)) {
        continue;
      }
      const key: string = `${fromPath}\u0001${link.targetPath}`;
      if (edgeKeys.has(key)) {
        continue;
      }
      edgeKeys.add(key);
      const edge: GraphEdge = new GraphEdge();
      edge.from = fromPath;
      edge.to = link.targetPath;
      graph.edges.push(edge);
    }
    return graph;
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
    this.mtimeByPath = VaultViewModel.buildMtimeMap(this.tree);
    this.refreshTreeItems();
    this.vaultFiles = await manager.listVaultFiles(this.currentVault);
    this.refreshRootFolders();
    await this.refreshAllTags();
  }

  /** 遍历完整文件树，收集 path → mtime（秒）映射（含未展开目录）。 */
  private static buildMtimeMap(nodes: FileNode[]): Map<string, number> {
    const map: Map<string, number> = new Map<string, number>();
    VaultViewModel.collectMtime(nodes, map);
    return map;
  }

  private static collectMtime(nodes: FileNode[], output: Map<string, number>): void {
    for (const node of nodes) {
      if (node.isDir) {
        VaultViewModel.collectMtime(node.children, output);
      } else {
        output.set(node.path, node.mtime);
      }
    }
  }

  /** 列出指定目录（'' 表示根目录）的直接子目录摘要（含子目录递归笔记数）。 */
  public listSubFolders(parentPath: string): RootFolderSummary[] {
    if (parentPath.length === 0) {
      return this.rootFolders;
    }
    const targetNode: FileNode | null = this.findDirNode(this.tree, parentPath);
    if (targetNode === null) {
      return [];
    }
    const folders: RootFolderSummary[] = [];
    for (const child of targetNode.children) {
      if (!child.isDir) {
        continue;
      }
      const summary: RootFolderSummary = new RootFolderSummary();
      summary.name = child.name;
      summary.path = child.path;
      summary.noteCount = this.countMarkdownFilesUnder(`${child.path}/`);
      folders.push(summary);
    }
    return folders;
  }

  private findDirNode(nodes: FileNode[], targetPath: string): FileNode | null {
    for (const node of nodes) {
      if (!node.isDir) {
        continue;
      }
      if (node.path === targetPath) {
        return node;
      }
      if (targetPath.startsWith(`${node.path}/`)) {
        const hit: FileNode | null = this.findDirNode(node.children, targetPath);
        if (hit !== null) {
          return hit;
        }
      }
    }
    return null;
  }

  /** 统计指定目录下的 Markdown 笔记总数（含子目录）。 */
  public countNotesInFolder(dirPath: string): number {
    const normalized: string = VaultPath.normalize(dirPath).replace(/\/+$/, '');
    if (normalized.length === 0) {
      return 0;
    }
    return this.countMarkdownFilesUnder(`${normalized}/`);
  }

  private countMarkdownFilesUnder(prefix: string): number {
    let count: number = 0;
    for (const file of this.vaultFiles) {
      if (file.startsWith(prefix) && file.toLowerCase().endsWith('.md')) {
        count++;
      }
    }
    return count;
  }

  /** 汇总根级目录及各目录笔记数（首页文件页展示）。 */
  private refreshRootFolders(): void {
    const folders: RootFolderSummary[] = [];
    for (const item of this.treeItems) {
      if (item.depth === 0 && item.node.isDir) {
        const summary: RootFolderSummary = new RootFolderSummary();
        summary.name = item.node.name;
        summary.path = item.node.path;
        folders.push(summary);
      }
    }
    for (const folder of folders) {
      folder.noteCount = this.countMarkdownFilesUnder(`${folder.path}/`);
    }
    this.rootFolders = folders;
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
    this.externalUri = '';
    this.externalFileName = '';
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

  /** 进入编辑模式（仅仓库内笔记可编辑；外部文件需先导入仓库）。 */
  public startEdit(): void {
    if (this.selectedPath.length === 0) {
      return;
    }
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

  /** 在当前仓库根目录（或指定子目录）新建空笔记并打开。 */
  public async createNote(folder: string = ''): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    const now: Date = new Date();
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    const stamp: string = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}` +
      `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
    const title: string = `未命名-${stamp}`;
    if (folder.length === 0) {
      // 根目录存在默认模板时套用模板。
      const template: string = await this.findTemplate(['默认', 'default', 'Default', '笔记']);
      if (template.length > 0) {
        await this.createNoteWithTemplate(template, title);
        return;
      }
    } else if (!this.expandedPaths.includes(folder)) {
      this.expandedPaths.push(folder);
    }
    const path: string = folder.length > 0 ? `${folder}/${title}.md` : `${title}.md`;
    await manager.writeNote(this.currentVault, path, '');
    await manager.refreshNote(this.currentVault, path);
    await this.refreshTree();
    await this.openNote(path);
  }

  /**
   * 快速笔记：以标题（为空时用时间戳）在根目录新建笔记并写入内容。
   * 同名文件已存在时追加时间戳后缀避免覆盖。返回新建笔记路径（失败返回空串）。
   */
  public async createQuickNote(title: string, content: string): Promise<string> {
    const manager: VaultManager | null = this.manager;
    if (manager === null || this.currentVault.rootPath.length === 0) {
      return '';
    }
    const now: Date = new Date();
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    const stamp: string = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}` +
      `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
    let safeTitle: string = title.trim().replace(/[\\/:*?"<>|#\[\]]/g, '');
    if (safeTitle.length === 0) {
      safeTitle = `闪念-${stamp}`;
    }
    let path: string = `${safeTitle}.md`;
    if (this.vaultFiles.includes(path)) {
      path = `${safeTitle}-${stamp}.md`;
    }
    const body: string = content.trim();
    const noteContent: string = body.length > 0 ? `# ${safeTitle}\n\n${body}\n` : `# ${safeTitle}\n\n`;
    await manager.writeNote(this.currentVault, path, noteContent);
    await manager.refreshNote(this.currentVault, path);
    await this.refreshTree();
    await this.openNote(path);
    return path;
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
    const hits: Map<string, string> = await BlockDao.findMentions(context,
      this.currentVault.id, title, path);
    hits.forEach((blockText: string, file: string): void => {
      if (!VaultPath.isMarkdown(file) || linked.has(file)) {
        return;
      }
      const index: number = blockText.indexOf(title);
      if (index < 0) {
        return;
      }
      const item: UnlinkedMention = new UnlinkedMention();
      item.path = file;
      item.title = this.noteDisplayName(file);
      const start: number = Math.max(0, index - 20);
      const end: number = Math.min(blockText.length, index + title.length + 20);
      item.context = blockText.substring(start, end).replace(/\n/g, ' ');
      items.push(item);
    });
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

  /** 查询某月的日历数据（有日记标记 + 未完成任务角标，优先从 RDB 列表块索引统计）。 */
  public async calendarMonth(year: number, month: number): Promise<CalendarDay[]> {
    const manager: VaultManager | null = this.manager;
    const context: common.Context | null = this.context;
    const days: CalendarDay[] = [];
    if (manager === null) {
      return days;
    }
    const now: Date = new Date();
    const todayKey: string = VaultViewModel.dateKey(now.getFullYear(), now.getMonth() + 1,
      now.getDate());
    const total: number = new Date(year, month, 0).getDate();
    const pathByDay: Map<string, string> = new Map<string, string>();
    const existingPaths: string[] = [];
    for (let day = 1; day <= total; day++) {
      const dateStr: string = VaultViewModel.dateKey(year, month, day);
      const resolved: string = this.findExistingDailyPathFromTree(dateStr);
      if (resolved.length > 0) {
        pathByDay.set(dateStr, resolved);
        existingPaths.push(resolved);
      }
    }
    const listTextByPath: Map<string, string> = context !== null && existingPaths.length > 0 ?
      await BlockDao.listBlocksByPaths(context, this.currentVault.id, existingPaths) :
      new Map<string, string>();
    for (let day = 1; day <= total; day++) {
      const item: CalendarDay = new CalendarDay();
      item.day = day;
      item.date = VaultViewModel.dateKey(year, month, day);
      item.today = item.date === todayKey;
      const path: string = pathByDay.get(item.date) ?? '';
      if (path.length > 0) {
        item.hasNote = true;
        const indexedListText: string | undefined = listTextByPath.get(path);
        if (indexedListText !== undefined && indexedListText.length > 0) {
          item.openTasks = VaultViewModel.countOpenTasks(indexedListText);
        } else {
          const content: string = await manager.readNote(this.currentVault, path);
          item.openTasks = VaultViewModel.countOpenTasks(content);
        }
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

  /** 新建仓库；仅在未直接配置 WebDAV 的首个仓库预填示例笔记，避免示例笔记污染已有远端库。 */
  public async createVault(name: string, seedDemo: boolean = true): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    this.busy = true;
    try {
      const firstVault: boolean = this.vaults.length === 0 && seedDemo;
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
        this.mtimeByPath = new Map<string, number>();
        if (this.vaults.length > 0) {
          await this.selectVault(this.vaults[0]);
        } else {
          this.currentVault = new VaultInfo();
          await this.loadVaultGraph();
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
    // 文件树直接读文件系统：先刷新让同步拉取的新笔记立即可见，
    // 不必等待下方全量扫描与逐篇索引（720 篇约需十几秒）完成。
    await this.refreshTree();
    await manager.scanVault(this.currentVault);
    const notes: NoteRow[] = await NoteDao.listByVault(context, this.currentVault.id);
    for (const note of notes) {
      // 单篇笔记读取/解析/索引失败不中断整批：本方法常以 fire-and-forget 方式
      // 在同步完成后调用，任何一处抛错都会静默吞掉后续的树刷新，导致笔记不出现。
      try {
        const content: string = await manager.readNote(this.currentVault, note.path);
        const document: MdDocument = MarkdownParser.parse(content);
        await IndexPipeline.indexNote(context, note, document);
      } catch (error) {
        LOG.warn(`rescan index note failed: ${note.path}`);
      }
    }
    await this.refreshTree();
    if (!this.editMode && this.selectedPath.length > 0) {
      const stillExists: NoteRow | null = await NoteDao.findByPath(
        context, this.currentVault.id, this.selectedPath);
      if (stillExists !== null) {
        const refreshed: string = await manager.readNote(this.currentVault, this.selectedPath);
        if (refreshed !== this.noteContent) {
          const parsed: MdDocument = MarkdownParser.parse(refreshed);
          const title: string = parsed.title.length > 0 ?
            parsed.title : VaultPath.basename(this.selectedPath);
          this.applyDocument(this.selectedPath, refreshed, parsed, title);
        }
      }
    }
    await this.refreshNoteInfo();
    // 索引重建后链接关系可能变化，同步刷新整库图谱。
    await this.loadVaultGraph();
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
