import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { SyncConflict, SyncConfig, SyncPlanSummary, SyncSafetyReason, SyncState, SyncStatus,
  VaultInfo } from '@ohos/domain';
import { Logger, SecretStore } from '@ohos/common';
import { DiffLine, FileHistory } from '@ohos/vault';
import { SyncEngine } from '@ohos/sync';

const LOG: Logger = new Logger('MySidianSyncVM');

/** WebDAV 密码在系统加密存储（Asset Store）中的别名。 */
const PASSWORD_ALIAS: string = 'mysidian_webdav_password';

/**
 * 同步视图模型：配置持久化、同步执行与状态展示。
 */
@ObservedV2
export class SyncViewModel {
  @Trace serverUrl: string = '';
  @Trace username: string = '';
  @Trace password: string = '';
  @Trace remoteRoot: string = 'mysidian';
  @Trace caCertPath: string = '';
  @Trace skipCertVerify: boolean = false;
  @Trace autoSync: boolean = false;
  @Trace configured: boolean = false;
  @Trace status: SyncStatus = new SyncStatus();
  @Trace conflicts: SyncConflict[] = [];
  @Trace syncing: boolean = false;
  @Trace pendingPlan: SyncPlanSummary = new SyncPlanSummary();
  @Trace awaitingConfirmation: boolean = false;

  private context: common.Context | null = null;
  private readonly engine: SyncEngine = new SyncEngine();
  private debounceTimer: number = -1;
  private retryTimer: number = -1;
  private queuedVault: VaultInfo | null = null;
  private autoRetryCount: number = 0;
  private lastPassiveTriggerAt: number = 0;
  private lastAuthFailAt: number = 0;
  private confirmArmedAt: number = 0;
  private static readonly STORE: string = 'mysidian_sync';
  private static readonly EDIT_DEBOUNCE_MS: number = 1500;
  private static readonly PASSIVE_COOLDOWN_MS: number = 20000;
  private static readonly SILENT_RETRY_MS: number = 8000;
  /**
   * 安全确认武装延迟：闸门暂停后确认卡片刚渲染的短时间内忽略「确认继续」，
   * 防止穿透点击/双击投递的第二次点击恰好落在滑入原按钮位置的确认按钮上
   * （确认卡片插入会使已到底部的面板内容上移，确认按钮可能移动到
   * 用户刚点过的「立即同步」坐标附近）。
   */
  private static readonly CONFIRM_ARM_DELAY_MS: number = 800;
  /**
   * 认证失败(401/403)后的自动同步冷却期：期间挂起一切自动/无感同步。
   * fnOS/nginx 会累计失败认证并临时限流封禁客户端 IP（表现为「过一阵又 401 又恢复」），
   * 冷却期避免应用在封禁窗口内反复发请求不断续期封禁，形成自维持 401 循环。
   * 用户手动「立即同步」不受冷却期限制并会重置它。
   */
  private static readonly AUTH_FAIL_COOLDOWN_MS: number = 5 * 60 * 1000;

  /** 同步完成后回调（由界面层设置，用于重建索引与刷新文件树）。 */
  public onSyncComplete: (() => void) | null = null;
  /** 同步触发安全闸门暂停时回调（由界面层弹窗提示用户核对后决定是否继续）。 */
  public onNeedsConfirm: ((plan: SyncPlanSummary) => void) | null = null;

  /** 初始化并读取已保存的配置。 */
  public async init(context: common.Context): Promise<void> {
    this.context = context;
    await this.load();
  }

  /** 读取配置。 */
  public async load(): Promise<void> {
    const context: common.Context | null = this.context;
    if (context === null) {
      return;
    }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context,
        SyncViewModel.STORE);
      const url: preferences.ValueType = await store.get('serverUrl', '');
      const user: preferences.ValueType = await store.get('username', '');
      const legacyPass: preferences.ValueType = await store.get('password', '');
      const root: preferences.ValueType = await store.get('remoteRoot', 'mysidian');
      const cert: preferences.ValueType = await store.get('caCertPath', '');
      const skipCert: preferences.ValueType = await store.get('skipCertVerify', false);
      const auto: preferences.ValueType = await store.get('autoSync', false);
      if (typeof url === 'string') {
        this.serverUrl = url;
      }
      if (typeof user === 'string') {
        this.username = user;
      }
      await this.loadPassword(store, typeof legacyPass === 'string' ? legacyPass : '');
      if (typeof root === 'string') {
        this.remoteRoot = root;
      }
      if (typeof cert === 'string') {
        this.caCertPath = cert;
      }
      if (typeof skipCert === 'boolean') {
        this.skipCertVerify = skipCert;
      }
      if (typeof auto === 'boolean') {
        this.autoSync = auto;
      }
      this.configured = this.serverUrl.length > 0;
    } catch (error) {
      LOG.error('load sync config failed');
    }
  }

  /**
   * 读取密码：优先取系统加密存储；若只有旧版明文（preferences），
   * 迁移进加密存储并清除明文。加密存储不可用时保留明文兜底，避免丢失密码。
   */
  private async loadPassword(store: preferences.Preferences, legacy: string): Promise<void> {
    const secret: string | null = await SecretStore.get(PASSWORD_ALIAS);
    if (secret !== null) {
      this.password = secret;
      if (legacy.length > 0) {
        await store.put('password', '');
        await store.flush();
      }
      return;
    }
    this.password = legacy;
    if (legacy.length > 0 && await SecretStore.put(PASSWORD_ALIAS, legacy)) {
      await store.put('password', '');
      await store.flush();
      LOG.info('webdav password migrated to secure store');
    }
  }

  /** 保存配置。 */
  public async save(): Promise<void> {
    const context: common.Context | null = this.context;
    if (context === null) {
      return;
    }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context,
        SyncViewModel.STORE);
      await store.put('serverUrl', this.serverUrl);
      await store.put('username', this.username);
      await store.put('password', await this.persistPassword());
      await store.put('remoteRoot', this.remoteRoot);
      await store.put('caCertPath', this.caCertPath);
      await store.put('skipCertVerify', this.skipCertVerify);
      await store.put('autoSync', this.autoSync);
      await store.flush();
      this.configured = this.serverUrl.length > 0;
    } catch (error) {
      LOG.error('save sync config failed');
    }
  }

  /**
   * 密码写入加密存储，返回需要写进 preferences 的值：
   * 加密存储成功则为空串（不留明文），失败才回退为明文兜底。
   */
  private async persistPassword(): Promise<string> {
    if (this.password.length === 0) {
      await SecretStore.remove(PASSWORD_ALIAS);
      return '';
    }
    if (await SecretStore.put(PASSWORD_ALIAS, this.password)) {
      return '';
    }
    LOG.warn('secure store unavailable, password kept in preferences');
    return this.password;
  }

  private buildConfig(): SyncConfig {
    const config: SyncConfig = new SyncConfig();
    config.serverUrl = this.serverUrl;
    config.username = this.username;
    config.password = this.password;
    config.remoteRoot = this.remoteRoot;
    config.caCertPath = this.caCertPath;
    config.skipCertVerify = this.skipCertVerify;
    config.autoSync = this.autoSync;
    return config;
  }

  /**
   * 计划自动同步（防抖合并：连续保存/编辑仅同步一次；若正在同步则排入队列结束后自动补跑）。
   */
  public scheduleAutoSync(vault: VaultInfo, delayMs: number = SyncViewModel.EDIT_DEBOUNCE_MS): void {
    if (!this.autoSync || this.serverUrl.trim().length === 0 ||
      vault.rootPath.length === 0 || this.awaitingConfirmation ||
      this.isInAuthFailCooldown()) {
      return;
    }
    if (this.syncing) {
      this.queuedVault = vault;
      return;
    }
    this.clearDebounceTimer();
    this.debounceTimer = setTimeout((): void => {
      this.debounceTimer = -1;
      this.runSync(vault, false, false);
    }, delayMs);
  }

  /**
   * 启动或切回前台时触发轻量无感同步（带冷却节流，避免频繁切屏反复请求服务端）。
   */
  public requestPassiveSync(vault: VaultInfo): void {
    if (!this.autoSync || this.serverUrl.trim().length === 0 ||
      vault.rootPath.length === 0 || this.awaitingConfirmation || this.syncing ||
      this.isInAuthFailCooldown()) {
      return;
    }
    const now: number = Date.now();
    if (now - this.lastPassiveTriggerAt < SyncViewModel.PASSIVE_COOLDOWN_MS) {
      return;
    }
    if (this.status.lastSyncAt > 0 && now - this.status.lastSyncAt < SyncViewModel.PASSIVE_COOLDOWN_MS) {
      return;
    }
    this.lastPassiveTriggerAt = now;
    this.scheduleAutoSync(vault, 600);
  }

  /** 释放同步防抖与重试定时器。 */
  public disposeTimers(): void {
    this.clearDebounceTimer();
    this.clearRetryTimer();
    this.queuedVault = null;
  }

  private clearDebounceTimer(): void {
    if (this.debounceTimer >= 0) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
  }

  private clearRetryTimer(): void {
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
  }

  private static isAuthOrConfigError(message: string): boolean {
    return message.includes('(401)') || message.includes('(403)') ||
      message.includes('(400)') || message.includes('服务器地址') ||
      message.includes('认证失败') || message.includes('无权限');
  }

  /** 执行一次同步（并发时自动合并补跑请求，绝不漏掉同步期间的新改动）。 */
  public async runSync(vault: VaultInfo, confirmed: boolean = false,
    userInitiated: boolean = false): Promise<void> {
    const context: common.Context | null = this.context;
    if (context === null || vault.rootPath.length === 0) {
      return;
    }
    if (this.syncing) {
      if (!userInitiated && !this.awaitingConfirmation) {
        this.queuedVault = vault;
      }
      return;
    }
    this.clearDebounceTimer();
    this.clearRetryTimer();
    this.queuedVault = null;
    if (userInitiated) {
      this.autoRetryCount = 0;
      // 手动同步始终允许：用户可能刚修正凭据或服务器封禁已过，重置认证冷却期。
      this.lastAuthFailAt = 0;
    }
    this.syncing = true;
    try {
      await this.save();
      const config: SyncConfig = this.buildConfig();
      this.status = await this.engine.sync(vault, config, context, confirmed);
      this.conflicts = this.engine.getConflicts();
      if (this.status.state === SyncState.PAUSED) {
        this.pendingPlan = this.engine.getPendingPlan();
        this.awaitingConfirmation = true;
        this.confirmArmedAt = Date.now();
        if (userInitiated && this.onNeedsConfirm !== null) {
          this.onNeedsConfirm(this.pendingPlan);
        }
        return;
      }
      this.awaitingConfirmation = false;
      this.pendingPlan = new SyncPlanSummary();
      if (this.status.state === SyncState.SUCCESS || this.status.state === SyncState.CONFLICT) {
        this.autoRetryCount = 0;
        this.lastAuthFailAt = 0;
      }
      if (this.status.state === SyncState.FAILED &&
        SyncViewModel.isAuthOrConfigError(this.status.message)) {
        // 进入认证冷却期：停止自动同步，等待服务器端限流/封禁窗口过期。
        this.lastAuthFailAt = Date.now();
        this.autoRetryCount = 0;
        LOG.warn(`auth/config failure, auto-sync paused for ` +
          `${Math.round(SyncViewModel.AUTH_FAIL_COOLDOWN_MS / 1000)}s`);
      }
      if (this.onSyncComplete !== null && (this.status.pendingDownloads > 0 ||
        this.status.pendingTrashed > 0 || this.conflicts.length > 0)) {
        this.onSyncComplete();
      }
      if (!userInitiated && this.status.state === SyncState.FAILED &&
        this.autoSync && !SyncViewModel.isAuthOrConfigError(this.status.message) &&
        this.autoRetryCount < 1) {
        this.autoRetryCount++;
        const retryVault: VaultInfo = vault;
        this.retryTimer = setTimeout((): void => {
          this.retryTimer = -1;
          this.runSync(retryVault, false, false);
        }, SyncViewModel.SILENT_RETRY_MS);
      }
    } finally {
      this.syncing = false;
      const pending: VaultInfo | null = this.queuedVault;
      this.queuedVault = null;
      if (pending !== null && this.autoSync && !this.awaitingConfirmation) {
        this.scheduleAutoSync(pending, 600);
      }
    }
  }

  /** 认证失败冷却期内返回 true：挂起一切自动/无感同步，避免反复认证失败触发/续期服务端封禁。 */
  private isInAuthFailCooldown(): boolean {
    return this.lastAuthFailAt > 0 &&
      Date.now() - this.lastAuthFailAt < SyncViewModel.AUTH_FAIL_COOLDOWN_MS;
  }

  /** 用户确认安全提示后继续执行同步；卡片刚渲染的武装期内忽略，防穿透点击误确认。 */
  public async confirmPendingSync(vault: VaultInfo): Promise<void> {
    // 未武装（初始或已取消后 confirmArmedAt=0）视为武装期未过：fail-closed，
    // 防止取消后 Date.now()-0 恒大于延迟而放行无确认意图的空跑。
    if (this.confirmArmedAt === 0 ||
      Date.now() - this.confirmArmedAt < SyncViewModel.CONFIRM_ARM_DELAY_MS) {
      LOG.warn('sync confirm ignored: within arm delay (likely tap-through)');
      return;
    }
    this.confirmArmedAt = 0;
    await this.runSync(vault, true, true);
  }

  /** 取消本次等待确认的同步，复位为安全空闲状态。 */
  public cancelPendingSync(): void {
    this.awaitingConfirmation = false;
    this.confirmArmedAt = 0;
    this.pendingPlan = new SyncPlanSummary();
    if (this.status.state === SyncState.PAUSED) {
      this.status = new SyncStatus();
    }
  }

  /** 从文件选择器 URI 导入 PEM 证书到应用沙箱。 */
  public async importCert(uri: string): Promise<boolean> {
    const context: common.Context | null = this.context;
    if (context === null) {
      return false;
    }
    const destPath: string = `${context.filesDir}/webdav-ca.pem`;
    try {
      const src = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      try {
        const dest = fileIo.openSync(destPath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        try {
          fileIo.copyFileSync(src.fd, dest.fd);
        } finally {
          fileIo.closeSync(dest);
        }
      } finally {
        fileIo.closeSync(src);
      }
      this.caCertPath = destPath;
      await this.save();
      return true;
    } catch (error) {
      LOG.error('import cert failed');
      return false;
    }
  }

  /** 移除已导入的自定义证书。 */
  public async clearCert(): Promise<void> {
    const context: common.Context | null = this.context;
    if (context !== null) {
      const certPath: string = `${context.filesDir}/webdav-ca.pem`;
      try {
        if (fileIo.accessSync(certPath)) {
          fileIo.unlinkSync(certPath);
        }
      } catch (error) {
        LOG.error('remove cert failed');
      }
    }
    this.caCertPath = '';
    await this.save();
  }

  /** 计算冲突文件与本地版本的行级差异（本地 → 远端冲突副本；二进制图片返回空）。 */
  public diffConflict(vault: VaultInfo, conflict: SyncConflict): DiffLine[] {
    if (vault.rootPath.length === 0 || conflict.isBinary) {
      return [];
    }
    try {
      const localAbs: string = `${vault.rootPath}/${conflict.path}`;
      const remoteAbs: string = `${vault.rootPath}/${conflict.conflictPath}`;
      const localText: string = fileIo.accessSync(localAbs) ? fileIo.readTextSync(localAbs) : '';
      const remoteText: string = fileIo.accessSync(remoteAbs) ? fileIo.readTextSync(remoteAbs) : '';
      return FileHistory.diff(localText, remoteText);
    } catch (error) {
      LOG.warn('diff conflict failed');
      return [];
    }
  }

  /** 冲突处理：明确将本地版本推送覆盖远端并移除冲突副本。 */
  public async resolveConflictKeepLocal(vault: VaultInfo,
    conflict: SyncConflict): Promise<boolean> {
    const context: common.Context | null = this.context;
    if (context === null || vault.rootPath.length === 0) {
      return false;
    }
    // 同步进行中禁止解决冲突：并发 sync 的 replaceAll/putManifest 会覆盖
    // 刚写入的基线与清单，导致冲突复活、重复推送。仅拒绝本次操作。
    if (this.syncing) {
      LOG.warn('resolve conflict rejected: sync in progress');
      return false;
    }
    try {
      await this.engine.pushConflictKeepLocal(vault, this.buildConfig(), conflict, context);
      const remoteAbs: string = `${vault.rootPath}/${conflict.conflictPath}`;
      if (fileIo.accessSync(remoteAbs)) {
        fileIo.unlinkSync(remoteAbs);
      }
      this.removeConflictItem(conflict);
      return true;
    } catch (error) {
      LOG.warn('resolve keep local push failed');
      return false;
    }
  }

  /** 冲突处理：采用远端冲突副本覆盖本地（文本先存历史快照，支持图片附件），并刷新索引与基线。 */
  public async resolveConflictUseRemote(vault: VaultInfo,
    conflict: SyncConflict): Promise<boolean> {
    const context: common.Context | null = this.context;
    if (context === null || vault.rootPath.length === 0) {
      return false;
    }
    // 同步进行中禁止解决冲突，理由同 resolveConflictKeepLocal。
    if (this.syncing) {
      LOG.warn('resolve conflict rejected: sync in progress');
      return false;
    }
    try {
      const localAbs: string = `${vault.rootPath}/${conflict.path}`;
      const remoteAbs: string = `${vault.rootPath}/${conflict.conflictPath}`;
      if (!fileIo.accessSync(remoteAbs)) {
        return false;
      }
      if (conflict.isBinary) {
        SyncViewModel.copyBinaryFile(remoteAbs, localAbs);
      } else {
        const remoteText: string = fileIo.readTextSync(remoteAbs);
        if (fileIo.accessSync(localAbs)) {
          await FileHistory.snapshot(context, vault, conflict.path);
        }
        const file = fileIo.openSync(localAbs,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        try {
          fileIo.writeSync(file.fd, remoteText);
          fileIo.fsyncSync(file.fd);
        } finally {
          fileIo.closeSync(file);
        }
      }
      fileIo.unlinkSync(remoteAbs);
      await SyncEngine.markConflictUseRemoteResolved(
        vault, this.buildConfig(), conflict, context);
      this.removeConflictItem(conflict);
      if (this.onSyncComplete !== null) {
        this.onSyncComplete();
      }
      return true;
    } catch (error) {
      LOG.warn('resolve use remote failed');
      return false;
    }
  }

  private static copyBinaryFile(srcAbs: string, destAbs: string): void {
    const stat = fileIo.statSync(srcAbs);
    const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
    const src = fileIo.openSync(srcAbs, fileIo.OpenMode.READ_ONLY);
    try {
      fileIo.readSync(src.fd, buffer);
    } finally {
      fileIo.closeSync(src);
    }
    const dest = fileIo.openSync(destAbs,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(dest.fd, buffer);
      fileIo.fsyncSync(dest.fd);
    } finally {
      fileIo.closeSync(dest);
    }
  }

  private removeConflictItem(target: SyncConflict): void {
    // 按笔记自身 path 过滤而非 conflictPath：不同目录同名同内容的两份冲突
    // 可能共享同一 conflictPath，按 conflictPath 过滤会一次移除多条。
    this.conflicts = this.conflicts.filter((item: SyncConflict): boolean =>
      item.path !== target.path);
    if (this.conflicts.length === 0 && this.status.state === SyncState.CONFLICT) {
      const next: SyncStatus = new SyncStatus();
      next.state = SyncState.SUCCESS;
      next.message = 'success';
      next.lastSyncAt = this.status.lastSyncAt;
      next.pendingUploads = this.status.pendingUploads;
      next.pendingDownloads = this.status.pendingDownloads;
      this.status = next;
    }
  }

  /** 返回触发安全暂停原因的本地化文案。 */
  public safetyReasonText(reason: string): string {
    if (reason === SyncSafetyReason.TARGET_CHANGED) {
      return this.resText($r('app.string.sync_confirm_reason_target'));
    }
    if (reason === SyncSafetyReason.BULK_TRASH) {
      return this.resText($r('app.string.sync_confirm_reason_bulk'));
    }
    return this.resText($r('app.string.sync_confirm_reason_initial'));
  }

  /** 返回待确认计划的汇总说明文本。 */
  public safetySummaryText(): string {
    const p: SyncPlanSummary = this.pendingPlan;
    return this.resText($r('app.string.sync_confirm_summary'), p.uploads, p.downloads,
      p.trashes, p.conflicts);
  }

  /** 拼接弹窗确认正文（原因 + 数量统计 + 示例文件路径）。 */
  public safetyAlertMessage(): string {
    const parts: string[] = [
      this.safetyReasonText(this.pendingPlan.reason),
      this.safetySummaryText()
    ];
    if (this.pendingPlan.samplePaths.length > 0) {
      parts.push(this.resText($r('app.string.sync_confirm_samples'),
        this.pendingPlan.samplePaths.join('、')));
    }
    return parts.join('\n');
  }

  /** 状态展示文案（走资源，随系统语言）。 */
  public statusText(): string {
    if (this.status.state === SyncState.SYNCING) {
      return this.resText($r('app.string.sync_status_syncing'));
    }
    if (this.status.state === SyncState.PAUSED) {
      return this.resText($r('app.string.sync_status_paused'));
    }
    if (this.status.state === SyncState.SUCCESS) {
      if (this.status.pendingTrashed > 0 || this.status.skippedRemoteDeletes > 0) {
        return this.resText($r('app.string.sync_status_success_detail'),
          this.status.pendingUploads, this.status.pendingDownloads,
          this.status.pendingTrashed, this.status.skippedRemoteDeletes);
      }
      return this.resText($r('app.string.sync_status_success'), this.status.pendingUploads,
        this.status.pendingDownloads);
    }
    if (this.status.state === SyncState.CONFLICT) {
      return this.resText($r('app.string.sync_status_conflict'), this.conflicts.length);
    }
    if (this.status.state === SyncState.FAILED) {
      return this.status.message.length > 0 ?
        this.resText($r('app.string.sync_status_failed'), this.status.message) :
        this.resText($r('app.string.sync_status_failed_plain'));
    }
    return this.resText($r('app.string.sync_status_idle'));
  }

  private resText(resource: Resource, ...args: Array<string | number>): string {
    const context: common.Context | null = this.context;
    if (context === null) {
      return '';
    }
    try {
      return context.resourceManager.getStringSync(resource, ...args);
    } catch (error) {
      return '';
    }
  }
}
