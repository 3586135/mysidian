import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { SyncConflict, SyncConfig, SyncState, SyncStatus, VaultInfo } from '@ohos/domain';
import { Logger } from '@ohos/common';
import { SyncEngine } from '@ohos/sync';

const LOG: Logger = new Logger('MySidianSyncVM');

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
      const pass: preferences.ValueType = await store.get('password', '');
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
      if (typeof pass === 'string') {
        this.password = pass;
      }
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
      await store.put('password', this.password);
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

  /** 状态展示文案。 */
  public statusText(): string {
    if (this.status.state === SyncState.SYNCING) {
      return 'syncing';
    }
    if (this.status.state === SyncState.SUCCESS) {
      return `success (${this.status.pendingUploads} up / ${this.status.pendingDownloads} down)`;
    }
    if (this.status.state === SyncState.CONFLICT) {
      return `conflict (${this.conflicts.length})`;
    }
    if (this.status.state === SyncState.FAILED) {
      return this.status.message.length > 0 ? `failed: ${this.status.message}` : 'failed';
    }
    return 'idle';
  }
}
