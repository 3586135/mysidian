/**
 * 同步领域模型（纯数据类型）。
 */

export enum SyncState {
  IDLE = 'idle',
  SYNCING = 'syncing',
  SUCCESS = 'success',
  FAILED = 'failed',
  CONFLICT = 'conflict',
  PAUSED = 'paused'
}

export enum RemoteTrashStatus {
  MOVED = 'moved',
  NOT_FOUND = 'notFound',
  UNSUPPORTED = 'unsupported'
}

export enum SyncSafetyReason {
  NONE = 'none',
  TARGET_CHANGED = 'targetChanged',
  INITIAL_NON_EMPTY_MERGE = 'initialMerge',
  BULK_TRASH = 'bulkTrash'
}

export enum ConflictResolution {
  KEEP_LOCAL = 'keepLocal',
  KEEP_REMOTE = 'keepRemote',
  KEEP_BOTH = 'keepBoth'
}

/** 同步配置。 */
export class SyncConfig {
  /** 供应商标识，如 webdav */
  providerId: string = 'webdav';
  serverUrl: string = '';
  username: string = '';
  password: string = '';
  /** 远端根目录（相对服务器） */
  remoteRoot: string = 'mysidian';
  /** 自定义 CA 证书路径（PEM），用于自签名服务器 */
  caCertPath: string = '';
  /** 跳过 HTTPS 证书校验（不安全，仅自用服务器建议开启） */
  skipCertVerify: boolean = false;
  autoSync: boolean = false;
  intervalMinutes: number = 30;
  wifiOnly: boolean = true;
  chargeOnly: boolean = false;
  /** 端到端加密开关 */
  encrypt: boolean = false;
}

/** 远端条目。 */
export class RemoteEntry {
  path: string = '';
  isDir: boolean = false;
  size: number = 0;
  mtime: number = 0;
  /** 远端 ETag / 校验值 */
  etag: string = '';
  /** 服务器原生版本标识（PROPFIND etag 或 mtime~size），用于检测清单之外的外部修改 */
  serverTag: string = '';
}

/** 同步状态。 */
export class SyncStatus {
  state: SyncState = SyncState.IDLE;
  message: string = '';
  lastSyncAt: number = 0;
  pendingUploads: number = 0;
  pendingDownloads: number = 0;
  /** 移入远端 .trash/ 的文件数（软删除） */
  pendingTrashed: number = 0;
  /** 因服务端不支持 MOVE 等原因而保留未删的远端文件数 */
  skippedRemoteDeletes: number = 0;
  /** 触发安全暂停（PAUSED）的原因 */
  safetyReason: string = SyncSafetyReason.NONE;
}

/** 同步计划预览：执行远端写入/移动前的干跑统计。 */
export class SyncPlanSummary {
  uploads: number = 0;
  downloads: number = 0;
  conflicts: number = 0;
  trashes: number = 0;
  requiresConfirmation: boolean = false;
  reason: string = SyncSafetyReason.NONE;
  samplePaths: string[] = [];
}

/** 冲突记录。 */
export class SyncConflict {
  path: string = '';
  localHash: string = '';
  remoteHash: string = '';
  /** 冲突副本在本地仓库内的相对路径 */
  conflictPath: string = '';
  /** 是否为二进制附件冲突 */
  isBinary: boolean = false;
  /** 远端版本标识（采用远端后同步更新本地基线） */
  remoteServerTag: string = '';
}
