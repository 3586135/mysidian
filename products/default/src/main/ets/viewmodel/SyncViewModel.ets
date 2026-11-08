import { common } from '@kit.AbilityKit';
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
  @Trace autoSync: boolean = false;
  @Trace configured: boolean = false;
  @Trace status: SyncStatus = new SyncStatus();
  @Trace conflicts: SyncConflict[] = [];

  private context: common.Context | null = null;
  private readonly engine: SyncEngine = new SyncEngine();
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
      await store.put('autoSync', this.autoSync);
      await store.flush();
      this.configured = this.serverUrl.length > 0;
    } catch (error) {
      LOG.error('save sync config failed');
    }
  }

  /** 执行一次同步。 */
  public async runSync(vault: VaultInfo): Promise<void> {
    const context: common.Context | null = this.context;
    if (context === null) {
      return;
    }
    await this.save();
    const config: SyncConfig = new SyncConfig();
    config.serverUrl = this.serverUrl;
    config.username = this.username;
    config.password = this.password;
    config.remoteRoot = this.remoteRoot;
    config.autoSync = this.autoSync;
    this.status = await this.engine.sync(vault, config, context);
    this.conflicts = this.engine.getConflicts();
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
      return 'failed';
    }
    return 'idle';
  }
}
