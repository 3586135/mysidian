import { common } from '@kit.AbilityKit';
import { FileNode, FlatFileNode, MdDocument, VaultInfo } from '@ohos/domain';
import { Logger } from '@ohos/common';
import { MarkdownParser } from '@ohos/markdown';
import { NoteResolver, VaultManager, VaultPath } from '@ohos/vault';

const LOG: Logger = new Logger('MySidianVM');

/**
 * 仓库视图模型：负责仓库列表、文件树、笔记读取与导入导出。
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

  private manager: VaultManager | null = null;
  private context: common.Context | null = null;
  private tree: FileNode[] = [];
  private expandedPaths: string[] = [];

  /** 初始化存储层并加载仓库列表。 */
  public async init(context: common.Context): Promise<void> {
    try {
      this.context = context;
      this.manager = await VaultManager.create(context);
      await this.refreshVaults();
      if (this.vaults.length > 0) {
        await this.selectVault(this.vaults[0]);
      }
    } catch (error) {
      LOG.error('vault view model init failed');
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

  /** 打开笔记。 */
  public async openNote(path: string): Promise<void> {
    const manager: VaultManager | null = this.manager;
    if (manager === null) {
      return;
    }
    this.selectedPath = path;
    this.noteTitle = VaultPath.basename(path);
    this.noteContent = await manager.readNote(this.currentVault, path);
    this.document = MarkdownParser.parse(this.noteContent);
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
