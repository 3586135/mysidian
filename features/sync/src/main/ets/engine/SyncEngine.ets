import { fileIo, hash } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { RemoteEntry, RemoteTrashStatus, SyncConfig, SyncConflict, SyncFileFilter, SyncPathGuard,
  SyncPlanSummary, SyncProvider, SyncSafetyReason, SyncState, SyncStatus, VaultInfo } from '@ohos/domain';
import { Logger } from '@ohos/common';
import { FileHistory, SyncBaseline, SyncBaselineRow, SyncStateDao, VaultManager } from '@ohos/vault';
import { ConflictResolver } from './ConflictResolver';
import { WebDavProvider } from '../provider/WebDavProvider';
import { MAX_SYNC_FILE_BYTES, SyncOversizedError } from '../SyncLimits';

const LOG: Logger = new Logger('MySidianSync');

/**
 * 远端新文件拉取并发数。
 * 注意：fnOS（nginx Basic 认证）对短时并发认证请求返回 401，且模拟器
 * netstack 并发在途请求存在认证头丢失问题，故采用串行拉取保证稳定。
 */
const PULL_CONCURRENCY: number = 1;

/**
 * 单文件参与同步的体积上限常量统一放在 SyncLimits（引擎规划期检查与
 * 供应方读取期熔断共用，见 SyncLimits.ets 头注释）。
 */

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
  TRASH_LOCAL = 'trashLocal',
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

/** 单文件拉取结果：ok 成功；oversized 读取期体积熔断（持续性状态，跳过不计错）；error 失败消息。 */
class PullOutcome {
  ok: boolean = false;
  oversized: boolean = false;
  error: string = '';
}

/** 本地扫描结果：可同步条目 + 因超限被跳过的文件路径（决策阶段须原样保留两端）。 */
class LocalCollectResult {
  entries: RemoteEntry[] = [];
  oversizedPaths: Set<string> = new Set<string>();
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
  localTrashes: RemoteEntry[] = [];
  keptLocalDeleted: RemoteEntry[] = [];
  verifiedEqualEntries: RemoteEntry[] = [];
  /** 规划阶段收集并哈希好的本地条目快照（persistSyncState 复用，避免全库二次 sha256）。 */
  localEntries: RemoteEntry[] = [];
  /** 本地超限跳过的文件：persistSyncState 须结转其清单与基线，不得因全量覆写丢失。 */
  oversizedPaths: Set<string> = new Set<string>();
  /** 本地超限跳过但远端存在的条目快照（含清单哈希），persistSyncState 原样结转回清单。 */
  oversizedCarry: RemoteEntry[] = [];
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
  /** 规划阶段已预载到沙箱临时目录的冲突二进制路径：plan 未成形就抛异常时兜底清理。 */
  private preloadedTempPaths: string[] = [];

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
    this.preloadedTempPaths = [];
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
        await this.executeLocalTrashes(provider, vault, context, plan.localTrashes, progress);
      }
      if (progress.fatalError.length === 0) {
        await this.executePulls(provider, vault, plan.pulls, context, progress);
      }

      if (!progress.hasErrors()) {
        await this.persistSyncState(provider, vault, context, plan, progress);
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
      } else {
        // 计划构建中途抛异常：plan 尚未成形，已预载的冲突临时文件
        // 不在任何 plan.conflicts 里，须按引擎侧记录逐一清理，防止泄漏。
        for (const tempPath of this.preloadedTempPaths) {
          SyncEngine.removeTempFileSafe(tempPath);
        }
      }
      this.preloadedTempPaths = [];
      const err = error as BusinessError;
      const code: string = err.code === undefined ? '' : ` (${err.code})`;
      this.status.state = SyncState.FAILED;
      this.status.message = `${err.message}${code}`;
      LOG.error(`sync failed, code=${err.code}, message=${err.message}`);
    } finally {
      await provider.disconnect();
      this.provider = null;
      this.preloadedTempPaths = [];
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
      // 推送前校验远端自冲突发现以来未再变化（serverTag/ETag 比对）：
      // 若其他端在用户决策前又改了远端文件，静默覆盖会丢失那一侧的修改，
      // 此时中止并保留冲突，交由下一轮同步重新决策。
      if (conflict.remoteServerTag.length > 0) {
        const remoteNow: RemoteEntry | null = await provider.stat(conflict.path);
        if (remoteNow !== null && remoteNow.serverTag.length > 0 &&
          remoteNow.serverTag !== conflict.remoteServerTag) {
          throw new Error(`远端文件在解决冲突期间发生了变化，已保留冲突: ${conflict.path}`);
        }
      }
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
    const localCollect: LocalCollectResult = await this.collectLocalEntries(
      vault, plan.baselines, plan.ignoreRules);
    plan.localEntries = localCollect.entries;
    plan.oversizedPaths = localCollect.oversizedPaths;
    const localEntries: RemoteEntry[] = plan.localEntries;
    LOG.info(`sync plan: local=${localEntries.length}, remote=${remoteEntries.length}, ` +
      `targetChanged=${plan.targetChanged}`);

    // 清单缺失兜底（如上一轮同步末尾写清单失败）：远端条目没有内容哈希时，
    // 用本地基线里"已同步"行的已知哈希回填 etag，避免决策落入逐文件
    // readRemote 内容探测。对 PUT 不回 ETag 的服务端（坚果云实测），若不
    // 回填，基线 serverTag 为空的文件每轮都会探测一次，严格限流的服务端
    // 会直接打爆配额形成死锁。仅在基线与远端 serverTag 不冲突且大小一致
    // 时回填（防远端被外部改动后误判相同）；serverTag 为空时存在一轮盲区，
    // 本轮结束后基线会补记真实 serverTag，后续轮次即可识别漂移。
    let baselineEtagBackfilled = 0;
    for (const remote of remoteEntries) {
      if (remote.etag.length > 0) {
        continue;
      }
      const baseline: SyncBaseline | undefined = plan.baselines.get(remote.path);
      if (baseline === undefined || baseline.state !== 'synced' || baseline.fileHash.length === 0) {
        continue;
      }
      if (baseline.targetKey.length > 0 && baseline.targetKey !== plan.targetKey) {
        continue;
      }
      if (baseline.serverTag.length > 0 && remote.serverTag.length > 0 &&
        baseline.serverTag !== remote.serverTag) {
        continue;
      }
      if (remote.size > 0 && baseline.size > 0 && remote.size !== baseline.size) {
        continue;
      }
      remote.etag = baseline.fileHash;
      baselineEtagBackfilled++;
    }
    if (baselineEtagBackfilled > 0) {
      LOG.info(`sync baseline etag backfill: ${baselineEtagBackfilled} entries`);
    }

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
        local, remote, baseline, SyncFileFilter.isMarkdown(local.path), plan.targetKey);
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
      if (decision === SyncDecision.TRASH_LOCAL) {
        plan.localTrashes.push(local);
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
          if (error instanceof SyncOversizedError) {
            // 远端内容探测期体积熔断：持续性状态，跳过该文件本轮决策
            // （基线不变，下轮重新探测），不中止整轮也不计 itemErrors。
            LOG.warn(`sync check-content skip oversized remote: ${local.path}`);
            continue;
          }
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
          let preloadedTemp: string | null = null;
          try {
            preloadedTemp = await this.checkBinaryEqualOrTemp(
              provider, vault, local, remote);
          } catch (error) {
            if (error instanceof SyncOversizedError) {
              // 冲突预载期体积熔断：跳过该文件本轮决策（基线不变，两端
              // 各自原样保留），不因单个超大文件中止整轮规划。
              LOG.warn(`sync conflict probe skip oversized remote: ${local.path}`);
              continue;
            }
            throw error as Error;
          }
          if (preloadedTemp === null) {
            plan.verifiedEqualEntries.push(local);
            continue;
          }
          const item: PlannedConflictItem = new PlannedConflictItem();
          item.local = local;
          item.remote = remote;
          item.preloadedBinaryTempPath = preloadedTemp;
          this.preloadedTempPaths.push(preloadedTemp);
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
      // 本地超限被跳过的文件：两端各自原样保留，绝不参与远端决策
      // （否则基线 synced + 同 targetKey 时会被 TRASH_REMOTE，远端副本丢失）。
      if (localCollect.oversizedPaths.has(remote.path)) {
        LOG.warn(`skip remote decision for oversized local file: ${remote.path}`);
        // 记录远端条目快照（含清单哈希）：persistSyncState 原样结转回远端清单，
        // 否则全量覆写 manifest 会丢失该文件的哈希记录，退化为冲突/内容探测。
        plan.oversizedCarry.push(remote);
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

    // 远端软删与本地回收站传播统一计入批量删除闸门：任一侧超额都要求用户确认。
    const pendingTrashTotal: number = plan.trashes.length + plan.localTrashes.length;
    const plannedChanges: number = plan.uploads.length + plan.pulls.length +
      plan.trashes.length + plan.conflicts.length + plan.localTrashes.length;
    const plannedRiskyChanges: number = plan.uploads.length + plan.trashes.length +
      plan.conflicts.length + plan.localTrashes.length;
    const reason: SyncSafetyReason = SyncEngine.evaluateSafetyGate(
      localEntries.length, remoteMap.size, plan.baselines.size,
      pendingTrashTotal, syncedBaselineCount, plan.targetChanged,
      plannedChanges, plannedRiskyChanges);
    const summary: SyncPlanSummary = new SyncPlanSummary();
    summary.uploads = plan.uploads.length;
    summary.downloads = plan.pulls.length;
    summary.conflicts = plan.conflicts.length;
    summary.trashes = pendingTrashTotal;
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
    for (const item of plan.localTrashes) {
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
        if (error instanceof SyncOversizedError) {
          // 冲突副本保存期体积熔断：持续性状态，跳过该冲突（两端各自
          // 原样保留、基线不变），不计 itemErrors 以免每轮永久报失败。
          LOG.warn(`sync conflict skip oversized remote: ${item.local.path}`);
          continue;
        }
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

  /**
   * 传播远端删除到本地：远端文件已被其他端删除（本地基线 synced 且内容未变）时，
   * 把本地文件移入仓库回收站并清理索引记录，避免下一轮把已删除的文件推回远端。
   * 执行前用独立 HEAD 探测二次确认远端确实已不存在，防止部分列举或竞态误删本地。
   */
  private async executeLocalTrashes(provider: SyncProvider, vault: VaultInfo,
    context: common.Context, localTrashes: RemoteEntry[],
    progress: SyncExecutionProgress): Promise<void> {
    if (localTrashes.length === 0) {
      return;
    }
    const manager: VaultManager = await VaultManager.create(context);
    for (const entry of localTrashes) {
      if (progress.fatalError.length > 0) {
        return;
      }
      try {
        const remoteStat: RemoteEntry | null = await provider.stat(entry.path);
        if (remoteStat !== null) {
          LOG.warn(`sync local trash skip (remote still exists): ${entry.path}`);
          continue;
        }
        LOG.info(`sync trash local: ${entry.path}`);
        const trashRel: string = await manager.trashNote(vault, entry.path);
        if (trashRel.length === 0) {
          LOG.warn(`sync local trash missing file: ${entry.path}`);
          continue;
        }
        this.status.pendingTrashed++;
        progress.succeededTrashes.add(entry.path);
      } catch (error) {
        const msg: string = SyncEngine.errorMessageOf(error);
        LOG.warn(`sync local trash failed (${entry.path}): ${msg}`);
        if (SyncEngine.isFatalSyncError(msg)) {
          progress.fatalError = msg;
          return;
        }
        progress.itemErrors.push(`${entry.path}: ${msg}`);
      }
    }
  }

  private async executePulls(provider: SyncProvider, vault: VaultInfo, pulls: RemoteEntry[],
    context: common.Context, progress: SyncExecutionProgress): Promise<void> {
    if (pulls.length > 0) {
      LOG.info(`sync pull pending: ${pulls.length} files`);
    }
    // 规划期超限预检（省带宽优化/防御纵深）：真实强制在供应方读取期熔断
    // （服务器可谎报 size 或不报 size，见 SyncLimits.ets）。仅记日志不计
    // itemErrors：超限是持续性状态，计入会让每轮同步都永久报"失败"。
    const boundedPulls: RemoteEntry[] = [];
    for (const remote of pulls) {
      if (remote.size > 0 && remote.size > MAX_SYNC_FILE_BYTES) {
        LOG.warn(`sync pull skip oversized file (${remote.size} bytes): ${remote.path}`);
        continue;
      }
      boundedPulls.push(remote);
    }
    for (let i = 0; i < boundedPulls.length; i += PULL_CONCURRENCY) {
      if (progress.fatalError.length > 0) {
        return;
      }
      const batch: RemoteEntry[] = boundedPulls.slice(i, i + PULL_CONCURRENCY);
      const outcomes: PullOutcome[] = await Promise.all(batch.map(
        (remote: RemoteEntry): Promise<PullOutcome> => {
          return this.pullRemote(provider, vault, remote, context);
        }));
      for (let k = 0; k < outcomes.length; k++) {
        const outcome: PullOutcome = outcomes[k];
        const remoteItem: RemoteEntry = batch[k];
        if (outcome.ok) {
          progress.succeededPulls.add(remoteItem.path);
          continue;
        }
        // 读取期体积熔断（远端谎报/未报体积）：与规划期跳过同等对待——
        // 持续性状态，记日志不计 itemErrors，避免每轮同步永久报失败。
        if (outcome.oversized) {
          LOG.warn(`sync pull skip oversized at read: ${remoteItem.path}`);
          continue;
        }
        if (outcome.error.includes('404')) {
          LOG.warn(`sync pull skip (404): ${remoteItem.path}`);
          continue;
        }
        LOG.warn(`sync pull failed (${remoteItem.path}): ${outcome.error}`);
        if (SyncEngine.isFatalSyncError(outcome.error)) {
          progress.fatalError = outcome.error;
          return;
        }
        progress.itemErrors.push(`${remoteItem.path}: ${outcome.error}`);
      }
    }
  }

  private async persistSyncState(provider: SyncProvider, vault: VaultInfo,
    context: common.Context, plan: SyncExecutionPlan,
    progress: SyncExecutionProgress): Promise<void> {
    const conflictRemoteMap: Map<string, RemoteEntry> = new Map<string, RemoteEntry>();
    for (const item of plan.conflicts) {
      conflictRemoteMap.set(item.local.path, item.remote);
    }

    // 复用规划阶段的本地条目快照（哈希已算好），避免成功轮次全库二次 sha256；
    // 仅对执行期间实际落盘的拉取文件重算哈希（内容已变化）。
    // 规划时点之后用户的编辑/新建不进入本轮基线与清单，下轮按未同步内容
    // 重新上传——修复「同步中编辑被误标已同步、永不推送」的丢失类缺陷。
    // 本轮已软删（含本地回收站传播）的条目不再写入清单与基线。
    const finalEntries: RemoteEntry[] = [];
    for (const entry of plan.localEntries) {
      if (progress.succeededTrashes.has(entry.path)) {
        continue;
      }
      if (progress.succeededPulls.has(entry.path)) {
        const pulledAbs: string = `${vault.rootPath}/${entry.path}`;
        if (fileIo.accessSync(pulledAbs)) {
          const pulledStat = fileIo.statSync(pulledAbs);
          const pulledItem: RemoteEntry = new RemoteEntry();
          pulledItem.path = entry.path;
          pulledItem.size = pulledStat.size;
          pulledItem.mtime = pulledStat.mtime;
          pulledItem.etag = await hash.hash(pulledAbs, 'sha256');
          pulledItem.isDir = false;
          finalEntries.push(pulledItem);
        }
        continue;
      }
      finalEntries.push(entry);
    }
    // PULL_NEW（远端新增、规划时本地不存在）的文件不在快照中：成功落盘后必须
    // 并入清单与基线，否则全量覆写的远端 manifest 丢失这些条目、本地基线缺失，
    // 窗口期内远端一旦删除该文件，本地会按 PUSH_NEW 把它推回复活。
    const snapshotPaths: Set<string> = new Set<string>();
    for (const entry of plan.localEntries) {
      snapshotPaths.add(entry.path);
    }
    for (const remote of plan.pulls) {
      if (!progress.succeededPulls.has(remote.path) || snapshotPaths.has(remote.path)) {
        continue;
      }
      const pulledAbs: string = `${vault.rootPath}/${remote.path}`;
      if (!fileIo.accessSync(pulledAbs)) {
        continue;
      }
      const pulledStat = fileIo.statSync(pulledAbs);
      const pulledItem: RemoteEntry = new RemoteEntry();
      pulledItem.path = remote.path;
      pulledItem.size = pulledStat.size;
      pulledItem.mtime = pulledStat.mtime;
      pulledItem.etag = await hash.hash(pulledAbs, 'sha256');
      pulledItem.isDir = false;
      finalEntries.push(pulledItem);
    }
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

    // F4：本地超限跳过的文件：远端清单条目原样结转，防止全量覆写 manifest 丢失
    // 该文件的哈希记录（丢失后下一轮 etag 未知，退化为冲突/逐文件内容探测）。
    for (const carry of plan.oversizedCarry) {
      if (!finalLocalMap.has(carry.path)) {
        manifestEntries.push(carry);
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

    // F4：本地超限跳过的文件：基线行原样结转（保留 serverTag 与既有状态），
    // 防止 replaceAll 全量覆写把"曾同步"记录清掉。
    for (const carry of plan.oversizedCarry) {
      if (finalLocalMap.has(carry.path)) {
        continue;
      }
      const prev: SyncBaseline | undefined = plan.baselines.get(carry.path);
      if (prev !== undefined && prev.state === 'conflict') {
        baselineRows.push(SyncEngine.buildConflictBaselineRow(carry.path, prev, plan.targetKey));
        continue;
      }
      if (prev !== undefined && prev.state === 'synced' && prev.fileHash.length > 0) {
        baselineRows.push(SyncEngine.buildSyncedBaselineRow(
          carry.path, prev.fileHash, prev.mtime, prev.size, carry.serverTag, plan.targetKey));
        continue;
      }
      if (carry.etag.length > 0) {
        baselineRows.push(SyncEngine.buildSyncedBaselineRow(
          carry.path, carry.etag, carry.mtime, carry.size, carry.serverTag, plan.targetKey));
      }
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
   * 超过 MAX_SYNC_FILE_BYTES 的文件不进 entries，但路径记入 oversizedPaths：
   * 远端决策阶段须据此原样跳过，否则曾同步过的文件长大后超限会被误判为
   * "远端独有 + 已同步基线"而把远端副本移入 .trash/（数据丢失）。
   */
  private async collectLocalEntries(vault: VaultInfo,
    baselines: Map<string, SyncBaseline> = new Map<string, SyncBaseline>(),
    ignoreRules: string[] = []): Promise<LocalCollectResult> {
    const result: LocalCollectResult = new LocalCollectResult();
    const entries: RemoteEntry[] = [];
    this.collectFiles(vault.rootPath, '', entries, ignoreRules);
    for (const entry of entries) {
      const absolute: string = `${vault.rootPath}/${entry.path}`;
      const stat = fileIo.statSync(absolute);
      if (stat.size > MAX_SYNC_FILE_BYTES) {
        LOG.warn(`skip oversized file (${stat.size} bytes): ${entry.path}`);
        result.oversizedPaths.add(entry.path);
        continue;
      }
      const item: RemoteEntry = new RemoteEntry();
      item.path = entry.path;
      item.size = stat.size;
      item.mtime = stat.mtime;
      const cached: SyncBaseline | undefined = baselines.get(entry.path);
      if (cached !== undefined && cached.state === 'synced' &&
        SyncEngine.isHashReusable(cached, stat.mtime, stat.size)) {
        item.etag = cached.fileHash;
        item.isDir = false;
        result.entries.push(item);
        continue;
      }
      item.etag = await hash.hash(absolute, 'sha256');
      item.isDir = false;
      result.entries.push(item);
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
    baseline: SyncBaseline | undefined, isMarkdown: boolean = true,
    currentTargetKey: string = ''): SyncDecision {
    if (remote === undefined) {
      // 远端已消失而本地仍是上次同步后的原样（基线 synced 且内容未变）：
      // 判定为其他端删除，传播到本地回收站，避免把删除的文件推回远端造成“删除后复活”。
      // 墓碑只在基线确实属于当前同步目标时生效：targetKey 为空的历史基线或来自
      // 其他服务器/目录的基线不能证明“当前远端删过它”，否则切换目标后远端暂缺
      // 的文件会被整批误判为“他端删除”而移入回收站。
      if (baseline !== undefined && baseline.state === 'synced' &&
        baseline.fileHash === local.etag &&
        currentTargetKey.length > 0 && baseline.targetKey === currentTargetKey) {
        return SyncDecision.TRASH_LOCAL;
      }
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

  /** 拉取单个远端新文件：体积熔断与失败均以 PullOutcome 表达，绝不抛出到批量循环外。 */
  private async pullRemote(provider: SyncProvider, vault: VaultInfo, remote: RemoteEntry,
    context: common.Context): Promise<PullOutcome> {
    const outcome: PullOutcome = new PullOutcome();
    try {
      await this.pullEntry(provider, vault, remote, context);
      this.status.pendingDownloads++;
      outcome.ok = true;
      return outcome;
    } catch (error) {
      if (error instanceof SyncOversizedError) {
        outcome.oversized = true;
        return outcome;
      }
      const err = error as BusinessError;
      outcome.error = err.message ?? '';
      return outcome;
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
    } else {
      await provider.pullBinary(entry, absolute);
    }
    // 落盘后回写远端原始 mtime：临时文件 rename 的落盘时间是拉取时刻，
    // 不回写会让「最近修改」排序与 mtime 变化检测丢失远端的历史状态。
    // utimes 接口要求毫秒：PROPFIND 的 mtime 为毫秒可直接传入；
    // PROPFIND 不可用服务器的清单回退路径 mtime 为秒（stat.mtime），
    // 直接当毫秒会把时间错设到 1970 年附近，宁可不回写。
    if (entry.mtime > 100000000000) {
      try {
        fileIo.utimes(absolute, entry.mtime);
      } catch (error) {
        LOG.warn(`sync pull utime failed: ${entry.path}`);
      }
    }
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
    // 400 只可能出现在文件级请求（PROPFIND 已成功才会走到执行阶段），
    // 属单项失败而非配置/认证错误，不应中止整轮同步。
    return message.includes('(401)') || message.includes('(403)') ||
      message.includes('服务器地址') ||
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
