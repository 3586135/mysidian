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
import { FileHistory } from './FileHistory';
import { TemplateEngine } from './TemplateEngine';

const LOG: Logger = new Logger('MySidianVault');

/**
 * 仓库管理器：负责沙箱内的仓库目录、文件读写、导入导出与元数据索引。
 * 所有数据均保存在应用沙箱（context.filesDir/vaults）内。
 */
export class VaultManager {
  /** 回收站目录名：以 '.' 开头，天然被文件树、索引与同步忽略。 */
  public static readonly TRASH_DIR: string = '.trash';
  /** 附件目录名：非隐藏目录，图片附件会参与 WebDAV 同步。 */
  public static readonly ATTACHMENT_DIR: string = 'attachments';
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
    // 覆盖前保留历史快照（本地文件历史）。
    if (fileIo.accessSync(absolute)) {
      await FileHistory.snapshot(this.context, vault, relativePath);
    }
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

  /** 在仓库内创建目录（已存在时返回 false）。 */
  public async createFolder(vault: VaultInfo, relativePath: string): Promise<boolean> {
    const trimmed: string = VaultPath.normalize(relativePath);
    if (trimmed.length === 0) {
      return false;
    }
    const absolute: string = VaultPath.absolute(vault.rootPath, trimmed);
    if (fileIo.accessSync(absolute)) {
      return false;
    }
    fileIo.mkdirSync(absolute, true);
    await VaultDao.touch(this.context, vault.id);
    return true;
  }

  /**
   * 删除笔记：移入 .trash 回收站。
   * 文件名加时间戳前缀，避免同名笔记互相覆盖；返回回收站内相对路径。
   */
  public async trashNote(vault: VaultInfo, relativePath: string): Promise<string> {
    const absolute: string = VaultPath.absolute(vault.rootPath, relativePath);
    if (!fileIo.accessSync(absolute)) {
      return '';
    }
    const trashDir: string = VaultPath.absolute(vault.rootPath, VaultManager.TRASH_DIR);
    if (!fileIo.accessSync(trashDir)) {
      fileIo.mkdirSync(trashDir, true);
    }
    // 时间戳前缀防同名覆盖；同一毫秒内连续删除同名文件（批量删除）时
    // 追加序号，避免 renameSync 静默覆盖先删的那份。
    const basename: string = VaultPath.basename(relativePath);
    let name: string = `${Date.now()}_${basename}`;
    let suffix: number = 1;
    while (fileIo.accessSync(`${trashDir}/${name}`)) {
      name = `${Date.now()}_${suffix}_${basename}`;
      suffix++;
    }
    fileIo.renameSync(absolute, `${trashDir}/${name}`);
    await NoteDao.removeByPath(this.context, vault.id, relativePath);
    await VaultDao.touch(this.context, vault.id);
    return `${VaultManager.TRASH_DIR}/${name}`;
  }

  /** 从回收站恢复笔记到仓库根目录，返回恢复后的相对路径。 */
  public async restoreNote(vault: VaultInfo, trashRelativePath: string): Promise<string> {
    const absolute: string = VaultPath.absolute(vault.rootPath, trashRelativePath);
    if (!fileIo.accessSync(absolute)) {
      return '';
    }
    const restored: string = VaultManager.uniqueRestoredName(vault.rootPath,
      VaultManager.stripTrashStamp(VaultPath.basename(trashRelativePath)));
    fileIo.renameSync(absolute, VaultPath.absolute(vault.rootPath, restored));
    await this.refreshNote(vault, restored);
    await VaultDao.touch(this.context, vault.id);
    return restored;
  }

  /** 清空回收站：删除 .trash 下所有内容，返回删除的文件数。 */
  public async emptyTrash(vault: VaultInfo): Promise<number> {
    const trashDir: string = VaultPath.absolute(vault.rootPath, VaultManager.TRASH_DIR);
    if (!fileIo.accessSync(trashDir)) {
      return 0;
    }
    const names: string[] = fileIo.listFileSync(trashDir);
    let removed: number = 0;
    for (const name of names) {
      const full: string = `${trashDir}/${name}`;
      if (fileIo.statSync(full).isDirectory()) {
        this.removeDirectory(full);
      } else {
        fileIo.unlinkSync(full);
      }
      removed++;
    }
    await VaultDao.touch(this.context, vault.id);
    return removed;
  }

  /** 列出回收站内的文件相对路径。 */
  public async listTrash(vault: VaultInfo): Promise<string[]> {
    const trashDir: string = VaultPath.absolute(vault.rootPath, VaultManager.TRASH_DIR);
    const items: string[] = [];
    if (!fileIo.accessSync(trashDir)) {
      return items;
    }
    const names: string[] = fileIo.listFileSync(trashDir);
    for (const name of names) {
      items.push(`${VaultManager.TRASH_DIR}/${name}`);
    }
    return items;
  }

  /**
   * 重命名笔记（保持笔记主键不变）。
   * 只改文件与 note 表路径，双链正文重写由上层（视图模型）驱动。
   */
  public async renameNote(vault: VaultInfo, relativePath: string,
    newRelativePath: string): Promise<boolean> {
    return this.relocateNote(vault, relativePath, newRelativePath);
  }

  /**
   * 移动笔记到目标目录（保持笔记主键不变）。
   * 仓库内 wiki 链接按文件名解析，移动目录不影响既有链接，无需重写正文。
   */
  public async moveNote(vault: VaultInfo, relativePath: string,
    newRelativePath: string): Promise<boolean> {
    return this.relocateNote(vault, relativePath, newRelativePath);
  }

  /** 把图片二进制写入仓库附件目录，返回相对路径。 */
  public async importImageBuffer(vault: VaultInfo, data: ArrayBuffer,
    extension: string): Promise<string> {
    const dir: string = VaultPath.absolute(vault.rootPath, VaultManager.ATTACHMENT_DIR);
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true);
    }
    let ext: string = extension.trim().toLowerCase();
    if (ext.startsWith('.')) {
      ext = ext.substring(1);
    }
    const suffix: string = ext.length > 0 ? `.${ext}` : '.png';
    const name: string = `${Date.now()}_${Math.floor(Math.random() * 100000)}${suffix}`;
    const target: string = `${dir}/${name}`;
    const file = fileIo.openSync(target,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, data);
      fileIo.fsyncSync(file.fd);
    } finally {
      fileIo.closeSync(file);
    }
    await VaultDao.touch(this.context, vault.id);
    return `${VaultManager.ATTACHMENT_DIR}/${name}`;
  }

  /** 导入附件（图片）到 attachments 目录，返回仓库相对路径。 */
  public async importAttachment(vault: VaultInfo, sourceUri: string,
    extension: string): Promise<string> {
    const dir: string = VaultPath.absolute(vault.rootPath, VaultManager.ATTACHMENT_DIR);
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true);
    }
    let ext: string = extension.trim().toLowerCase();
    if (ext.startsWith('.')) {
      ext = ext.substring(1);
    }
    const suffix: string = ext.length > 0 ? `.${ext}` : '';
    const name: string = `${Date.now()}_${Math.floor(Math.random() * 100000)}${suffix}`;
    const target: string = `${dir}/${name}`;
    try {
      ZipTransfer.copyUriToFile(sourceUri, target);
    } catch (error) {
      const err = error as BusinessError;
      LOG.error(`import attachment failed, code=${err.code}, message=${err.message}`);
      return '';
    }
    await VaultDao.touch(this.context, vault.id);
    return `${VaultManager.ATTACHMENT_DIR}/${name}`;
  }

  /** 列出仓库内全部文件的相对路径（附件解析用）。 */
  public async listVaultFiles(vault: VaultInfo): Promise<string[]> {
    const files: string[] = [];
    this.collectFiles(vault.rootPath, '', files);
    return files;
  }

  /** 读取文件的修改时间与大小（检测外部改动）。 */
  public statFile(vault: VaultInfo, relativePath: string): FileStatInfo | null {
    const absolute: string = VaultPath.absolute(vault.rootPath, relativePath);
    if (!fileIo.accessSync(absolute)) {
      return null;
    }
    try {
      const stat: fileIo.Stat = fileIo.statSync(absolute);
      const info: FileStatInfo = new FileStatInfo();
      info.mtime = stat.mtime;
      info.size = stat.size;
      return info;
    } catch (error) {
      return null;
    }
  }

  /** 列出模板文件（Templates 目录下的 Markdown）。 */
  public async listTemplates(vault: VaultInfo): Promise<string[]> {
    const templates: string[] = [];
    const dir: string = VaultPath.absolute(vault.rootPath, TemplateEngine.TEMPLATES_DIR);
    if (!fileIo.accessSync(dir)) {
      return templates;
    }
    const names: string[] = fileIo.listFileSync(dir);
    for (const name of names) {
      if (!name.toLowerCase().endsWith('.md')) {
        continue;
      }
      templates.push(`${TemplateEngine.TEMPLATES_DIR}/${name}`);
    }
    templates.sort();
    return templates;
  }

  /** 读取模板内容。 */
  public async readTemplate(vault: VaultInfo, relativePath: string): Promise<string> {
    const absolute: string = VaultPath.absolute(vault.rootPath, relativePath);
    if (!fileIo.accessSync(absolute)) {
      return '';
    }
    return fileIo.readTextSync(absolute);
  }

  /** 移动 / 重命名笔记的公共实现：改文件 + 更新 note 表路径（主键不变）。 */
  private async relocateNote(vault: VaultInfo, relativePath: string,
    newRelativePath: string): Promise<boolean> {
    const absolute: string = VaultPath.absolute(vault.rootPath, relativePath);
    const target: string = VaultPath.absolute(vault.rootPath, newRelativePath);
    if (!fileIo.accessSync(absolute) || absolute === target) {
      return false;
    }
    if (fileIo.accessSync(target)) {
      return false;
    }
    const dir: string = VaultPath.dirname(target);
    if (dir.length > 0 && !fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true);
    }
    fileIo.renameSync(absolute, target);
    await NoteDao.updatePath(this.context, vault.id, relativePath, newRelativePath,
      VaultPath.basenameWithoutExt(newRelativePath));
    await this.refreshNote(vault, newRelativePath);
    await VaultDao.touch(this.context, vault.id);
    return true;
  }

  /** 去掉回收站文件名的时间戳（及同毫秒防重名附加的序号）前缀。 */
  private static stripTrashStamp(name: string): string {
    let rest: string = name;
    // 最多剥离两段纯数字前缀：时间戳 + 同毫秒防重名序号。
    for (let round = 0; round < 2; round++) {
      const index: number = rest.indexOf('_');
      if (index <= 0) {
        return rest;
      }
      const prefix: string = rest.substring(0, index);
      for (let i = 0; i < prefix.length; i++) {
        const code: number = prefix.charCodeAt(i);
        if (code < 48 || code > 57) {
          return rest;
        }
      }
      rest = rest.substring(index + 1);
    }
    return rest;
  }

  /** 恢复时若目标同名已存在，追加序号避免覆盖。 */
  private static uniqueRestoredName(root: string, name: string): string {
    if (!fileIo.accessSync(VaultPath.absolute(root, name))) {
      return name;
    }
    const dot: number = name.lastIndexOf('.');
    const stem: string = dot > 0 ? name.substring(0, dot) : name;
    const ext: string = dot > 0 ? name.substring(dot) : '';
    for (let i = 1; i < 100; i++) {
      const candidate: string = `${stem}-${i}${ext}`;
      if (!fileIo.accessSync(VaultPath.absolute(root, candidate))) {
        return candidate;
      }
    }
    return `${stem}-${Date.now()}${ext}`;
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

/** 文件状态信息（修改时间与大小，用于检测外部改动）。 */
export class FileStatInfo {
  /** 修改时间（毫秒）。 */
  mtime: number = 0;
  /** 文件大小（字节）。 */
  size: number = 0;
}
