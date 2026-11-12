import { fileIo, hash } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { RemoteEntry, SyncConfig, SyncConflict, SyncFileFilter, SyncProvider, SyncState, SyncStatus,
  VaultInfo } from '@ohos/domain';
import { Logger } from '@ohos/common';
import { FileHistory, SyncBaseline, SyncBaselineRow, SyncStateDao } from '@ohos/vault';
import { ConflictResolver } from './ConflictResolver';
import { WebDavProvider } from '../provider/WebDavProvider';

const LOG: Logger = new Logger('MySidianSync');

/**
 * 远端新文件拉取并发数。
 * 注意：fnOS（nginx Basic 认证）对短时并发认证请求返回 401，且模拟器
 * netstack 并发在途请求存在认证头丢失问题，故采用串行拉取保证稳定。
 */
const PULL_CONCURRENCY: number = 1;

/**
 * 双向同步引擎。
 * 依据「本地清单 / 远端清单 / 上次同步基线」三方比较决定上传、下载或产生冲突；
 * 另以服务器原生版本标识（serverTag，来自 PROPFIND 的 etag）检测
 * 清单协议之外的外部修改（如桌面 Obsidian 直接写入 WebDAV）。
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
      const baselines: Map<string, SyncBaseline> = await SyncStateDao.baselines(context, vault.id);
      LOG.info(`sync plan: local=${localEntries.length}, remote=${remoteEntries.length}`);

      const remoteMap: Map<string, RemoteEntry> = new Map<string, RemoteEntry>();
      for (const entry of remoteEntries) {
        remoteMap.set(entry.path, entry);
      }
      const localMap: Map<string, RemoteEntry> = new Map<string, RemoteEntry>();
      for (const entry of localEntries) {
        localMap.set(entry.path, entry);
      }
      // 服务器原生版本标识快照：PROPFIND 提供，push 后用 PUT 响应的 ETag 更新。
      const serverTagMap: Map<string, string> = new Map<string, string>();
      for (const entry of remoteEntries) {
        if (entry.serverTag.length > 0) {
          serverTagMap.set(entry.path, entry.serverTag);
        }
      }

      for (const local of localEntries) {
        const remote: RemoteEntry | undefined = remoteMap.get(local.path);
        if (remote === undefined) {
          LOG.info(`sync push (new): ${local.path}`);
          await this.pushEntry(provider, vault, local, serverTagMap);
          this.status.pendingUploads++;
          continue;
        }
        if (remote.etag === local.etag) {
          // 内容与上次同步一致：以服务器版本标识兜底检测外部修改
          // （清单哈希未变但桌面端直接改写了文件的场景）。
          const baseline: SyncBaseline | undefined = baselines.get(local.path);
          if (baseline !== undefined && baseline.serverTag.length > 0 &&
            remote.serverTag.length > 0 && remote.serverTag !== baseline.serverTag) {
            LOG.info(`sync pull (external change): ${local.path}`);
            await this.pullEntry(provider, vault, remote, context);
            this.status.pendingDownloads++;
          }
          continue;
        }
        if (remote.etag.length === 0) {
          // 远端哈希未知（PROPFIND 发现的清单外文件）：serverTag 与基线一致可跳过。
          const unhashedBaseline: SyncBaseline | undefined = baselines.get(local.path);
          if (unhashedBaseline !== undefined && unhashedBaseline.serverTag.length > 0 &&
            remote.serverTag.length > 0 && unhashedBaseline.serverTag === remote.serverTag) {
            continue;
          }
          // 否则按内容判断是否一致（二进制附件无法按文本比对，直接以本地为准）。
          if (!SyncFileFilter.isMarkdown(local.path)) {
            LOG.info(`sync conflict (unhashed binary): ${local.path}`);
            await this.resolveConflict(provider, vault, local, remote, serverTagMap);
            continue;
          }
          const remoteText: string = await provider.readRemote(local.path);
          const localAbs: string = `${vault.rootPath}/${local.path}`;
          const localText: string = fileIo.readTextSync(localAbs);
          if (remoteText === localText) {
            continue;
          }
          LOG.info(`sync conflict (unhashed remote): ${local.path}`);
          await this.resolveConflict(provider, vault, local, remote, serverTagMap);
          continue;
        }
        const baseline: SyncBaseline | undefined = baselines.get(local.path);
        if (baseline !== undefined && baseline.fileHash === remote.etag) {
          LOG.info(`sync push (local changed): ${local.path}`);
          await this.pushEntry(provider, vault, local, serverTagMap);
          this.status.pendingUploads++;
          continue;
        }
        if (baseline !== undefined && baseline.fileHash === local.etag) {
          LOG.info(`sync pull (remote changed): ${remote.path}`);
          await this.pullEntry(provider, vault, remote, context);
          this.status.pendingDownloads++;
          continue;
        }
        LOG.info(`sync conflict: ${local.path}`);
        await this.resolveConflict(provider, vault, local, remote, serverTagMap);
      }

      // 远端存在、本地没有的文件分两类：
      // - 命中基线：上次同步后本地删除（移入回收站等）→ 删除传播到远端，
      //   否则删除会被下一轮同步无条件拉回（删除被撤销）。
      // - 未命中基线：远端新文件 → 拉取。单个 404（枚举后被删除、
      //   清单幽灵条目）跳过即可，不应中断整轮同步。
      const pendingPulls: RemoteEntry[] = [];
      const pendingDeletes: RemoteEntry[] = [];
      for (const remote of remoteEntries) {
        if (!localMap.has(remote.path)) {
          if (baselines.has(remote.path)) {
            pendingDeletes.push(remote);
          } else {
            pendingPulls.push(remote);
          }
        }
      }
      if (pendingPulls.length > 0) {
        LOG.info(`sync pull pending: ${pendingPulls.length} remote-new files`);
      }
      for (const deleted of pendingDeletes) {
        LOG.info(`sync delete (local removed): ${deleted.path}`);
        await provider.deleteRemote(deleted.path);
      }
      for (let i = 0; i < pendingPulls.length; i += PULL_CONCURRENCY) {
        const batch: RemoteEntry[] = pendingPulls.slice(i, i + PULL_CONCURRENCY);
        const outcomes: Array<string | null> = await Promise.all(batch.map(
          (remote: RemoteEntry): Promise<string | null> => {
            return this.pullRemote(provider, vault, remote, context);
          }));
        for (let k = 0; k < outcomes.length; k++) {
          const outcome: string | null = outcomes[k];
          if (outcome === null) {
            continue;
          }
          if (outcome.includes('404')) {
            LOG.warn(`sync pull skip (404): ${batch[k].path}`);
            continue;
          }
          throw new Error(outcome);
        }
      }

      // 拉取/推送完成后重新收集本地条目：新拉取的文件需进入清单与基线，
      // 否则清单回写会丢失它们，下次同步将重复处理。
      const finalEntries: RemoteEntry[] = await this.collectLocalEntries(vault);
      await provider.putManifest(finalEntries);
      // 基线回写整体事务化：中途失败不得留下「部分文件有基线、部分没有」
      // 的状态，否则缺基线文件下次同步会被误判为冲突。
      const baselineRows: SyncBaselineRow[] = [];
      for (const entry of finalEntries) {
        const row: SyncBaselineRow = new SyncBaselineRow();
        row.path = entry.path;
        row.fileHash = entry.etag;
        row.mtime = entry.mtime;
        row.etag = entry.etag;
        row.serverTag = serverTagMap.get(entry.path) ?? '';
        baselineRows.push(row);
      }
      await SyncStateDao.replaceAll(context, vault.id, baselineRows);

      this.status.state = this.conflicts.length > 0 ? SyncState.CONFLICT : SyncState.SUCCESS;
      this.status.message = this.conflicts.length > 0 ? 'conflict' : 'success';
      this.status.lastSyncAt = Date.now();
      LOG.info(`sync finished, uploads=${this.status.pendingUploads}, ` +
        `downloads=${this.status.pendingDownloads}, conflicts=${this.conflicts.length}`);
    } catch (error) {
      const err = error as BusinessError;
      const code: string = err.code === undefined ? '' : ` (${err.code})`;
      this.status.state = SyncState.FAILED;
      this.status.message = `${err.message}${code}`;
      LOG.error(`sync failed, code=${err.code}, message=${err.message}`);
    } finally {
      await provider.disconnect();
      this.provider = null;
    }
    return this.status;
  }

  /** 收集本地可同步文件（Markdown 笔记与图片附件）。 */
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
      // 全部文件（含二进制附件）统一 sha256 内容哈希。
      // 此前二进制用 mtime~size 做标识，但 mtime 是本机写入时间、跨设备必然
      // 不同，多设备间每轮同步都会互相判定变化而重复拉取同一张图片（乒乓）。
      // 内容哈希跨设备稳定，图片体积可控，开销可接受。
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
      if (!SyncFileFilter.isSyncable(name)) {
        continue;
      }
      const entry: RemoteEntry = new RemoteEntry();
      entry.path = childRelative;
      output.push(entry);
    }
  }

  /** 推送单个文件，并用 PUT 返回的 ETag 更新服务器版本基线。 */
  private async pushEntry(provider: SyncProvider, vault: VaultInfo, entry: RemoteEntry,
    serverTagMap: Map<string, string>): Promise<void> {
    const absolute: string = `${vault.rootPath}/${entry.path}`;
    let tag: string = '';
    if (SyncFileFilter.isMarkdown(entry.path)) {
      tag = await provider.push(absolute, entry);
    } else {
      tag = await provider.pushBinary(absolute, entry);
    }
    if (tag.length > 0) {
      serverTagMap.set(entry.path, tag);
    }
  }

  /** 拉取单个远端新文件：成功返回 null，失败返回错误消息。 */
  private async pullRemote(provider: SyncProvider, vault: VaultInfo, remote: RemoteEntry,
    context: common.Context): Promise<string | null> {
    try {
      await this.pullEntry(provider, vault, remote, context);
      this.status.pendingDownloads++;
      return null;
    } catch (error) {
      const err = error as BusinessError;
      return err.message ?? '';
    }
  }

  private async pullEntry(provider: SyncProvider, vault: VaultInfo, entry: RemoteEntry,
    context: common.Context): Promise<void> {
    const absolute: string = `${vault.rootPath}/${entry.path}`;
    const folder: string = absolute.substring(0, absolute.lastIndexOf('/'));
    if (!fileIo.accessSync(folder)) {
      fileIo.mkdirSync(folder, true);
    }
    // 覆盖已有本地笔记前保留历史快照：pull 中断/异常时旧内容可从
    // .history 找回，避免损坏文件被下一轮同步推上去覆盖唯一完好副本。
    if (SyncFileFilter.isMarkdown(entry.path) && fileIo.accessSync(absolute)) {
      await FileHistory.snapshot(context, vault, entry.path);
    }
    if (SyncFileFilter.isMarkdown(entry.path)) {
      await provider.pull(entry, absolute);
      return;
    }
    await provider.pullBinary(entry, absolute);
  }

  private async resolveConflict(provider: SyncProvider, vault: VaultInfo, local: RemoteEntry,
    remote: RemoteEntry, serverTagMap: Map<string, string>): Promise<void> {
    // 二进制附件不做冲突合并：直接以本地为准覆盖远端（local-wins）。
    if (!SyncFileFilter.isMarkdown(local.path)) {
      LOG.info(`sync conflict (binary, local wins): ${local.path}`);
      await this.pushEntry(provider, vault, local, serverTagMap);
      this.status.pendingUploads++;
      return;
    }
    const conflict: SyncConflict = new SyncConflict();
    conflict.path = local.path;
    conflict.localHash = local.etag;
    conflict.remoteHash = remote.etag;
    // 冲突副本必须保存「远端版本」：从远端拉取真实内容。
    // 此前误用本地文件内容充当远端内容，导致冲突副本与本地完全相同、
    // 远端版本被 push 覆盖后永久丢失。
    const remoteContent: string = await provider.readRemote(local.path);
    conflict.conflictPath = await ConflictResolver.saveCopy(vault, local.path, remoteContent);
    this.conflicts.push(conflict);
    await this.pushEntry(provider, vault, local, serverTagMap);
    this.status.pendingUploads++;
  }
}
