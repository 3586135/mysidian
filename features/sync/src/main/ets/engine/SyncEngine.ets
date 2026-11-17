import { fileIo, hash } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { RemoteEntry, RemoteTrashStatus, SyncConfig, SyncConflict, SyncFileFilter, SyncPathGuard,
  SyncPlanSummary, SyncProvider, SyncSafetyReason, SyncState, SyncStatus, VaultInfo } from '@ohos/domain';
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
 * 双向同步决策枚举。
 */
export enum SyncDecision {
  NONE = 'none',
  PUSH_NEW = 'pushNew',
  PUSH_CHANGED = 'pushChanged',
  PULL_NEW = 'pullNew',
  PULL_CHANGED = 'pullChanged',
  PULL_EXTERNAL = 'pullExternal',
  TRASH_REMOTE = 'trashRemote',
  SKIP_DELETED_LOCAL = 'skipDeletedLocal',
  CONFLICT = 'conflict',
  CHECK_CONTENT = 'checkContent'
}

/** 干跑阶段归类后的冲突待处理项。 */
class PlannedConflictItem {
  local: RemoteEntry = new RemoteEntry();
  remote: RemoteEntry = new RemoteEntry();
  preloadedRemoteText: string | null = null;
  preloadedBinaryTempPath: string = '';
}

/** 单轮同步执行期增量进展追踪（支持部分失败断点续传）。 */
class SyncExecutionProgress {
  succeededUploads: Set<string> = new Set<string>();
  succeededPulls: Set<string> = new Set<string>();
  succeededTrashes: Set<string> = new Set<string>();
  resolvedConflicts: Set<string> = new Set<string>();
  fatalError: string = '';
  itemErrors: string[] = [];

  hasAnyProgress(): boolean {
    return this.succeededUploads.size > 0 || this.succeededPulls.size > 0 ||
      this.succeededTrashes.size > 0 || this.resolvedConflicts.size > 0;
  }

  hasErrors(): boolean {
    return this.fatalError.length > 0 || this.itemErrors.length > 0;
  }
}

/** 干跑阶段归类后的完整执行计划。 */
class SyncExecutionPlan {
  targetKey: string = '';
  targetChanged: boolean = false;
  rawBaselines: Map<string, SyncBaseline> = new Map<string, SyncBaseline>();
  baselines: Map<string, SyncBaseline> = new Map<string, SyncBaseline>();
  ignoreRules: string[] = [];
  uploads: RemoteEntry[] = [];
  pulls: RemoteEntry[] = [];
  conflicts: PlannedConflictItem[] = [];
  trashes: RemoteEntry[] = [];
  keptLocalDeleted: RemoteEntry[] = [];
  verifiedEqualEntries: RemoteEntry[] = [];
  serverTagMap: Map<string, string> = new Map<string, string>();
  summary: SyncPlanSummary = new SyncPlanSummary();
}

/**
 * 双向同步引擎（Obsidian 共存安全版）。
 *
 * 核心保障：
 * 1. 先规划后执行：所有上传/下载/软删除/冲突在只读阶段分类完毕，触发安全闸门时在零远端变更前暂停确认；
 * 2. 禁止裸 HTTP DELETE：本地删除通过 WebDAV MOVE 移入远端 `.trash/`；不支持 MOVE 时写本地墓碑跳过并保留远端；
 * 3. 远端优先冲突保护：发现冲突或内容分歧时不自动推送覆盖远端，仅在本地保留去重后的冲突副本，由用户确认后再覆写；
 * 4. 远端目标绑定：`targetKey = serverUrl|remoteRoot` 变更时重置旧基线并要求确认，杜绝切换目录误删 Obsidian 文件。
 */
export class SyncEngine {
  /** 单轮触发批量软删除确认的数量阈值（.trash/ 软删除可恢复，放宽至 10 以适配常规文件夹整理）。 */
  public static readonly BULK_TRASH_COUNT_THRESHOLD: number = 10;
  /** 单轮触发批量软删除确认的比例阈值（百分比，按基线总数 >= 10 启用）。 */
  public static readonly BULK_TRASH_PERCENT_THRESHOLD: number = 30;
  private static readonly IGNORE_FILE: string = '.mysidianignore';

  private provider: SyncProvider | null = null;
  private status: SyncStatus = new SyncStatus();
  private conflicts: SyncConflict[] = [];
  private pendingPlan: SyncPlanSummary = new SyncPlanSummary();

  public getStatus(): SyncStatus {
    return this.status;
  }

  public getConflicts(): SyncConflict[] {
    return this.conflicts;
  }

  public getPendingPlan(): SyncPlanSummary {
    return this.pendingPlan;
  }

  /**
   * 执行一次同步（先干跑规划并检查安全闸门，通过后再落盘与推送）。
   * @param confirmed 是否已由用户确认危险操作（首次非空合并 / 切换远端目标 / 批量移入回收站）
   */
  public async sync(vault: VaultInfo, config: SyncConfig, context: common.Context,
    confirmed: boolean = false): Promise<SyncStatus> {
    this.status = new SyncStatus();
    this.status.state = SyncState.SYNCING;
    this.status.message = 'syncing';
    this.conflicts = [];
    this.pendingPlan = new SyncPlanSummary();
    const provider: SyncProvider = new WebDavProvider();
    this.provider = provider;
    let plan: SyncExecutionPlan | null = null;
    const progress: SyncExecutionProgress = new SyncExecutionProgress();
    try {
      await provider.connect(config);
      plan = await this.buildExecutionPlan(provider, vault, config, context, confirmed);
      this.pendingPlan = plan.summary;
      if (plan.summary.requiresConfirmation) {
        SyncEngine.cleanupTempBinaryPaths(plan.conflicts);
        this.status.state = SyncState.PAUSED;
        this.status.safetyReason = plan.summary.reason;
        this.status.message = plan.summary.reason;
        LOG.warn(`sync paused by safety gate: reason=${plan.summary.reason}, ` +
          `up=${plan.summary.uploads}, down=${plan.summary.downloads}, ` +
          `trash=${plan.summary.trashes}, conflict=${plan.summary.conflicts}`);
        return this.status;
      }

      await this.executeUploads(provider, vault, plan.uploads, plan.serverTagMap, progress);
      if (progress.fatalError.length === 0) {
        await this.executeConflicts(provider, vault, plan.conflicts, progress);
      }
      if (progress.fatalError.length === 0) {
        await this.executeRemoteTrashes(provider, plan.trashes, plan.keptLocalDeleted, progress);
      }
      if (progress.fatalError.length === 0) {
        await this.executePulls(provider, vault, plan.pulls, context, progress);
      }

      if (!progress.hasErrors()) {
        await this.persistSyncState(provider, vault, context, plan);
        this.status.state = this.conflicts.length > 0 ? SyncState.CONFLICT : SyncState.SUCCESS;
        this.status.message = this.conflicts.length > 0 ? 'conflict' : 'success';
        this.status.lastSyncAt = Date.now();
        LOG.info(`sync finished, uploads=${this.status.pendingUploads}, ` +
          `downloads=${this.status.pendingDownloads}, trashed=${this.status.pendingTrashed}, ` +
          `skippedDel=${this.status.skippedRemoteDeletes}, conflicts=${this.conflicts.length}`);
      } else {
        // 上传阶段致命失败时 executeConflicts 被整体跳过，预载的冲突
        // 临时文件无人清理；此清理幂等（字段清空后不再重复删除）。
        SyncEngine.cleanupTempBinaryPaths(plan.conflicts);
        if (progress.hasAnyProgress() || plan.keptLocalDeleted.length > 0) {
          await this.persistPartialCheckpoint(provider, vault, context, plan, progress);
        }
        this.status.state = SyncState.FAILED;
        this.status.message = SyncEngine.summarizeProgressErrors(progress);
        LOG.error(`sync partial failure: ${this.status.message}`);
      }
    } catch (error) {
      if (plan !== null) {
        SyncEngine.cleanupTempBinaryPaths(plan.conflicts);
        if (progress.hasAnyProgress() || plan.keptLocalDeleted.length > 0) {
          await this.persistPartialCheckpoint(provider, vault, context, plan, progress);
        }
      }
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

  /**
   * 仅当用户在冲突界面明确点击「保留本地并覆盖远端」时调用：
   * 推送本地文件到远端、增量更新 `.mysidian/manifest.json`，并把该路径基线收敛为 synced。
   */
  public async pushConflictKeepLocal(vault: VaultInfo, config: SyncConfig,
    conflict: SyncConflict, context: common.Context): Promise<void> {
    if (!SyncPathGuard.isSafeSyncPath(conflict.path)) {
      throw new Error(`受保护或非同步路径不可推送: ${conflict.path}`);
    }
    const localAbs: string = `${vault.rootPath}/${conflict.path}`;
    if (!fileIo.accessSync(localAbs)) {
      throw new Error(`本地文件不存在: ${conflict.path}`);
    }
    const stat = fileIo.statSync(localAbs);
    const localEntry: RemoteEntry = new RemoteEntry();
    localEntry.path = conflict.path;
    localEntry.size = stat.size;
    localEntry.mtime = stat.mtime;
    localEntry.etag = await hash.hash(localAbs, 'sha256');
    localEntry.isDir = false;

    const provider: SyncProvider = new WebDavProvider();
    const serverTagMap: Map<string, string> = new Map<string, string>();
    try {
      await provider.connect(config);
      await this.pushEntry(provider, vault, localEntry, serverTagMap);
      await provider.patchManifestEntry(localEntry);
      const row: SyncBaselineRow = new SyncBaselineRow();
      row.path = localEntry.path;
      row.fileHash = localEntry.etag;
      row.mtime = localEntry.mtime;
      row.size = localEntry.size;
      row.etag = localEntry.etag;
      row.serverTag = serverTagMap.get(localEntry.path) ?? '';
      row.state = 'synced';
      row.targetKey = SyncEngine.buildTargetKey(config.serverUrl, config.remoteRoot);
      await SyncStateDao.upsertRow(context, vault.id, row);
      LOG.info(`conflict resolved (keep local pushed): ${conflict.path}`);
    } finally {
      await provider.disconnect();
    }
  }

  /** 将「采用远端」手动解决后的路径基线立即收敛为 synced。 */
  public static async markConflictUseRemoteResolved(vault: VaultInfo, config: SyncConfig,
    conflict: SyncConflict, context: common.Context): Promise<void> {
    const localAbs: string = `${vault.rootPath}/${conflict.path}`;
    if (!fileIo.accessSync(localAbs)) {
      return;
    }
    const stat = fileIo.statSync(localAbs);
    const fileHash: string = await hash.hash(localAbs, 'sha256');
    const row: SyncBaselineRow = new SyncBaselineRow();
    row.path = conflict.path;
    row.fileHash = fileHash;
    row.mtime = stat.mtime;
    row.size = stat.size;
    row.etag = fileHash;
    row.serverTag = conflict.remoteServerTag;
    row.state = 'synced';
    row.targetKey = SyncEngine.buildTargetKey(config.serverUrl, config.remoteRoot);
    await SyncStateDao.upsertRow(context, vault.id, row);
  }

  /** 只读规划阶段：比对本地、远端与基线，分类所有操作并检查安全闸门。 */
  private async buildExecutionPlan(provider: SyncProvider, vault: VaultInfo,
    config: SyncConfig, context: common.Context, confirmed: boolean): Promise<SyncExecutionPlan> {
    const plan: SyncExecutionPlan = new SyncExecutionPlan();
    plan.targetKey = SyncEngine.buildTargetKey(config.serverUrl, config.remoteRoot);
    plan.rawBaselines = await SyncStateDao.baselines(context, vault.id);
    plan.targetChanged = !SyncEngine.isBaselineTargetCompatible(plan.rawBaselines, plan.targetKey);
    plan.baselines = plan.targetChanged ? new Map<string, SyncBaseline>() : plan.rawBaselines;
    plan.ignoreRules = SyncEngine.loadIgnoreRules(vault.rootPath);

    const remoteEntries: RemoteEntry[] = await provider.list('');
    const localEntries: RemoteEntry[] = await this.collectLocalEntries(
      vault, plan.baselines, plan.ignoreRules);
    LOG.info(`sync plan: local=${localEntries.length}, remote=${remoteEntries.length}, ` +
      `targetChanged=${plan.targetChanged}`);

    const remoteMap: Map<string, RemoteEntry> = new Map<string, RemoteEntry>();
    for (const entry of remoteEntries) {
      if (SyncPathGuard.isIgnoredByRules(entry.path, plan.ignoreRules)) {
        continue;
      }
      remoteMap.set(entry.path, entry);
      if (entry.serverTag.length > 0) {
        plan.serverTagMap.set(entry.path, entry.serverTag);
      }
    }
    const localMap: Map<string, RemoteEntry> = new Map<string, RemoteEntry>();
    for (const entry of localEntries) {
      localMap.set(entry.path, entry);
    }

    for (const local of localEntries) {
      const remote: RemoteEntry | undefined = remoteMap.get(local.path);
      const baseline: SyncBaseline | undefined = plan.baselines.get(local.path);
      const decision: SyncDecision = SyncEngine.decideLocalEntry(
        local, remote, baseline, SyncFileFilter.isMarkdown(local.path));
      if (decision === SyncDecision.NONE) {
        continue;
      }
      if (decision === SyncDecision.PUSH_NEW || decision === SyncDecision.PUSH_CHANGED) {
        plan.uploads.push(local);
        continue;
      }
      if ((decision === SyncDecision.PULL_EXTERNAL || decision === SyncDecision.PULL_CHANGED) &&
        remote !== undefined) {
        plan.pulls.push(remote);
        continue;
      }
      if (decision === SyncDecision.CHECK_CONTENT && remote !== undefined) {
        try {
          const remoteText: string = await provider.readRemote(local.path);
          const localAbs: string = `${vault.rootPath}/${local.path}`;
          const localText: string = fileIo.readTextSync(localAbs);
          if (remoteText === localText) {
            plan.verifiedEqualEntries.push(local);
            continue;
          }
          const item: PlannedConflictItem = new PlannedConflictItem();
          item.local = local;
          item.remote = remote;
          item.preloadedRemoteText = remoteText;
          plan.conflicts.push(item);
        } catch (error) {
          const err = error as BusinessError;
          if ((err.message ?? '').includes('404')) {
            plan.uploads.push(local);
            continue;
          }
          throw error as Error;
        }
        continue;
      }
      if (decision === SyncDecision.CONFLICT && remote !== undefined) {
        const isMd: boolean = SyncFileFilter.isMarkdown(local.path);
        if (!isMd && remote.etag.length === 0 &&
          (remote.size === 0 || remote.size === local.size)) {
          const preloadedTemp: string | null = await this.checkBinaryEqualOrTemp(
            provider, vault, local, remote);
          if (preloadedTemp === null) {
            plan.verifiedEqualEntries.push(local);
            continue;
          }
          const item: PlannedConflictItem = new PlannedConflictItem();
          item.local = local;
          item.remote = remote;
          item.preloadedBinaryTempPath = preloadedTemp;
          plan.conflicts.push(item);
          continue;
        }
        const item: PlannedConflictItem = new PlannedConflictItem();
        item.local = local;
        item.remote = remote;
        plan.conflicts.push(item);
      }
    }

    for (const remote of remoteEntries) {
      if (SyncPathGuard.isIgnoredByRules(remote.path, plan.ignoreRules) ||
        localMap.has(remote.path)) {
        continue;
      }
      const baseline: SyncBaseline | undefined = plan.baselines.get(remote.path);
      const remoteDecision: SyncDecision = SyncEngine.decideRemoteOnly(
        remote, baseline, plan.targetKey);
      if (remoteDecision === SyncDecision.TRASH_REMOTE) {
        plan.trashes.push(remote);
      } else if (remoteDecision === SyncDecision.SKIP_DELETED_LOCAL) {
        plan.keptLocalDeleted.push(remote);
      } else {
        plan.pulls.push(remote);
      }
    }

    let syncedBaselineCount: number = 0;
    plan.baselines.forEach((b: SyncBaseline): void => {
      if (b.state !== 'local_deleted') {
        syncedBaselineCount++;
      }
    });

    const plannedChanges: number = plan.uploads.length + plan.pulls.length +
      plan.trashes.length + plan.conflicts.length;
    const plannedRiskyChanges: number = plan.uploads.length + plan.trashes.length +
      plan.conflicts.length;
    const reason: SyncSafetyReason = SyncEngine.evaluateSafetyGate(
      localEntries.length, remoteMap.size, plan.baselines.size,
      plan.trashes.length, syncedBaselineCount, plan.targetChanged,
      plannedChanges, plannedRiskyChanges);
    const summary: SyncPlanSummary = new SyncPlanSummary();
    summary.uploads = plan.uploads.length;
    summary.downloads = plan.pulls.length;
    summary.conflicts = plan.conflicts.length;
    summary.trashes = plan.trashes.length;
    summary.reason = reason;
    summary.requiresConfirmation = reason !== SyncSafetyReason.NONE && !confirmed;
    summary.samplePaths = SyncEngine.collectSamplePaths(plan);
    plan.summary = summary;
    return plan;
  }

  private static collectSamplePaths(plan: SyncExecutionPlan): string[] {
    const out: string[] = [];
    const limit: number = 5;
    for (const item of plan.trashes) {
      if (out.length >= limit) {
        return out;
      }
      out.push(item.path);
    }
    for (const item of plan.conflicts) {
      if (out.length >= limit) {
        return out;
      }
      out.push(item.local.path);
    }
    for (const item of plan.uploads) {
      if (out.length >= limit) {
        return out;
      }
      out.push(item.path);
    }
    return out;
  }

  private async executeUploads(provider: SyncProvider, vault: VaultInfo,
    uploads: RemoteEntry[], serverTagMap: Map<string, string>,
    progress: SyncExecutionProgress): Promise<void> {
    for (const local of uploads) {
      if (progress.fatalError.length > 0) {
        return;
      }
      try {
        LOG.info(`sync push: ${local.path}`);
        await this.pushEntry(provider, vault, local, serverTagMap);
        this.status.pendingUploads++;
        progress.succeededUploads.add(local.path);
      } catch (error) {
        const msg: string = SyncEngine.errorMessageOf(error);
        LOG.warn(`sync upload failed (${local.path}): ${msg}`);
        if (SyncEngine.isFatalSyncError(msg)) {
          progress.fatalError = msg;
          return;
        }
        progress.itemErrors.push(`${local.path}: ${msg}`);
      }
    }
  }

  private async executeConflicts(provider: SyncProvider, vault: VaultInfo,
    conflicts: PlannedConflictItem[], progress: SyncExecutionProgress): Promise<void> {
    for (const item of conflicts) {
      if (progress.fatalError.length > 0) {
        SyncEngine.removeTempFileSafe(item.preloadedBinaryTempPath);
        item.preloadedBinaryTempPath = '';
        continue;
      }
      try {
        LOG.info(`sync conflict (remote preserved): ${item.local.path}`);
        await this.resolveConflictRemoteFirst(
          provider, vault, item.local, item.remote,
          item.preloadedRemoteText, item.preloadedBinaryTempPath);
        item.preloadedBinaryTempPath = '';
        progress.resolvedConflicts.add(item.local.path);
      } catch (error) {
        SyncEngine.removeTempFileSafe(item.preloadedBinaryTempPath);
        item.preloadedBinaryTempPath = '';
        const msg: string = SyncEngine.errorMessageOf(error);
        LOG.warn(`sync conflict backup failed (${item.local.path}): ${msg}`);
        if (SyncEngine.isFatalSyncError(msg)) {
          // 不立即 return：让循环继续走到顶部 fatalError 分支，
          // 逐项清理剩余条目预载的冲突临时文件，避免遗留 conflicts/.tmp_*。
          progress.fatalError = msg;
          continue;
        }
        progress.itemErrors.push(`${item.local.path}: ${msg}`);
      }
    }
  }

  private async executeRemoteTrashes(provider: SyncProvider, trashes: RemoteEntry[],
    keptLocalDeleted: RemoteEntry[], progress: SyncExecutionProgress): Promise<void> {
    const stamp: string = SyncEngine.trashTimestamp();
    let seq: number = 0;
    for (const deleted of trashes) {
      if (progress.fatalError.length > 0) {
        return;
      }
      const trashPath: string = SyncEngine.buildRemoteTrashPath(deleted.path, stamp, seq);
      seq++;
      try {
        LOG.info(`sync trash remote -> ${trashPath}: ${deleted.path}`);
        const outcome: RemoteTrashStatus = await provider.trashRemote(deleted.path, trashPath);
        if (outcome === RemoteTrashStatus.MOVED || outcome === RemoteTrashStatus.NOT_FOUND) {
          if (outcome === RemoteTrashStatus.MOVED) {
            this.status.pendingTrashed++;
          }
          progress.succeededTrashes.add(deleted.path);
        } else if (outcome === RemoteTrashStatus.UNSUPPORTED) {
          this.status.skippedRemoteDeletes++;
          keptLocalDeleted.push(deleted);
        }
      } catch (error) {
        const msg: string = SyncEngine.errorMessageOf(error);
        LOG.warn(`sync trash failed (${deleted.path}): ${msg}`);
        if (SyncEngine.isFatalSyncError(msg)) {
          progress.fatalError = msg;
          return;
        }
        progress.itemErrors.push(`${deleted.path}: ${msg}`);
      }
    }
  }

  private async executePulls(provider: SyncProvider, vault: VaultInfo, pulls: RemoteEntry[],
    context: common.Context, progress: SyncExecutionProgress): Promise<void> {
    if (pulls.length > 0) {
      LOG.info(`sync pull pending: ${pulls.length} files`);
    }
    for (let i = 0; i < pulls.length; i += PULL_CONCURRENCY) {
      if (progress.fatalError.length > 0) {
        return;
      }
      const batch: RemoteEntry[] = pulls.slice(i, i + PULL_CONCURRENCY);
      const outcomes: Array<string | null> = await Promise.all(batch.map(
        (remote: RemoteEntry): Promise<string | null> => {
          return this.pullRemote(provider, vault, remote, context);
        }));
      for (let k = 0; k < outcomes.length; k++) {
        const outcome: string | null = outcomes[k];
        const remoteItem: RemoteEntry = batch[k];
        if (outcome === null) {
          progress.succeededPulls.add(remoteItem.path);
          continue;
        }
        if (outcome.includes('404')) {
          LOG.warn(`sync pull skip (404): ${remoteItem.path}`);
          continue;
        }
        LOG.warn(`sync pull failed (${remoteItem.path}): ${outcome}`);
        if (SyncEngine.isFatalSyncError(outcome)) {
          progress.fatalError = outcome;
          return;
        }
        progress.itemErrors.push(`${remoteItem.path}: ${outcome}`);
      }
    }
  }

  private async persistSyncState(provider: SyncProvider, vault: VaultInfo,
    context: common.Context, plan: SyncExecutionPlan): Promise<void> {
    const conflictRemoteMap: Map<string, RemoteEntry> = new Map<string, RemoteEntry>();
    for (const item of plan.conflicts) {
      conflictRemoteMap.set(item.local.path, item.remote);
    }

    const finalEntries: RemoteEntry[] = await this.collectLocalEntries(
      vault, plan.baselines, plan.ignoreRules);
    const finalLocalMap: Set<string> = new Set<string>();
    const manifestEntries: RemoteEntry[] = [];
    for (const entry of finalEntries) {
      finalLocalMap.add(entry.path);
      const conflictRemote: RemoteEntry | undefined = conflictRemoteMap.get(entry.path);
      if (conflictRemote !== undefined) {
        // 冲突期间保持远端原版本不被本地覆盖：清单仅保留远端原有哈希，禁止写入本地尚未推送的哈希。
        if (conflictRemote.etag.length > 0) {
          manifestEntries.push(conflictRemote);
        }
      } else {
        manifestEntries.push(entry);
      }
    }

    await provider.putManifest(manifestEntries);

    const baselineRows: SyncBaselineRow[] = [];
    for (const entry of finalEntries) {
      const conflictRemote: RemoteEntry | undefined = conflictRemoteMap.get(entry.path);
      if (conflictRemote !== undefined) {
        const prev: SyncBaseline | undefined = plan.baselines.get(entry.path);
        baselineRows.push(SyncEngine.buildConflictBaselineRow(entry.path, prev, plan.targetKey));
        continue;
      }
      baselineRows.push(SyncEngine.buildSyncedBaselineRow(
        entry.path, entry.etag, entry.mtime, entry.size,
        plan.serverTagMap.get(entry.path) ?? '', plan.targetKey));
    }

    for (const deleted of plan.keptLocalDeleted) {
      if (finalLocalMap.has(deleted.path)) {
        continue;
      }
      baselineRows.push(SyncEngine.buildLocalDeletedRow(deleted, plan.targetKey));
    }

    await SyncStateDao.replaceAll(context, vault.id, baselineRows);
  }

  /**
   * 增量断点落盘：在个别文件失败时仍保存本轮已成功上传/拉取/软删/校验一致的基线与清单，
   * 避免下次重试重头重复比对或误触发首次合并暂停。
   */
  private async persistPartialCheckpoint(provider: SyncProvider, vault: VaultInfo,
    context: common.Context, plan: SyncExecutionPlan, progress: SyncExecutionProgress): Promise<void> {
    try {
      const rowMap: Map<string, SyncBaselineRow> = new Map<string, SyncBaselineRow>();
      plan.baselines.forEach((baseline: SyncBaseline, path: string): void => {
        const row: SyncBaselineRow = new SyncBaselineRow();
        row.path = path;
        row.fileHash = baseline.fileHash;
        row.mtime = baseline.mtime;
        row.size = baseline.size;
        row.etag = baseline.fileHash;
        row.serverTag = baseline.serverTag;
        row.state = baseline.state.length > 0 ? baseline.state : 'synced';
        row.targetKey = plan.targetKey.length > 0 ? plan.targetKey : baseline.targetKey;
        rowMap.set(path, row);
      });

      progress.succeededTrashes.forEach((path: string): void => {
        rowMap.delete(path);
      });

      for (const eq of plan.verifiedEqualEntries) {
        rowMap.set(eq.path, SyncEngine.buildSyncedBaselineRow(
          eq.path, eq.etag, eq.mtime, eq.size,
          plan.serverTagMap.get(eq.path) ?? '', plan.targetKey));
      }

      for (const local of plan.uploads) {
        if (!progress.succeededUploads.has(local.path)) {
          continue;
        }
        rowMap.set(local.path, SyncEngine.buildSyncedBaselineRow(
          local.path, local.etag, local.mtime, local.size,
          plan.serverTagMap.get(local.path) ?? '', plan.targetKey));
      }

      for (const remote of plan.pulls) {
        if (!progress.succeededPulls.has(remote.path)) {
          continue;
        }
        const abs: string = `${vault.rootPath}/${remote.path}`;
        if (!fileIo.accessSync(abs)) {
          continue;
        }
        const stat = fileIo.statSync(abs);
        const fileHash: string = await hash.hash(abs, 'sha256');
        rowMap.set(remote.path, SyncEngine.buildSyncedBaselineRow(
          remote.path, fileHash, stat.mtime, stat.size,
          plan.serverTagMap.get(remote.path) ?? remote.serverTag, plan.targetKey));
      }

      for (const item of plan.conflicts) {
        if (!progress.resolvedConflicts.has(item.local.path)) {
          continue;
        }
        const prev: SyncBaseline | undefined = plan.baselines.get(item.local.path);
        rowMap.set(item.local.path, SyncEngine.buildConflictBaselineRow(
          item.local.path, prev, plan.targetKey));
      }

      for (const deleted of plan.keptLocalDeleted) {
        if (!rowMap.has(deleted.path)) {
          rowMap.set(deleted.path, SyncEngine.buildLocalDeletedRow(deleted, plan.targetKey));
        }
      }

      const rows: SyncBaselineRow[] = [];
      const manifestEntries: RemoteEntry[] = [];
      rowMap.forEach((row: SyncBaselineRow): void => {
        rows.push(row);
        if (row.state === 'synced' && row.fileHash.length > 0) {
          const entry: RemoteEntry = new RemoteEntry();
          entry.path = row.path;
          entry.etag = row.fileHash;
          entry.mtime = row.mtime;
          entry.size = row.size;
          entry.serverTag = row.serverTag;
          entry.isDir = false;
          manifestEntries.push(entry);
        }
      });

      await SyncStateDao.replaceAll(context, vault.id, rows);
      if (progress.fatalError.length === 0 && manifestEntries.length > 0) {
        try {
          await provider.putManifest(manifestEntries);
        } catch (manifestErr) {
          LOG.warn('checkpoint manifest update skipped');
        }
      }
      LOG.info(`partial checkpoint saved: rows=${rows.length}`);
    } catch (error) {
      LOG.warn('save partial checkpoint failed');
    }
  }

  private static buildSyncedBaselineRow(path: string, fileHash: string, mtime: number,
    size: number, serverTag: string, targetKey: string): SyncBaselineRow {
    const row: SyncBaselineRow = new SyncBaselineRow();
    row.path = path;
    row.fileHash = fileHash;
    row.mtime = mtime;
    row.size = size;
    row.etag = fileHash;
    row.serverTag = serverTag;
    row.state = 'synced';
    row.targetKey = targetKey;
    return row;
  }

  private static buildConflictBaselineRow(path: string, prev: SyncBaseline | undefined,
    targetKey: string): SyncBaselineRow {
    const row: SyncBaselineRow = new SyncBaselineRow();
    row.path = path;
    row.fileHash = prev !== undefined ? prev.fileHash : '';
    row.mtime = prev !== undefined ? prev.mtime : 0;
    row.size = prev !== undefined ? prev.size : 0;
    row.etag = prev !== undefined ? prev.fileHash : '';
    row.serverTag = prev !== undefined ? prev.serverTag : '';
    row.state = 'conflict';
    row.targetKey = targetKey;
    return row;
  }

  private static buildLocalDeletedRow(deleted: RemoteEntry, targetKey: string): SyncBaselineRow {
    const row: SyncBaselineRow = new SyncBaselineRow();
    row.path = deleted.path;
    row.fileHash = deleted.etag;
    row.mtime = deleted.mtime;
    row.size = deleted.size;
    row.etag = deleted.etag;
    row.serverTag = deleted.serverTag;
    row.state = 'local_deleted';
    row.targetKey = targetKey;
    return row;
  }

  /** 生成规范化远端目标绑定标识：`normalizedUrl|normalizedRoot`（协议与主机名小写化）。 */
  public static buildTargetKey(serverUrl: string, remoteRoot: string): string {
    let url: string = serverUrl.replace(/\s+/g, '');
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    const schemeIdx: number = url.indexOf('://');
    if (schemeIdx > 0) {
      const scheme: string = url.substring(0, schemeIdx).toLowerCase();
      const rest: string = url.substring(schemeIdx + 3);
      const slashIdx: number = rest.indexOf('/');
      if (slashIdx < 0) {
        url = `${scheme}://${rest.toLowerCase()}`;
      } else {
        url = `${scheme}://${rest.substring(0, slashIdx).toLowerCase()}${rest.substring(slashIdx)}`;
      }
    }
    const segs: string[] = remoteRoot.trim().replace(/\\/g, '/').split('/')
      .filter((s: string): boolean => s.length > 0);
    return `${url}|${segs.join('/')}`;
  }

  /** 检查现有基线是否与当前 WebDAV 目标一致（空 targetKey 视为升级前遗留数据，平滑过渡）。 */
  public static isBaselineTargetCompatible(baselines: Map<string, SyncBaseline>,
    currentTargetKey: string): boolean {
    if (currentTargetKey.length === 0) {
      return true;
    }
    let compatible: boolean = true;
    baselines.forEach((baseline: SyncBaseline): void => {
      if (baseline.targetKey.length > 0 && baseline.targetKey !== currentTargetKey) {
        compatible = false;
      }
    });
    return compatible;
  }

  /**
   * 评估同步安全闸门：
   * 0. 若两端零差异（无上传、下载、软删与冲突），无需拦截，直接无感对齐基线；
   * 1. 更换了 WebDAV 服务器或远端目录且远端非空并存在实际变更；
   * 2. 无公共基线时把非空本地库连接到非空远端库，且存在写入远端或冲突风险（仅纯增量拉取时静默通过）；
   * 3. 单轮待移入远端 `.trash/` 的文件数量或占比超过安全阈值。
   */
  public static evaluateSafetyGate(localCount: number, remoteCount: number,
    effectiveBaselineCount: number, pendingTrashCount: number, syncedBaselineCount: number,
    targetChanged: boolean, plannedChanges: number = -1,
    plannedRiskyChanges: number = -1): SyncSafetyReason {
    if (plannedChanges === 0) {
      return SyncSafetyReason.NONE;
    }
    if (targetChanged && remoteCount > 0) {
      return SyncSafetyReason.TARGET_CHANGED;
    }
    if (effectiveBaselineCount === 0 && localCount > 0 && remoteCount > 0 &&
      plannedRiskyChanges !== 0) {
      return SyncSafetyReason.INITIAL_NON_EMPTY_MERGE;
    }
    if (pendingTrashCount >= SyncEngine.BULK_TRASH_COUNT_THRESHOLD) {
      return SyncSafetyReason.BULK_TRASH;
    }
    if (syncedBaselineCount >= 10 &&
      pendingTrashCount * 100 >= syncedBaselineCount * SyncEngine.BULK_TRASH_PERCENT_THRESHOLD) {
      return SyncSafetyReason.BULK_TRASH;
    }
    return SyncSafetyReason.NONE;
  }

  /** 生成安全唯一的远端 `.trash/` 目标相对路径（`.trash/<stamp>_<seq>_<basename>`）。 */
  public static buildRemoteTrashPath(relativePath: string, stamp: string, seq: number = 0): string {
    const slash: number = relativePath.lastIndexOf('/');
    const baseName: string = slash < 0 ? relativePath : relativePath.substring(slash + 1);
    const seqPart: string = seq > 0 ? `${seq}_` : '';
    return `.trash/${stamp}_${seqPart}${baseName}`;
  }

  private static loadIgnoreRules(vaultRoot: string): string[] {
    const ignorePath: string = `${vaultRoot}/${SyncEngine.IGNORE_FILE}`;
    try {
      if (fileIo.accessSync(ignorePath)) {
        const content: string = fileIo.readTextSync(ignorePath);
        return SyncPathGuard.parseIgnoreRules(content);
      }
    } catch (error) {
      LOG.warn(`read ${SyncEngine.IGNORE_FILE} failed`);
    }
    return [];
  }

  /**
   * 收集本地可同步文件（Markdown 笔记与图片附件）。
   * 传入上次同步的基线时，mtime 与 size 均未变化的文件直接复用基线哈希，
   * 不再重算 sha256（大库的主要同步耗时）。
   */
  private async collectLocalEntries(vault: VaultInfo,
    baselines: Map<string, SyncBaseline> = new Map<string, SyncBaseline>(),
    ignoreRules: string[] = []): Promise<RemoteEntry[]> {
    const entries: RemoteEntry[] = [];
    this.collectFiles(vault.rootPath, '', entries, ignoreRules);
    const result: RemoteEntry[] = [];
    for (const entry of entries) {
      const absolute: string = `${vault.rootPath}/${entry.path}`;
      const stat = fileIo.statSync(absolute);
      const item: RemoteEntry = new RemoteEntry();
      item.path = entry.path;
      item.size = stat.size;
      item.mtime = stat.mtime;
      const cached: SyncBaseline | undefined = baselines.get(entry.path);
      if (cached !== undefined && cached.state === 'synced' &&
        SyncEngine.isHashReusable(cached, stat.mtime, stat.size)) {
        item.etag = cached.fileHash;
        item.isDir = false;
        result.push(item);
        continue;
      }
      item.etag = await hash.hash(absolute, 'sha256');
      item.isDir = false;
      result.push(item);
    }
    return result;
  }

  /**
   * 判断基线哈希是否可复用：mtime（秒）与 size 均未变，且文件在上次同步完成
   * 至少 2 秒前就已稳定——排除「同一秒内同尺寸改写」导致的缓存误命中。
   */
  public static isHashReusable(baseline: SyncBaseline, mtime: number, size: number): boolean {
    if (baseline.fileHash.length === 0 || baseline.lastSyncAt <= 0 || baseline.size <= 0) {
      return false;
    }
    if (baseline.mtime !== mtime || baseline.size !== size) {
      return false;
    }
    return mtime + 2 <= Math.floor(baseline.lastSyncAt / 1000);
  }

  /** 对单个本地条目的三方决策（本地 / 远端 / 上次同步基线）。 */
  public static decideLocalEntry(local: RemoteEntry, remote: RemoteEntry | undefined,
    baseline: SyncBaseline | undefined, isMarkdown: boolean = true): SyncDecision {
    if (remote === undefined) {
      return SyncDecision.PUSH_NEW;
    }
    if (remote.etag === local.etag) {
      if (baseline !== undefined && baseline.serverTag.length > 0 &&
        remote.serverTag.length > 0 && remote.serverTag !== baseline.serverTag) {
        return SyncDecision.PULL_EXTERNAL;
      }
      return SyncDecision.NONE;
    }
    if (remote.etag.length === 0) {
      if (baseline !== undefined && baseline.serverTag.length > 0 &&
        remote.serverTag.length > 0 && baseline.serverTag === remote.serverTag) {
        return SyncDecision.NONE;
      }
      if (!isMarkdown) {
        return SyncDecision.CONFLICT;
      }
      return SyncDecision.CHECK_CONTENT;
    }
    if (baseline !== undefined && baseline.fileHash === remote.etag) {
      return SyncDecision.PUSH_CHANGED;
    }
    if (baseline !== undefined && baseline.fileHash === local.etag) {
      return SyncDecision.PULL_CHANGED;
    }
    return SyncDecision.CONFLICT;
  }

  /**
   * 对仅存在于远端（本地不存在）的条目做决策：
   * 1. 无基线 / 基线无相同 targetKey 绑定 / 升级过渡：一律视为远端新增（PULL_NEW），绝不触发删除；
   * 2. 曾记录本地已删墓碑（local_deleted）：仅当远端版本随后被修改时重新拉取，否则跳过不动；
   * 3. 同一目标下已同步过且本地移除：触发移入远端 `.trash/` 软删除（TRASH_REMOTE）。
   */
  public static decideRemoteOnly(remote: RemoteEntry, baseline: SyncBaseline | undefined,
    currentTargetKey: string = ''): SyncDecision {
    if (baseline === undefined) {
      return SyncDecision.PULL_NEW;
    }
    if (baseline.state === 'local_deleted') {
      const hashChanged: boolean = remote.etag.length > 0 && baseline.fileHash.length > 0 &&
        remote.etag !== baseline.fileHash;
      const tagChanged: boolean = remote.serverTag.length > 0 && baseline.serverTag.length > 0 &&
        remote.serverTag !== baseline.serverTag;
      if (hashChanged || tagChanged) {
        return SyncDecision.PULL_NEW;
      }
      return SyncDecision.SKIP_DELETED_LOCAL;
    }
    if (currentTargetKey.length > 0 && baseline.targetKey !== currentTargetKey) {
      return SyncDecision.PULL_NEW;
    }
    return SyncDecision.TRASH_REMOTE;
  }

  private collectFiles(fullPath: string, relativePath: string, output: RemoteEntry[],
    ignoreRules: string[]): void {
    const names: string[] = fileIo.listFileSync(fullPath);
    for (const name of names) {
      const childFull: string = `${fullPath}/${name}`;
      const childRelative: string = relativePath.length === 0 ? name : `${relativePath}/${name}`;
      if (fileIo.statSync(childFull).isDirectory()) {
        if (SyncPathGuard.isIgnoredDirName(name) ||
          SyncPathGuard.isIgnoredByRules(childRelative, ignoreRules)) {
          continue;
        }
        this.collectFiles(childFull, childRelative, output, ignoreRules);
        continue;
      }
      if (!SyncPathGuard.isSafeSyncPath(childRelative) ||
        SyncPathGuard.isIgnoredByRules(childRelative, ignoreRules)) {
        continue;
      }
      const entry: RemoteEntry = new RemoteEntry();
      entry.path = childRelative;
      output.push(entry);
    }
  }

  /** 推送单个文件，并用 PUT 返回的 ETag 更新服务器版本基线；未返回 ETag 时清除旧 tag 防下轮回流拉取。 */
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
    } else {
      serverTagMap.delete(entry.path);
    }
  }

  /** 对无清单哈希的二进制图片下载到临时文件做 sha256 比对：完全一致返回 null，否则返回临时路径供复用。 */
  private async checkBinaryEqualOrTemp(provider: SyncProvider, vault: VaultInfo,
    local: RemoteEntry, remote: RemoteEntry): Promise<string | null> {
    const tempAbs: string = ConflictResolver.prepareBinaryTempPath(vault, local.path);
    try {
      await provider.pullBinary(remote, tempAbs);
      const remoteHash: string = await hash.hash(tempAbs, 'sha256');
      if (remoteHash === local.etag) {
        SyncEngine.removeTempFileSafe(tempAbs);
        return null;
      }
      return tempAbs;
    } catch (error) {
      SyncEngine.removeTempFileSafe(tempAbs);
      throw error as Error;
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
    if (SyncFileFilter.isMarkdown(entry.path) && fileIo.accessSync(absolute)) {
      await FileHistory.snapshot(context, vault, entry.path);
    }
    if (SyncFileFilter.isMarkdown(entry.path)) {
      await provider.pull(entry, absolute);
      return;
    }
    await provider.pullBinary(entry, absolute);
  }

  /**
   * 远端优先冲突处理：保持 WebDAV 远端文件原样不动，仅把远端版本保存为本地去重冲突副本，
   * 等待用户在同步设置中手动对比并明确选择「保留本地并覆盖远端」或「采用远端」。
   */
  private async resolveConflictRemoteFirst(provider: SyncProvider, vault: VaultInfo,
    local: RemoteEntry, remote: RemoteEntry, preloadedRemoteText: string | null,
    preloadedBinaryTempPath: string = ''): Promise<void> {
    const conflict: SyncConflict = new SyncConflict();
    conflict.path = local.path;
    conflict.localHash = local.etag;
    conflict.remoteHash = remote.etag;
    conflict.remoteServerTag = remote.serverTag;

    if (!SyncFileFilter.isMarkdown(local.path)) {
      conflict.isBinary = true;
      const tempAbs: string = preloadedBinaryTempPath.length > 0
        ? preloadedBinaryTempPath : ConflictResolver.prepareBinaryTempPath(vault, local.path);
      if (preloadedBinaryTempPath.length === 0) {
        await provider.pullBinary(remote, tempAbs);
      }
      conflict.conflictPath = await ConflictResolver.commitBinaryCopy(vault, local.path, tempAbs);
      this.conflicts.push(conflict);
      return;
    }

    conflict.isBinary = false;
    const remoteContent: string = preloadedRemoteText !== null
      ? preloadedRemoteText : await provider.readRemote(local.path);
    conflict.conflictPath = await ConflictResolver.saveCopy(vault, local.path, remoteContent);
    this.conflicts.push(conflict);
  }

  private static cleanupTempBinaryPaths(conflicts: PlannedConflictItem[]): void {
    for (const item of conflicts) {
      if (item.preloadedBinaryTempPath.length > 0) {
        SyncEngine.removeTempFileSafe(item.preloadedBinaryTempPath);
        item.preloadedBinaryTempPath = '';
      }
    }
  }

  private static removeTempFileSafe(path: string): void {
    if (path.length === 0) {
      return;
    }
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (error) {
      LOG.warn(`cleanup temp file failed: ${path}`);
    }
  }

  private static isFatalSyncError(message: string): boolean {
    return message.includes('(401)') || message.includes('(403)') ||
      message.includes('(400)') || message.includes('服务器地址') ||
      message.includes('认证失败') || message.includes('无权限');
  }

  private static errorMessageOf(error: Object): string {
    const err = error as BusinessError;
    const code: string = err.code === undefined ? '' : ` (${err.code})`;
    const msg: string = err.message ?? 'unknown error';
    return msg.endsWith(code) ? msg : `${msg}${code}`;
  }

  private static summarizeProgressErrors(progress: SyncExecutionProgress): string {
    if (progress.fatalError.length > 0) {
      return progress.fatalError;
    }
    if (progress.itemErrors.length === 0) {
      return '';
    }
    if (progress.itemErrors.length === 1) {
      return progress.itemErrors[0];
    }
    return `${progress.itemErrors[0]} 等 ${progress.itemErrors.length} 项失败（已保留其余进度）`;
  }

  private static trashTimestamp(): string {
    const now: Date = new Date();
    const pad: (value: number) => string = (value: number): string => {
      return value < 10 ? `0${value}` : `${value}`;
    };
    return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}` +
      `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  }
}
