import { fileIo, hash } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { RemoteEntry, SyncConfig, SyncConflict, SyncProvider, SyncState, SyncStatus, VaultInfo }
  from '@ohos/domain';
import { Logger } from '@ohos/common';
import { SyncStateDao } from '@ohos/vault';
import { ConflictResolver } from './ConflictResolver';
import { WebDavProvider } from '../provider/WebDavProvider';

const LOG: Logger = new Logger('MySidianSync');

/**
 * 双向同步引擎。
 * 依据「本地清单 / 远端清单 / 上次同步基线」三方比较决定上传、下载或产生冲突。
 */
export class SyncEngine {
  private provider: SyncProvider | null = null;
  private status: SyncStatus = new SyncStatus();
  private conflicts: SyncConflict[] = [];

  public getStatus(): SyncStatus {
    return this.status;
  }

  public getConflicts(): SyncConflict[] {
    return this.conflicts;
  }

  /**
   * 执行一次同步。
   */
  public async sync(vault: VaultInfo, config: SyncConfig, context: common.Context):
    Promise<SyncStatus> {
    this.status = new SyncStatus();
    this.status.state = SyncState.SYNCING;
    this.status.message = 'syncing';
    this.conflicts = [];
    const provider: SyncProvider = new WebDavProvider();
    this.provider = provider;
    try {
      await provider.connect(config);
      const remoteEntries: RemoteEntry[] = await provider.list('');
      const localEntries: RemoteEntry[] = await this.collectLocalEntries(vault);
      const baselines: Map<string, string> = await SyncStateDao.baselines(context);

      const remoteMap: Map<string, RemoteEntry> = new Map<string, RemoteEntry>();
      for (const entry of remoteEntries) {
        remoteMap.set(entry.path, entry);
      }
      const localMap: Map<string, RemoteEntry> = new Map<string, RemoteEntry>();
      for (const entry of localEntries) {
        localMap.set(entry.path, entry);
      }

      for (const local of localEntries) {
        const remote: RemoteEntry | undefined = remoteMap.get(local.path);
        if (remote === undefined) {
          await this.pushEntry(provider, vault, local);
          this.status.pendingUploads++;
          continue;
        }
        if (remote.etag === local.etag) {
          continue;
        }
        const baseline: string | undefined = baselines.get(local.path);
        if (baseline !== undefined && baseline === remote.etag) {
          await this.pushEntry(provider, vault, local);
          this.status.pendingUploads++;
          continue;
        }
        if (baseline !== undefined && baseline === local.etag) {
          await this.pullEntry(provider, vault, remote);
          this.status.pendingDownloads++;
          continue;
        }
        await this.resolveConflict(provider, vault, local, remote);
      }

      for (const remote of remoteEntries) {
        if (!localMap.has(remote.path)) {
          await this.pullEntry(provider, vault, remote);
          this.status.pendingDownloads++;
        }
      }

      await provider.putManifest(localEntries);
      await SyncStateDao.clear(context);
      for (const entry of localEntries) {
        await SyncStateDao.put(context, entry.path, entry.etag, entry.mtime, entry.etag);
      }

      this.status.state = this.conflicts.length > 0 ? SyncState.CONFLICT : SyncState.SUCCESS;
      this.status.message = this.conflicts.length > 0 ? 'conflict' : 'success';
      this.status.lastSyncAt = Date.now();
      LOG.info(`sync finished, uploads=${this.status.pendingUploads}, ` +
        `downloads=${this.status.pendingDownloads}, conflicts=${this.conflicts.length}`);
    } catch (error) {
      this.status.state = SyncState.FAILED;
      this.status.message = 'failed';
      LOG.error('sync failed');
    } finally {
      await provider.disconnect();
      this.provider = null;
    }
    return this.status;
  }

  /** 收集本地可同步文件（Markdown 文本文件）。 */
  private async collectLocalEntries(vault: VaultInfo): Promise<RemoteEntry[]> {
    const entries: RemoteEntry[] = [];
    this.collectFiles(vault.rootPath, '', entries);
    const result: RemoteEntry[] = [];
    for (const entry of entries) {
      const absolute: string = `${vault.rootPath}/${entry.path}`;
      const stat = fileIo.statSync(absolute);
      const item: RemoteEntry = new RemoteEntry();
      item.path = entry.path;
      item.size = stat.size;
      item.mtime = stat.mtime;
      item.etag = await hash.hash(absolute, 'sha256');
      item.isDir = false;
      result.push(item);
    }
    return result;
  }

  private collectFiles(fullPath: string, relativePath: string, output: RemoteEntry[]): void {
    const names: string[] = fileIo.listFileSync(fullPath);
    for (const name of names) {
      if (name.startsWith('.')) {
        continue;
      }
      const childFull: string = `${fullPath}/${name}`;
      const childRelative: string = relativePath.length === 0 ? name : `${relativePath}/${name}`;
      if (fileIo.statSync(childFull).isDirectory()) {
        if (name === 'conflicts') {
          continue;
        }
        this.collectFiles(childFull, childRelative, output);
        continue;
      }
      if (!name.toLowerCase().endsWith('.md')) {
        continue;
      }
      const entry: RemoteEntry = new RemoteEntry();
      entry.path = childRelative;
      output.push(entry);
    }
  }

  private async pushEntry(provider: SyncProvider, vault: VaultInfo, entry: RemoteEntry): Promise<void> {
    const absolute: string = `${vault.rootPath}/${entry.path}`;
    await provider.push(absolute, entry);
  }

  private async pullEntry(provider: SyncProvider, vault: VaultInfo, entry: RemoteEntry): Promise<void> {
    const absolute: string = `${vault.rootPath}/${entry.path}`;
    const folder: string = absolute.substring(0, absolute.lastIndexOf('/'));
    if (!fileIo.accessSync(folder)) {
      fileIo.mkdirSync(folder, true);
    }
    await provider.pull(entry, absolute);
  }

  private async resolveConflict(provider: SyncProvider, vault: VaultInfo, local: RemoteEntry,
    remote: RemoteEntry): Promise<void> {
    const conflict: SyncConflict = new SyncConflict();
    conflict.path = local.path;
    conflict.localHash = local.etag;
    conflict.remoteHash = remote.etag;
    const absolute: string = `${vault.rootPath}/${local.path}`;
    const remoteContent: string = fileIo.readTextSync(absolute);
    conflict.conflictPath = await ConflictResolver.saveCopy(vault, local.path, remoteContent);
    this.conflicts.push(conflict);
    await this.pushEntry(provider, vault, local);
    this.status.pendingUploads++;
  }
}
