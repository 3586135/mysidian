import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { SyncConflict, SyncConfig, SyncState, SyncStatus, VaultInfo } from '@ohos/domain';
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

  private context: common.Context | null = null;
  private readonly engine: SyncEngine = new SyncEngine();
  private syncing: boolean = false;
  private static readonly STORE: string = 'mysidian_sync';

  /** 同步完成后回调（由界面层设置，用于重建索引与刷新文件树）。 */
  public onSyncComplete: (() => void) | null = null;

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

  /** 执行一次同步（并发保护：上一次未完成时忽略本次请求）。 */
  public async runSync(vault: VaultInfo): Promise<void> {
    const context: common.Context | null = this.context;
    if (context === null || this.syncing || vault.rootPath.length === 0) {
      return;
    }
    this.syncing = true;
    try {
      await this.save();
      const config: SyncConfig = new SyncConfig();
      config.serverUrl = this.serverUrl;
      config.username = this.username;
      config.password = this.password;
      config.remoteRoot = this.remoteRoot;
      config.caCertPath = this.caCertPath;
      config.skipCertVerify = this.skipCertVerify;
      config.autoSync = this.autoSync;
      this.status = await this.engine.sync(vault, config, context);
      this.conflicts = this.engine.getConflicts();
      if (this.onSyncComplete !== null && this.status.pendingDownloads > 0) {
        this.onSyncComplete();
      }
    } finally {
      this.syncing = false;
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

  /** 计算冲突文件与本地版本的行级差异（本地 → 远端冲突副本）。 */
  public diffConflict(vault: VaultInfo, conflict: SyncConflict): DiffLine[] {
    if (vault.rootPath.length === 0) {
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

  /** 冲突处理：保留本地版本，移除冲突副本。 */
  public resolveConflictKeepLocal(vault: VaultInfo, conflict: SyncConflict): boolean {
    if (vault.rootPath.length === 0) {
      return false;
    }
    try {
      const remoteAbs: string = `${vault.rootPath}/${conflict.conflictPath}`;
      if (fileIo.accessSync(remoteAbs)) {
        fileIo.unlinkSync(remoteAbs);
      }
      this.removeConflictItem(conflict);
      return true;
    } catch (error) {
      LOG.warn('resolve keep local failed');
      return false;
    }
  }

  /** 冲突处理：采用远端冲突副本覆盖本地（覆盖前先存历史快照），并刷新索引。 */
  public async resolveConflictUseRemote(vault: VaultInfo,
    conflict: SyncConflict): Promise<boolean> {
    const context: common.Context | null = this.context;
    if (context === null || vault.rootPath.length === 0) {
      return false;
    }
    try {
      const localAbs: string = `${vault.rootPath}/${conflict.path}`;
      const remoteAbs: string = `${vault.rootPath}/${conflict.conflictPath}`;
      if (!fileIo.accessSync(remoteAbs)) {
        return false;
      }
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
      fileIo.unlinkSync(remoteAbs);
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

  private removeConflictItem(target: SyncConflict): void {
    this.conflicts = this.conflicts.filter((item: SyncConflict): boolean =>
      item.conflictPath !== target.conflictPath);
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

  /** 状态展示文案（走资源，随系统语言）。 */
  public statusText(): string {
    if (this.status.state === SyncState.SYNCING) {
      return this.resText($r('app.string.sync_status_syncing'));
    }
    if (this.status.state === SyncState.SUCCESS) {
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
