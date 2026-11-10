import { fileIo, hash } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FileNode, NoteRow, VaultInfo } from '@ohos/domain';
import { Logger } from '@ohos/common';
import { DbHelper } from '../db/DbHelper';
import { NoteDao } from '../db/NoteDao';
import { VaultDao } from '../db/VaultDao';
import { VaultPath } from './VaultPath';
import { ZipTransfer } from './ZipTransfer';
import { DemoNote, DemoVaultContent } from './DemoVaultContent';

const LOG: Logger = new Logger('MySidianVault');

/**
 * 仓库管理器：负责沙箱内的仓库目录、文件读写、导入导出与元数据索引。
 * 所有数据均保存在应用沙箱（context.filesDir/vaults）内。
 */
export class VaultManager {
  private readonly context: common.Context;
  private readonly vaultsRoot: string;

  private constructor(context: common.Context) {
    this.context = context;
    this.vaultsRoot = `${context.filesDir}/vaults`;
  }

  /** 创建管理器并初始化数据库与仓库根目录。 */
  public static async create(context: common.Context): Promise<VaultManager> {
    await DbHelper.init(context);
    const manager: VaultManager = new VaultManager(context);
    manager.ensureVaultsRoot();
    return manager;
  }

  /** 仓库根目录。 */
  public getVaultsRoot(): string {
    return this.vaultsRoot;
  }

  /** 查询全部仓库。 */
  public async listVaults(): Promise<VaultInfo[]> {
    const vaults: VaultInfo[] = await VaultDao.list(this.context);
    const valid: VaultInfo[] = [];
    for (const vault of vaults) {
      if (fileIo.accessSync(vault.rootPath)) {
        valid.push(vault);
      }
    }
    return valid;
  }

  /** 新建空仓库。 */
  public async createVault(name: string): Promise<VaultInfo> {
    const now: number = Date.now();
    const safeName: string = VaultPath.sanitizeName(name);
    const root: string = `${this.vaultsRoot}/${now}_${safeName}`;
    fileIo.mkdirSync(root, true);
    const info: VaultInfo = new VaultInfo();
    info.name = safeName;
    info.rootPath = root;
    info.createdAt = now;
    info.updatedAt = now;
    info.id = await VaultDao.insert(this.context, info);
    LOG.info(`created vault ${info.name} at ${root}`);
    return info;
  }

  /** 创建预填示例笔记的仓库（引导页首次新建仓库时调用）。 */
  public async createDemoVault(name: string): Promise<VaultInfo> {
    const vault: VaultInfo = await this.createVault(name.length > 0 ? name : '示例仓库');
    const notes: DemoNote[] = DemoVaultContent.notes();
    for (const note of notes) {
      await this.writeNote(vault, note.path, note.content);
    }
    await this.scanVault(vault);
    LOG.info('seeded demo vault');
    return vault;
  }

  /** 导入 zip 仓库。 */
  public async importVault(uri: string, name: string): Promise<VaultInfo> {
    const now: number = Date.now();
    const safeName: string = VaultPath.sanitizeName(name);
    const root: string = `${this.vaultsRoot}/${now}_${safeName}`;
    fileIo.mkdirSync(root, true);
    try {
      await ZipTransfer.importZip(this.context, uri, root);
      const realRoot: string = this.resolveImportRoot(root);
      const info: VaultInfo = new VaultInfo();
      info.name = safeName;
      info.rootPath = realRoot;
      info.createdAt = now;
      info.updatedAt = now;
      info.id = await VaultDao.insert(this.context, info);
      await this.scanVault(info);
      LOG.info(`imported vault ${info.name} from archive`);
      return info;
    } catch (error) {
      const err = error as BusinessError;
      LOG.error(`import vault failed, code=${err.code}, message=${err.message}, root=${root}`);
      this.removeDirectory(root);
      throw new Error(`vault import failed, code=${err.code}, message=${err.message}`);
    }
  }

  /** 导出仓库为 zip。 */
  public async exportVault(vault: VaultInfo, uri: string): Promise<void> {
    await ZipTransfer.exportZip(this.context, vault.rootPath, uri);
  }

  /** 删除仓库（包含磁盘目录）。 */
  public async deleteVault(vault: VaultInfo): Promise<void> {
    await NoteDao.removeByVault(this.context, vault.id);
    await VaultDao.remove(this.context, vault.id);
    this.removeDirectory(vault.rootPath);
    LOG.info(`deleted vault ${vault.name}`);
  }

  /** 构建仓库文件树。 */
  public async buildTree(vault: VaultInfo): Promise<FileNode[]> {
    return this.buildChildren(vault.rootPath, '');
  }

  /** 读取笔记内容。 */
  public async readNote(vault: VaultInfo, relativePath: string): Promise<string> {
    const absolute: string = VaultPath.absolute(vault.rootPath, relativePath);
    if (!fileIo.accessSync(absolute)) {
      return '';
    }
    return fileIo.readTextSync(absolute);
  }

  /** 原子写入笔记内容。 */
  public async writeNote(vault: VaultInfo, relativePath: string, content: string): Promise<void> {
    const absolute: string = VaultPath.absolute(vault.rootPath, relativePath);
    const dir: string = VaultPath.dirname(absolute);
    if (dir.length > 0 && !fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true);
    }
    const tempPath: string = `${absolute}.tmp`;
    const file = fileIo.openSync(tempPath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, content);
      fileIo.fsyncSync(file.fd);
    } finally {
      fileIo.closeSync(file);
    }
    fileIo.renameSync(tempPath, absolute);
    await VaultDao.touch(this.context, vault.id);
  }

  /** 删除笔记文件。 */
  public async deleteNote(vault: VaultInfo, relativePath: string): Promise<void> {
    const absolute: string = VaultPath.absolute(vault.rootPath, relativePath);
    if (fileIo.accessSync(absolute)) {
      fileIo.unlinkSync(absolute);
    }
    await VaultDao.touch(this.context, vault.id);
  }

  /** 扫描仓库并刷新笔记元数据索引，返回笔记数量。 */
  public async scanVault(vault: VaultInfo): Promise<number> {
    await NoteDao.removeByVault(this.context, vault.id);
    const files: string[] = [];
    this.collectFiles(vault.rootPath, '', files);
    let count: number = 0;
    for (const relative of files) {
      if (!VaultPath.isMarkdown(relative)) {
        continue;
      }
      const absolute: string = VaultPath.absolute(vault.rootPath, relative);
      const stat = fileIo.statSync(absolute);
      const row: NoteRow = new NoteRow();
      row.vaultId = vault.id;
      row.path = relative;
      row.ext = VaultPath.extension(relative);
      row.title = VaultPath.basenameWithoutExt(relative);
      row.mtime = stat.mtime;
      row.size = stat.size;
      row.hash = await this.hashFile(absolute);
      await NoteDao.upsert(this.context, row);
      count++;
    }
    await VaultDao.touch(this.context, vault.id);
    LOG.info(`scanned vault ${vault.name}, ${count} notes`);
    return count;
  }

  /** 查询仓库笔记列表。 */
  public async listNotes(vault: VaultInfo): Promise<NoteRow[]> {
    return await NoteDao.listByVault(this.context, vault.id);
  }

  /** 刷新单篇笔记的元数据（保存后调用）。 */
  public async refreshNote(vault: VaultInfo, relativePath: string): Promise<NoteRow | null> {
    const absolute: string = VaultPath.absolute(vault.rootPath, relativePath);
    if (!fileIo.accessSync(absolute)) {
      return null;
    }
    const stat = fileIo.statSync(absolute);
    const row: NoteRow = new NoteRow();
    row.vaultId = vault.id;
    row.path = relativePath;
    row.ext = VaultPath.extension(relativePath);
    row.title = VaultPath.basenameWithoutExt(relativePath);
    row.mtime = stat.mtime;
    row.size = stat.size;
    row.hash = await this.hashFile(absolute);
    row.id = await NoteDao.upsert(this.context, row);
    return row;
  }

  private async hashFile(absolutePath: string): Promise<string> {
    try {
      return await hash.hash(absolutePath, 'sha256');
    } catch (error) {
      LOG.warn(`hash failed for ${absolutePath}`);
      return '';
    }
  }

  private ensureVaultsRoot(): void {
    if (!fileIo.accessSync(this.vaultsRoot)) {
      fileIo.mkdirSync(this.vaultsRoot, true);
    }
  }

  /** 解压后若根目录下只有一个子目录，则以该子目录作为仓库根。 */
  private resolveImportRoot(root: string): string {
    const names: string[] = fileIo.listFileSync(root);
    if (names.length !== 1) {
      return root;
    }
    const only: string = names[0];
    const full: string = `${root}/${only}`;
    if (fileIo.accessSync(full) && fileIo.statSync(full).isDirectory()) {
      return full;
    }
    return root;
  }

  private removeDirectory(path: string): void {
    if (!fileIo.accessSync(path)) {
      return;
    }
    this.removeDirectoryContent(path);
    fileIo.rmdirSync(path);
  }

  private removeDirectoryContent(dir: string): void {
    const names: string[] = fileIo.listFileSync(dir);
    for (const name of names) {
      const full: string = `${dir}/${name}`;
      if (fileIo.statSync(full).isDirectory()) {
        this.removeDirectoryContent(full);
        fileIo.rmdirSync(full);
      } else {
        fileIo.unlinkSync(full);
      }
    }
  }

  private buildChildren(fullPath: string, relativePath: string): FileNode[] {
    const nodes: FileNode[] = [];
    if (!fileIo.accessSync(fullPath)) {
      return nodes;
    }
    const names: string[] = fileIo.listFileSync(fullPath);
    names.sort();
    for (const name of names) {
      if (name.startsWith('.')) {
        continue;
      }
      const childFull: string = `${fullPath}/${name}`;
      const childRelative: string = relativePath.length === 0 ? name : `${relativePath}/${name}`;
      const stat = fileIo.statSync(childFull);
      const node: FileNode = new FileNode();
      node.name = name;
      node.path = childRelative;
      node.isDir = stat.isDirectory();
      node.size = stat.size;
      node.mtime = stat.mtime;
      if (node.isDir) {
        node.children = this.buildChildren(childFull, childRelative);
      }
      nodes.push(node);
    }
    return nodes;
  }

  private collectFiles(fullPath: string, relativePath: string, output: string[]): void {
    const names: string[] = fileIo.listFileSync(fullPath);
    for (const name of names) {
      if (name.startsWith('.')) {
        continue;
      }
      const childFull: string = `${fullPath}/${name}`;
      const childRelative: string = relativePath.length === 0 ? name : `${relativePath}/${name}`;
      if (fileIo.statSync(childFull).isDirectory()) {
        this.collectFiles(childFull, childRelative, output);
      } else {
        output.push(childRelative);
      }
    }
  }
}
