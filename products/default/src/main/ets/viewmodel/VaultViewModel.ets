import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BacklinkItem, FileNode, FlatFileNode, MdDocument, MdProperty, NoteRow, OutlineEntry,
  VaultInfo } from '@ohos/domain';
import { Logger } from '@ohos/common';
import { MarkdownParser } from '@ohos/markdown';
import { BlockDao, IndexPipeline, LinkDao, NoteDao, NoteResolver, PropDao, TagDao, VaultManager,
  VaultPath } from '@ohos/vault';

const LOG: Logger = new Logger('MySidianVM');
const PREFERENCE_STORE: string = 'mysidian_preferences';

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
  private tree: FileNode[] = [];
  private expandedPaths: string[] = [];

  /** 初始化存储层并加载仓库列表。 */
  public async init(context: common.Context): Promise<void> {
    try {
      this.context = context;
      this.manager = await VaultManager.create(context);
      await this.loadPreferences(context);
      await this.refreshVaults();
      if (this.vaults.length > 0) {
        await this.selectVault(this.vaults[0]);
      }
    } catch (error) {
      LOG.error('vault view model init failed');
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
    this.tree = await manager.buildTree(vault);
    this.refreshTreeItems();
    await this.ensureIndexed(vault);
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

  /** 打开笔记，并同步建立索引。 */
  public async openNote(path: string): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    this.selectedPath = path;
    this.noteTitle = VaultPath.basename(path);
    this.noteContent = await manager.readNote(this.currentVault, path);
    this.document = MarkdownParser.parse(this.noteContent);
    if (this.document.title.length > 0) {
      this.noteTitle = this.document.title;
    }
    this.editMode = false;
    this.draftBuffer = '';
    await this.reindexCurrentNote();
    await this.refreshNoteInfo();
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

  /** 导出当前仓库为 zip。 */
  public async exportVault(uri: string): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    this.busy = true;
    try {
      await manager.exportVault(this.currentVault, uri);
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
