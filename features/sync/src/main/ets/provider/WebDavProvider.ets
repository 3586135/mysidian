import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { RemoteEntry, RemoteTrashStatus, SyncConfig, SyncPathGuard, SyncProvider } from '@ohos/domain';
import { Logger } from '@ohos/common';

const LOG: Logger = new Logger('MySidianWebDav');

/** 远端清单文件（JSON）原始结构。 */
class WebDavManifestRaw {
  version?: string = '';
  files?: WebDavFileRaw[] = [];
}

/** 远端清单条目原始结构。 */
class WebDavFileRaw {
  path?: string = '';
  hash?: string = '';
  mtime?: number = 0;
  size?: number = 0;
}

/** PROPFIND 多状态响应中的单个条目解析结果。 */
class PropfindItem {
  href: string = '';
  isDir: boolean = false;
  size: number = 0;
  mtime: string = '';
  etag: string = '';
}

/** BFS 枚举队列元素：待枚举的远端目录。 */
class PropfindQueueDir {
  dir: string = '';
  depth: number = 0;
}

/** 单个远端目录的 PROPFIND 枚举结果。 */
class PropfindDirResult {
  subDirs: string[] = [];
  files: RemoteEntry[] = [];
}

/** 全库 PROPFIND 枚举结果（区分服务端明确不支持 405/501 与真实异常）。 */
class PropfindResult {
  supported: boolean = true;
  entries: RemoteEntry[] = [];
}

/** 标记服务端明确不支持 PROPFIND（405 / 501）。 */
class PropfindUnsupportedError extends Error {
  constructor(code: number) {
    super(`propfind unsupported (${code})`);
  }
}

/**
 * WebDAV 同步供应方。
 *
 * 清单的读写走 @ohos.http，优先存放在隐藏目录 `.mysidian/manifest.json`
 * （兼容只读旧版根目录 `mysidian-manifest.json`），避免污染 Obsidian 文件树；
 * 目录真实枚举优先 Depth: infinity 单请求全库 PROPFIND（fnOS 实测支持，
 * 把每轮同步的带认证请求降到 1 个），不支持时回退逐层 Depth:1；
 * 严格屏蔽 `.obsidian`、`.trash`、`conflicts` 及非同步扩展名；
 * 远端删除优先通过 WebDAV `MOVE` 移入 `.trash/`，绝不发出裸 HTTP `DELETE`。
 */
export class WebDavProvider implements SyncProvider {
  private static readonly MANIFEST: string = '.mysidian/manifest.json';
  private static readonly MANIFEST_DIR: string = '.mysidian';
  private static readonly LEGACY_MANIFEST: string = 'mysidian-manifest.json';
  private static readonly MAX_PROPFIND_DEPTH: number = 8;
  private static readonly PROPFIND_CONCURRENCY: number = 1;
  /** 受控单点扩展：http.RequestMethod 枚举运行时即字符串，WebDAV 标准 PROPFIND 方法。 */
  private static readonly PROPFIND_METHOD: http.RequestMethod = 'PROPFIND' as http.RequestMethod;
  /** 受控单点扩展：http.RequestMethod 枚举运行时即字符串，WebDAV 标准 MKCOL 方法。 */
  private static readonly MKCOL_METHOD: http.RequestMethod = 'MKCOL' as http.RequestMethod;
  /** 受控单点扩展：http.RequestMethod 枚举运行时即字符串，WebDAV 标准 MOVE 方法（用于软删除）。 */
  private static readonly MOVE_METHOD: http.RequestMethod = 'MOVE' as http.RequestMethod;
  private static readonly PROPFIND_BODY: string =
    '<?xml version="1.0" encoding="utf-8"?>' +
    '<d:propfind xmlns:d="DAV:">' +
    '<d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/><d:getetag/></d:prop>' +
    '</d:propfind>';
  private static readonly MAX_RETRY_ATTEMPTS: number = 3;
  /** 429 自适应请求间距上限（毫秒），对齐 sync-engine 插件 rate-limiter 惩罚策略。 */
  private static readonly MAX_PACING_PENALTY_MS: number = 2000;
  private config: SyncConfig = new SyncConfig();
  private baseUrl: string = '';
  private createdDirs: Set<string> = new Set<string>();
  private primaryManifestFound: boolean = false;
  private manifestSnapshotKey: string = '';
  private pacingPenaltyMs: number = 0;
  private lastRequestFinishedAt: number = 0;
  /** 网关拒绝绝对 URL Destination（502）后置 true，本连接内后续 MOVE 直接用纯路径形式。 */
  private preferPathDestination: boolean = false;

  public async connect(config: SyncConfig): Promise<void> {
    this.config = config;
    this.baseUrl = WebDavProvider.buildBaseUrl(config.serverUrl, config.remoteRoot);
    this.createdDirs.clear();
    this.primaryManifestFound = false;
    this.manifestSnapshotKey = '';
    this.pacingPenaltyMs = 0;
    this.lastRequestFinishedAt = 0;
    this.preferPathDestination = false;
    LOG.info(`webdav connected: ${this.baseUrl}`);
  }

  public async list(remoteDir: string): Promise<RemoteEntry[]> {
    const manifestEntries: RemoteEntry[] = await this.listManifest();
    const propResult: PropfindResult = await this.propfindEntries();
    if (!propResult.supported) {
      return manifestEntries;
    }
    const realEntries: RemoteEntry[] = propResult.entries;
    // 以 PROPFIND 的真实文件为准；清单提供已知内容哈希，用于三方比较。
    const hashByPath: Map<string, string> = new Map<string, string>();
    for (const entry of manifestEntries) {
      hashByPath.set(entry.path, entry.etag);
    }
    const result: RemoteEntry[] = [];
    for (const real of realEntries) {
      const entry: RemoteEntry = new RemoteEntry();
      entry.path = real.path;
      const known: string | undefined = hashByPath.get(real.path);
      entry.etag = known === undefined ? '' : known;
      entry.size = real.size;
      entry.mtime = real.mtime;
      entry.serverTag = real.serverTag;
      entry.isDir = false;
      result.push(entry);
    }
    LOG.info(`webdav list: manifest=${manifestEntries.length}, real=${realEntries.length}`);
    return result;
  }

  public async readRemote(path: string): Promise<string> {
    WebDavProvider.assertSafeSyncPath(path);
    const url: string = `${this.baseUrl}/${WebDavProvider.encodePath(path)}`;
    const response: http.HttpResponse = await this.request(url, http.RequestMethod.GET,
      http.HttpDataType.STRING);
    if (response.responseCode !== 200) {
      throw new Error(WebDavProvider.describeCode(response.responseCode, 'webdav readRemote'));
    }
    return WebDavProvider.extractTextPayload(response.result, 'webdav file response is not text');
  }

  public async pull(entry: RemoteEntry, destPath: string): Promise<void> {
    WebDavProvider.assertSafeSyncPath(entry.path);
    const url: string = `${this.baseUrl}/${WebDavProvider.encodePath(entry.path)}`;
    const response: http.HttpResponse = await this.request(url, http.RequestMethod.GET,
      http.HttpDataType.STRING);
    if (response.responseCode !== 200) {
      throw new Error(WebDavProvider.describeCode(response.responseCode, 'webdav pull'));
    }
    const payload: string = WebDavProvider.extractTextPayload(
      response.result, 'webdav file response is not text');
    WebDavProvider.writeText(destPath, payload);
  }

  public async push(localPath: string, entry: RemoteEntry): Promise<string> {
    WebDavProvider.assertSafeSyncPath(entry.path);
    const url: string = `${this.baseUrl}/${WebDavProvider.encodePath(entry.path)}`;
    const content: string = WebDavProvider.readText(localPath);
    const response: http.HttpResponse = await this.request(url, http.RequestMethod.PUT,
      http.HttpDataType.STRING, content);
    if (response.responseCode === 403 || response.responseCode === 404 ||
      response.responseCode === 409) {
      // 父目录不存在：fnOS 等服务端返回 403（而非标准 409），先建目录再重试一次。
      const dir: string = WebDavProvider.dirnameOf(entry.path);
      if (dir.length > 0) {
        await this.mkdirRemote(dir);
        const retry: http.HttpResponse = await this.request(url, http.RequestMethod.PUT,
          http.HttpDataType.STRING, content);
        if (retry.responseCode >= 200 && retry.responseCode < 300) {
          return WebDavProvider.etagOf(retry);
        }
        throw new Error(WebDavProvider.describeCode(retry.responseCode, 'webdav push'));
      }
      throw new Error(`远端目录不存在(409)，请先在 WebDAV 服务端创建目录: ${this.baseUrl}`);
    }
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(WebDavProvider.describeCode(response.responseCode, 'webdav push'));
    }
    return WebDavProvider.etagOf(response);
  }

  /** 拉取远端二进制文件（图片等附件）到本地沙箱路径。 */
  public async pullBinary(entry: RemoteEntry, destPath: string): Promise<void> {
    WebDavProvider.assertSafeSyncPath(entry.path);
    const url: string = `${this.baseUrl}/${WebDavProvider.encodePath(entry.path)}`;
    const response: http.HttpResponse = await this.request(url, http.RequestMethod.GET,
      http.HttpDataType.ARRAY_BUFFER);
    if (response.responseCode !== 200) {
      throw new Error(WebDavProvider.describeCode(response.responseCode, 'webdav pullBinary'));
    }
    const buffer: ArrayBuffer | null = WebDavProvider.toArrayBuffer(response.result);
    if (buffer === null) {
      throw new Error('webdav binary response is not binary');
    }
    WebDavProvider.writeBytes(destPath, buffer);
  }

  /** 推送本地二进制文件（图片等附件），返回上传后的服务器版本标识。 */
  public async pushBinary(localPath: string, entry: RemoteEntry): Promise<string> {
    WebDavProvider.assertSafeSyncPath(entry.path);
    const url: string = `${this.baseUrl}/${WebDavProvider.encodePath(entry.path)}`;
    const data: ArrayBuffer = WebDavProvider.readBytes(localPath);
    const response: http.HttpResponse = await this.requestBinary(url, http.RequestMethod.PUT, data);
    if (response.responseCode === 403 || response.responseCode === 404 ||
      response.responseCode === 409) {
      // 父目录不存在（fnOS 以 403 表达）：先建目录再重试一次。
      const dir: string = WebDavProvider.dirnameOf(entry.path);
      if (dir.length > 0) {
        await this.mkdirRemote(dir);
        const retry: http.HttpResponse = await this.requestBinary(url, http.RequestMethod.PUT, data);
        if (retry.responseCode >= 200 && retry.responseCode < 300) {
          return WebDavProvider.etagOf(retry);
        }
        if (retry.responseCode === 409) {
          throw new Error(`远端目录不存在(409)，请先在 WebDAV 服务端创建目录: ${this.baseUrl}`);
        }
        throw new Error(WebDavProvider.describeCode(retry.responseCode, 'webdav pushBinary'));
      }
      throw new Error(`远端目录不存在(409)，请先在 WebDAV 服务端创建目录: ${this.baseUrl}`);
    }
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(WebDavProvider.describeCode(response.responseCode, 'webdav pushBinary'));
    }
    return WebDavProvider.etagOf(response);
  }

  /** 在远端创建目录（幂等：已存在视为成功；缓存本次连接已验证目录并兼容尾部斜杠差异）。 */
  public async mkdirRemote(remoteDir: string): Promise<void> {
    const trimmed: string = remoteDir.replace(/^\/+/, '').replace(/\/+$/, '');
    if (trimmed.length === 0) {
      return;
    }
    await this.mkdirSequential(this.baseUrl, trimmed, this.createdDirs);
  }

  /** 若用户配置了尚未建好的远端根目录，在服务端根下逐级尝试创建。 */
  private async ensureRemoteRoot(): Promise<boolean> {
    const rootTrimmed: string = this.config.remoteRoot.trim().replace(/^\/+/, '').replace(/\/+$/, '');
    if (rootTrimmed.length === 0) {
      return false;
    }
    const serverBase: string = WebDavProvider.trimTrailingSlashes(this.config.serverUrl.replace(/\s+/g, ''));
    const dummyCache: Set<string> = new Set<string>();
    try {
      await this.mkdirSequential(serverBase, rootTrimmed, dummyCache);
      return true;
    } catch (error) {
      LOG.warn(`auto create remoteRoot failed: ${rootTrimmed}`);
      return false;
    }
  }

  private async mkdirSequential(basePrefix: string, relativeDir: string,
    cache: Set<string>): Promise<void> {
    const segments: string[] = relativeDir.split('/');
    let current: string = '';
    for (const segment of segments) {
      if (segment.length === 0) {
        continue;
      }
      current = current.length === 0 ? segment : `${current}/${segment}`;
      if (cache.has(current)) {
        continue;
      }
      const baseSegmentUrl: string = `${basePrefix}/${WebDavProvider.encodePath(current)}`;
      // RFC 4918 集合资源推荐带尾斜杠；若遇不识别尾斜杠或重定向的服务端，回退无尾斜杠重试一次。
      const response: http.HttpResponse = await this.request(`${baseSegmentUrl}/`,
        WebDavProvider.MKCOL_METHOD, http.HttpDataType.STRING);
      if ((response.responseCode >= 200 && response.responseCode < 300) ||
        response.responseCode === 405) {
        cache.add(current);
        continue;
      }
      const code: number = response.responseCode;
      if (code === 301 || code === 302 || code === 307 || code === 308 ||
        code === 400 || code === 403 || code === 404 || code === 409) {
        const fallback: http.HttpResponse = await this.request(baseSegmentUrl,
          WebDavProvider.MKCOL_METHOD, http.HttpDataType.STRING);
        if ((fallback.responseCode >= 200 && fallback.responseCode < 300) ||
          fallback.responseCode === 405 || fallback.responseCode === 301) {
          cache.add(current);
          continue;
        }
        throw new Error(WebDavProvider.describeCode(fallback.responseCode, 'webdav mkdir'));
      }
      throw new Error(WebDavProvider.describeCode(code, 'webdav mkdir'));
    }
  }

  /**
   * 软删除远端文件：通过 WebDAV MOVE 移入 `.trash/`，绝不发出 HTTP DELETE。
   * 服务端不支持 MOVE 或目标/反向代理拒绝时返回 UNSUPPORTED，保留远端文件不动。
   */
  public async trashRemote(path: string, trashPath: string): Promise<RemoteTrashStatus> {
    WebDavProvider.assertSafeSyncPath(path);
    if (!SyncPathGuard.isValidTrashPath(trashPath)) {
      throw new Error(`非法远端回收站路径已拦截: ${trashPath}`);
    }
    try {
      const dir: string = WebDavProvider.dirnameOf(trashPath);
      if (dir.length > 0) {
        await this.mkdirRemote(dir);
      }
      const sourceUrl: string = `${this.baseUrl}/${WebDavProvider.encodePath(path)}`;
      let response: http.HttpResponse = await this.request(sourceUrl,
        WebDavProvider.MOVE_METHOD, http.HttpDataType.STRING, undefined, {
          'Destination': this.destinationHeaderOf(trashPath),
          'Overwrite': 'F'
        });
      if (response.responseCode === 502 && !this.preferPathDestination) {
        // 部分网关（如 fnOS 中继）拒绝绝对 URL 形式的 Destination（实测返回 502，
        // 而纯路径形式 201）。降级为路径形式重试一次，成功后本连接内后续 MOVE 直接用路径形式。
        LOG.warn('webdav MOVE got 502 with absolute Destination, retrying with path-only');
        response = await this.request(sourceUrl,
          WebDavProvider.MOVE_METHOD, http.HttpDataType.STRING, undefined, {
            'Destination': this.destinationPathOf(trashPath),
            'Overwrite': 'F'
          });
        this.preferPathDestination = response.responseCode >= 200 && response.responseCode < 300;
      }
      let lastCode: number = response.responseCode;
      if (lastCode >= 200 && lastCode < 300) {
        return RemoteTrashStatus.MOVED;
      }
      if (lastCode === 404) {
        return RemoteTrashStatus.NOT_FOUND;
      }
      if (lastCode === 412) {
        const retryTrashPath: string = WebDavProvider.withCollisionSuffix(trashPath);
        const retryDestination: string = this.preferPathDestination
          ? this.destinationPathOf(retryTrashPath)
          : this.destinationHeaderOf(retryTrashPath);
        const retry: http.HttpResponse = await this.request(sourceUrl,
          WebDavProvider.MOVE_METHOD, http.HttpDataType.STRING, undefined, {
            'Destination': retryDestination,
            'Overwrite': 'F'
          });
        lastCode = retry.responseCode;
        if (lastCode >= 200 && lastCode < 300) {
          return RemoteTrashStatus.MOVED;
        }
      }
      if (WebDavProvider.isTransientHttpCode(lastCode)) {
        // 认证过期/限流/服务端 5xx 是瞬时故障：抛错让引擎保留原 synced 基线，下轮重试软删；
        // 吞成 UNSUPPORTED 会写 local_deleted 墓碑，删除传播从此被永久跳过。
        throw new Error(WebDavProvider.describeCode(lastCode, 'webdav MOVE'));
      }
      LOG.warn(`webdav MOVE to .trash skipped (code=${lastCode}): ${path}`);
      return RemoteTrashStatus.UNSUPPORTED;
    } catch (error) {
      const err = error as BusinessError;
      // 不能把瞬时故障（401/403 中途封禁、超时、MKCOL 失败）吞成 UNSUPPORTED：
      // UNSUPPORTED 会写永久 local_deleted 墓碑，导致删除永不被重试、
      // 且远端后续修改会把已删文件复活。向上抛出由引擎按可重试错误处理。
      LOG.warn(`webdav MOVE failed, rethrowing for retry (${path}): ${err.message}`);
      throw error as Error;
    }
  }

  /**
   * 瞬时故障判定：认证过期/封禁（401/403/407）、超时（408）、资源被临时锁定（423，
   * 部分服务器在并发写入/整理期间短暂返回）、限流（429）、
   * 服务端错误（5xx，501「未实现」除外）。此类失败应重试而非永久跳过。
   */
  private static isTransientHttpCode(code: number): boolean {
    return code === 401 || code === 403 || code === 407 || code === 408 ||
      code === 423 || code === 429 || (code >= 500 && code !== 501);
  }

  /** 兼容保留接口：生产同步路径禁用直接 HTTP DELETE，防止误删 Obsidian 远端文件。 */
  public async deleteRemote(path: string): Promise<void> {
    WebDavProvider.assertSafeSyncPath(path);
    throw new Error('直接 HTTP DELETE 已被禁用，请使用移入 .trash/ 软删除或手动保留远端');
  }

  public async stat(path: string): Promise<RemoteEntry | null> {
    WebDavProvider.assertSafeSyncPath(path);
    const url: string = `${this.baseUrl}/${WebDavProvider.encodePath(path)}`;
    const response: http.HttpResponse = await this.request(url, http.RequestMethod.HEAD,
      http.HttpDataType.STRING);
    if (response.responseCode === 404) {
      return null;
    }
    const entry: RemoteEntry = new RemoteEntry();
    entry.path = path;
    entry.isDir = false;
    if (response.responseCode >= 200 && response.responseCode < 300) {
      entry.serverTag = WebDavProvider.headerValueOf(response,
        ['getetag', 'GetETag', 'GETETAG']);
      const sizeText: string = WebDavProvider.headerValueOf(response,
        ['content-length', 'Content-Length', 'CONTENT-LENGTH']).trim();
      const size: number = Number(sizeText);
      if (!Number.isNaN(size) && size > 0) {
        entry.size = size;
      }
      return entry;
    }
    // 服务器不支持 HEAD 或其他异常状态：保守视为远端仍存在，交由调用方跳过本地删除。
    LOG.warn(`webdav stat unexpected code (${response.responseCode}): ${path}`);
    return entry;
  }

  public async putManifest(entries: RemoteEntry[]): Promise<void> {
    const files: WebDavFileRaw[] = [];
    for (const entry of entries) {
      if (!SyncPathGuard.isSafeSyncPath(entry.path)) {
        continue;
      }
      const item: WebDavFileRaw = new WebDavFileRaw();
      item.path = entry.path;
      item.hash = entry.etag;
      item.mtime = entry.mtime;
      item.size = entry.size;
      files.push(item);
    }
    const nextKey: string = WebDavProvider.manifestKeyOfRaw(files);
    if (this.primaryManifestFound && nextKey === this.manifestSnapshotKey) {
      LOG.info('manifest unchanged, skip PUT');
      return;
    }
    const manifest: WebDavManifestRaw = new WebDavManifestRaw();
    manifest.version = '1';
    manifest.files = files;
    const body: string = JSON.stringify(manifest);
    const url: string = `${this.baseUrl}/${WebDavProvider.encodePath(WebDavProvider.MANIFEST)}`;
    const response: http.HttpResponse = await this.request(url, http.RequestMethod.PUT,
      http.HttpDataType.STRING, body);
    if (response.responseCode === 403 || response.responseCode === 404 ||
      response.responseCode === 409) {
      await this.mkdirRemote(WebDavProvider.MANIFEST_DIR);
      const retry: http.HttpResponse = await this.request(url, http.RequestMethod.PUT,
        http.HttpDataType.STRING, body);
      if (retry.responseCode >= 200 && retry.responseCode < 300) {
        this.primaryManifestFound = true;
        this.manifestSnapshotKey = nextKey;
        return;
      }
      if (retry.responseCode === 409) {
        throw new Error(`远端目录不存在(409)，请先在 WebDAV 服务端创建目录: ${this.baseUrl}`);
      }
      throw new Error(WebDavProvider.describeCode(retry.responseCode, 'webdav manifest write'));
    }
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(WebDavProvider.describeCode(response.responseCode, 'webdav manifest write'));
    }
    this.primaryManifestFound = true;
    this.manifestSnapshotKey = nextKey;
  }

  /** 增量更新 `.mysidian/manifest.json` 中的单个条目（冲突确认覆盖远端后调用）。 */
  public async patchManifestEntry(entry: RemoteEntry): Promise<void> {
    WebDavProvider.assertSafeSyncPath(entry.path);
    const current: RemoteEntry[] = await this.listManifest();
    const updated: RemoteEntry[] = [];
    let replaced: boolean = false;
    for (const item of current) {
      if (item.path === entry.path) {
        updated.push(entry);
        replaced = true;
      } else {
        updated.push(item);
      }
    }
    if (!replaced) {
      updated.push(entry);
    }
    this.manifestSnapshotKey = '';
    await this.putManifest(updated);
  }

  /** 读取远端清单条目；优先 `.mysidian/manifest.json`，不存在时只读兼容旧版根目录清单。 */
  private async listManifest(): Promise<RemoteEntry[]> {
    const primaryUrl: string = `${this.baseUrl}/${WebDavProvider.encodePath(WebDavProvider.MANIFEST)}`;
    let response: http.HttpResponse = await this.request(primaryUrl, http.RequestMethod.GET,
      http.HttpDataType.STRING);
    let fromPrimary: boolean = response.responseCode === 200;
    if (response.responseCode === 404) {
      const legacyUrl: string = `${this.baseUrl}/${WebDavProvider.LEGACY_MANIFEST}`;
      response = await this.request(legacyUrl, http.RequestMethod.GET, http.HttpDataType.STRING);
    }
    if (response.responseCode === 404) {
      this.primaryManifestFound = false;
      this.manifestSnapshotKey = '';
      return [];
    }
    if (response.responseCode !== 200) {
      throw new Error(WebDavProvider.describeCode(response.responseCode, 'webdav list'));
    }
    const payload: string = WebDavProvider.extractTextPayload(
      response.result, 'webdav manifest response is not text');
    const parsed: RemoteEntry[] = WebDavProvider.parseManifest(payload);
    this.primaryManifestFound = fromPrimary;
    this.manifestSnapshotKey = fromPrimary ? WebDavProvider.manifestKeyOfEntries(parsed) : '';
    return parsed;
  }

  private static manifestKeyOfRaw(files: WebDavFileRaw[]): string {
    const pairs: string[] = [];
    for (const item of files) {
      pairs.push(`${item.path ?? ''}\t${item.hash ?? ''}`);
    }
    pairs.sort();
    return pairs.join('\n');
  }

  private static manifestKeyOfEntries(entries: RemoteEntry[]): string {
    const pairs: string[] = [];
    for (const item of entries) {
      pairs.push(`${item.path}\t${item.etag}`);
    }
    pairs.sort();
    return pairs.join('\n');
  }

  /**
   * 通过 PROPFIND 枚举远端真实同步条目。
   * 优先尝试 Depth: infinity 单请求全库枚举（fnOS 等服务端支持，把每轮同步的
   * 带认证请求从几十个降到 1 个，从根本上避免认证突发限流/防暴力破解）；
   * 服务端明确拒绝 infinity 时回退逐层 Depth:1 BFS。
   * 仅当服务端明确返回 405/501 不支持 PROPFIND 时才回退清单模式；
   * 任何鉴权、网络或子目录枚举失败都必须向上抛出中止本轮同步，
   * 防止用残缺清单误判远端或本地删除。
   */
  private async propfindEntries(): Promise<PropfindResult> {
    const out: PropfindResult = new PropfindResult();
    try {
      const fast: RemoteEntry[] | null = await this.propfindRecursive();
      if (fast !== null) {
        out.supported = true;
        out.entries = fast;
        return out;
      }
      const queue: PropfindQueueDir[] = [];
      const rootItem: PropfindQueueDir = new PropfindQueueDir();
      queue.push(rootItem);
      const visitedDirs: Set<string> = new Set<string>(['']);
      const seenFiles: Set<string> = new Set<string>();
      const files: RemoteEntry[] = [];
      while (queue.length > 0) {
        const take: number = Math.min(queue.length, WebDavProvider.PROPFIND_CONCURRENCY);
        const batch: PropfindQueueDir[] = queue.splice(0, take);
        const results: PropfindDirResult[] = await Promise.all(batch.map(
          (item: PropfindQueueDir): Promise<PropfindDirResult> => {
            return this.propfindOneDir(item);
          }));
        for (let r = 0; r < results.length; r++) {
          const result: PropfindDirResult = results[r];
          const parent: PropfindQueueDir = batch[r];
          for (const sub of result.subDirs) {
            if (!visitedDirs.has(sub)) {
              visitedDirs.add(sub);
              const next: PropfindQueueDir = new PropfindQueueDir();
              next.dir = sub;
              next.depth = parent.depth + 1;
              queue.push(next);
            }
          }
          for (const file of result.files) {
            if (!seenFiles.has(file.path)) {
              seenFiles.add(file.path);
              files.push(file);
            }
          }
        }
      }
      out.supported = true;
      out.entries = files;
      return out;
    } catch (error) {
      if (error instanceof PropfindUnsupportedError) {
        LOG.info(`propfind unsupported by server, fallback to manifest: ${error.message}`);
        out.supported = false;
        return out;
      }
      throw error as Error;
    }
  }

  /**
   * Depth: infinity 单请求全库枚举（fnOS 实测支持，LAN 与中继均 207）。
   * 服务端明确拒绝 infinity（400/403/405/501/507）时返回 null 回退逐层 BFS；
   * 鉴权失败（401）等其他错误照常上抛，不额外消耗认证尝试。
   */
  private async propfindRecursive(): Promise<RemoteEntry[] | null> {
    let response: http.HttpResponse = await this.sendPropfind(this.baseUrl, 'infinity');
    if (response.responseCode === 301 || response.responseCode === 302 ||
      response.responseCode === 307 || response.responseCode === 308) {
      const slashUrl: string = this.baseUrl.endsWith('/') ? this.baseUrl : `${this.baseUrl}/`;
      response = await this.sendPropfind(slashUrl, 'infinity');
    }
    if (response.responseCode === 400 || response.responseCode === 403 ||
      response.responseCode === 405 || response.responseCode === 501 ||
      response.responseCode === 507) {
      LOG.info(`propfind depth-infinity refused (${response.responseCode}), fallback to depth-1 bfs`);
      return null;
    }
    if (response.responseCode !== 207 && response.responseCode !== 200) {
      LOG.error(`propfind depth-infinity ${response.responseCode} on ${this.baseUrl}`);
      throw new Error(WebDavProvider.describeCode(response.responseCode, 'webdav propfind'));
    }
    const payload: string = WebDavProvider.extractTextPayload(
      response.result, 'propfind response is not text');
    const items: PropfindItem[] = WebDavProvider.parseMultistatus(payload);
    const files: RemoteEntry[] = [];
    for (const it of items) {
      const rel: string | null = this.hrefToRelative(it.href);
      if (rel === null || rel.length === 0 || it.isDir) {
        continue;
      }
      if (WebDavProvider.hasIgnoredSegment(rel) ||
        rel === WebDavProvider.MANIFEST || rel === WebDavProvider.LEGACY_MANIFEST) {
        continue;
      }
      if (!SyncPathGuard.isSafeSyncPath(rel)) {
        continue;
      }
      const entry: RemoteEntry = new RemoteEntry();
      entry.path = rel;
      entry.etag = '';
      entry.size = it.size;
      const parsedMtime: number = Date.parse(it.mtime);
      entry.mtime = Number.isNaN(parsedMtime) ? 0 : parsedMtime;
      entry.serverTag = it.etag.length > 0 ? it.etag : `${entry.mtime}~${entry.size}`;
      entry.isDir = false;
      files.push(entry);
    }
    LOG.info(`propfind depth-infinity ok: ${items.length} responses, ${files.length} sync files`);
    return files;
  }

  /** PROPFIND 单个远端目录（Depth:1），返回受信任的子目录与同步文件。 */
  private async propfindOneDir(item: PropfindQueueDir): Promise<PropfindDirResult> {
    const result: PropfindDirResult = new PropfindDirResult();
    if (item.depth > WebDavProvider.MAX_PROPFIND_DEPTH) {
      // 不能静默返回空结果：超出深度上限的文件会从远端清单中消失，
      // 本地同名文件会被误判为新增而盲推送覆盖远端。向上抛出中止本轮
      // 同步，由上层按同步失败处理（与"枚举失败必须中止"的策略一致）。
      throw new Error(`webdav bfs depth exceeded (${item.depth} > ${WebDavProvider.MAX_PROPFIND_DEPTH}): ${item.dir}`);
    }
    const url: string = item.dir.length === 0 ? this.baseUrl
      : `${this.baseUrl}/${WebDavProvider.encodePath(item.dir)}`;
    let response: http.HttpResponse = await this.sendPropfind(url);
    if (response.responseCode === 301 || response.responseCode === 302 ||
      response.responseCode === 307 || response.responseCode === 308 ||
      response.responseCode === 404) {
      const slashUrl: string = url.endsWith('/') ? url : `${url}/`;
      if (slashUrl !== url) {
        const retrySlash: http.HttpResponse = await this.sendPropfind(slashUrl);
        // 仅当尾斜杠重试真正成功（207/200）才采纳；失败时保留原响应，
        // 让下方 404 根目录恢复与错误路径按原状态码继续判断。
        if (retrySlash.responseCode === 207 || retrySlash.responseCode === 200) {
          response = retrySlash;
        }
      }
    }
    if (response.responseCode === 404 && item.dir.length === 0 &&
      this.config.remoteRoot.trim().length > 0 && await this.ensureRemoteRoot()) {
      const rootUrl: string = url.endsWith('/') ? url : `${url}/`;
      response = await this.sendPropfind(rootUrl);
    }
    if (response.responseCode !== 207 && response.responseCode !== 200) {
      LOG.error(`propfind ${response.responseCode} on ${url}`);
      if (item.dir.length === 0 &&
        (response.responseCode === 405 || response.responseCode === 501)) {
        throw new PropfindUnsupportedError(response.responseCode);
      }
      throw new Error(WebDavProvider.describeCode(response.responseCode, 'webdav propfind'));
    }
    const payload: string = WebDavProvider.extractTextPayload(
      response.result, 'propfind response is not text');
    const items: PropfindItem[] = WebDavProvider.parseMultistatus(payload);
    for (const it of items) {
      const rel: string | null = this.hrefToRelative(it.href);
      if (rel === null || rel.length === 0) {
        continue;
      }
      if (rel === item.dir) {
        continue;
      }
      const name: string = WebDavProvider.lastNameOf(rel);
      if (it.isDir) {
        if (WebDavProvider.hasIgnoredSegment(rel) || SyncPathGuard.isIgnoredDirName(name)) {
          continue;
        }
        result.subDirs.push(rel);
        continue;
      }
      if (rel === WebDavProvider.MANIFEST || rel === WebDavProvider.LEGACY_MANIFEST) {
        continue;
      }
      if (!SyncPathGuard.isSafeSyncPath(rel)) {
        continue;
      }
      const entry: RemoteEntry = new RemoteEntry();
      entry.path = rel;
      entry.etag = '';
      entry.size = it.size;
      const parsedMtime: number = Date.parse(it.mtime);
      entry.mtime = Number.isNaN(parsedMtime) ? 0 : parsedMtime;
      entry.serverTag = it.etag.length > 0 ? it.etag : `${entry.mtime}~${entry.size}`;
      entry.isDir = false;
      result.files.push(entry);
    }
    return result;
  }

  private static assertSafeSyncPath(path: string): void {
    if (!SyncPathGuard.isSafeSyncPath(path)) {
      throw new Error(`受保护或非同步路径已拦截: ${path}`);
    }
  }

  private static hasIgnoredSegment(path: string): boolean {
    const segs: string[] = path.split('/');
    for (const seg of segs) {
      if (SyncPathGuard.isIgnoredDirName(seg)) {
        return true;
      }
    }
    return false;
  }

  private static withCollisionSuffix(trashPath: string): string {
    const slash: number = trashPath.lastIndexOf('/');
    const dir: string = slash >= 0 ? trashPath.substring(0, slash + 1) : '';
    const file: string = slash >= 0 ? trashPath.substring(slash + 1) : trashPath;
    const dot: number = file.lastIndexOf('.');
    const suffix: string = `_${Date.now()}`;
    if (dot <= 0) {
      return `${dir}${file}${suffix}`;
    }
    return `${dir}${file.substring(0, dot)}${suffix}${file.substring(dot)}`;
  }

  /** 取路径最后一段名称。 */
  private static lastNameOf(path: string): string {
    const idx: number = path.lastIndexOf('/');
    return idx < 0 ? path : path.substring(idx + 1);
  }

  private async sendPropfind(targetUrl: string, depth: string = '1'): Promise<http.HttpResponse> {
    return this.request(targetUrl, WebDavProvider.PROPFIND_METHOD,
      http.HttpDataType.STRING, WebDavProvider.PROPFIND_BODY,
      { 'Depth': depth, 'Content-Type': 'application/xml;charset=utf-8' });
  }

  /** 将 multistatus XML 中的 href 转为相对 baseUrl 的路径；无法映射时返回 null。 */
  private hrefToRelative(href: string): string | null {
    if (href.length === 0) {
      return null;
    }
    const rawBasePath: string = WebDavProvider.urlPathOf(this.baseUrl);
    const decodedBasePath: string = WebDavProvider.decodePathSafe(rawBasePath);
    let rawHref: string = href;
    if (rawHref.startsWith('http://') || rawHref.startsWith('https://')) {
      rawHref = WebDavProvider.urlPathOf(rawHref);
    }
    let path: string = WebDavProvider.decodePathSafe(rawHref);
    if (decodedBasePath.length > 0 && path.startsWith(decodedBasePath)) {
      path = path.substring(decodedBasePath.length);
    } else if (rawBasePath.length > 0 && path.startsWith(rawBasePath)) {
      path = path.substring(rawBasePath.length);
    } else {
      // 部分服务端返回相对 href：回退按路径段匹配远端根目录。
      // 用整段比较而非 indexOf 子串定位，避免根目录名是其它路径段
      // 的子串时（如 notes2026/）解析错位。
      const rootName: string = this.config.remoteRoot.trim();
      const rootSegs: string[] = rootName.split('/').filter(
        (seg: string): boolean => seg.length > 0);
      if (rootSegs.length > 0) {
        const segs: string[] = path.split('/');
        let found: number = -1;
        for (let i = segs.length - rootSegs.length; i >= 0; i--) {
          let matched: boolean = true;
          for (let k = 0; k < rootSegs.length; k++) {
            if (segs[i + k] !== rootSegs[k]) {
              matched = false;
              break;
            }
          }
          if (matched) {
            found = i;
            break;
          }
        }
        if (found < 0) {
          return null;
        }
        path = segs.slice(found + rootSegs.length).join('/');
      }
      // rootSegs 为空：远端根即服务器根，href 路径本身就是相对路径，
      // 直接走下方去斜杠与安全校验（此前返回 null 会把整个远端判空，
      // 触发全量盲推送覆盖远端文件）。
    }
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    // 目录 href 通常带尾斜杠，与文件路径统一为无尾斜杠形式，
    // 避免目录被误判为新子目录而重复递归枚举。
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    // 路径穿越防护：任何路径段不得为 ".."/"."，防止异常/恶意
    // 服务端响应让 pull 把文件写到 vault 沙箱之外。
    if (!WebDavProvider.isSafeRelativePath(path)) {
      return null;
    }
    return path;
  }

  private static decodePathSafe(raw: string): string {
    try {
      return decodeURIComponent(raw);
    } catch (error) {
      return raw;
    }
  }

  /**
   * 相对路径安全校验：拒绝绝对路径、反斜杠、空段与 "."/".." 穿越段。
   */
  private static isSafeRelativePath(path: string): boolean {
    if (path.length === 0 || path.startsWith('/') || path.includes('\\')) {
      return false;
    }
    const segments: string[] = path.split('/');
    for (const seg of segments) {
      if (seg === '..' || seg === '.' || seg.length === 0) {
        return false;
      }
    }
    return true;
  }

  /** 取 URL 的路径部分（不含协议与主机）。 */
  private static urlPathOf(url: string): string {
    const schemeIdx: number = url.indexOf('://');
    let rest: string = schemeIdx < 0 ? url : url.substring(schemeIdx + 3);
    const slashIdx: number = rest.indexOf('/');
    return slashIdx < 0 ? '' : rest.substring(slashIdx);
  }

  /**
   * XML 命名实体反转义。文件名中的 & 在 multistatus 响应中为 &amp;，
   * 未反转义会导致 GET 路径与真实文件名不符（404）。&amp; 必须最后处理。
   */
  private static xmlUnescape(text: string): string {
    let out: string = text;
    out = out.replaceAll('&lt;', '<');
    out = out.replaceAll('&gt;', '>');
    out = out.replaceAll('&quot;', '"');
    out = out.replaceAll('&apos;', "'");
    out = out.replaceAll('&amp;', '&');
    return out;
  }

  /**
   * 解析 PROPFIND multistatus 响应。WebDAV 命名空间前缀不固定（D:/d:/无前缀），
   * 采用对前缀不敏感的正则提取 response/href/collection/getcontentlength/getlastmodified。
   */
  private static parseMultistatus(text: string): PropfindItem[] {
    const items: PropfindItem[] = [];
    const responseRe: RegExp = /<(?:[A-Za-z0-9_.-]+:)?response(?:\s[^>]*)?>([\s\S]*?)<\/(?:[A-Za-z0-9_.-]+:)?response>/g;
    let match: RegExpExecArray | null = responseRe.exec(text);
    while (match !== null) {
      const block: string = match[1];
      const item: PropfindItem = new PropfindItem();
      const hrefMatch: RegExpExecArray | null =
        /<(?:[A-Za-z0-9_.-]+:)?href(?:\s[^>]*)?>([\s\S]*?)<\/(?:[A-Za-z0-9_.-]+:)?href>/.exec(block);
      if (hrefMatch !== null) {
        item.href = WebDavProvider.xmlUnescape(hrefMatch[1].trim());
      }
      item.isDir = /<(?:[A-Za-z0-9_.-]+:)?collection[\s/>]/.test(block);
      const sizeMatch: RegExpExecArray | null =
        /<(?:[A-Za-z0-9_.-]+:)?getcontentlength(?:\s[^>]*)?>([\s\S]*?)<\/(?:[A-Za-z0-9_.-]+:)?getcontentlength>/.exec(block);
      if (sizeMatch !== null) {
        const parsed: number = Number(sizeMatch[1].trim());
        item.size = Number.isNaN(parsed) ? 0 : parsed;
      }
      const mtimeMatch: RegExpExecArray | null =
        /<(?:[A-Za-z0-9_.-]+:)?getlastmodified(?:\s[^>]*)?>([\s\S]*?)<\/(?:[A-Za-z0-9_.-]+:)?getlastmodified>/.exec(block);
      if (mtimeMatch !== null) {
        item.mtime = mtimeMatch[1].trim();
      }
      const etagMatch: RegExpExecArray | null =
        /<(?:[A-Za-z0-9_.-]+:)?getetag(?:\s[^>]*)?>([^<]*)<\/(?:[A-Za-z0-9_.-]+:)?getetag>/.exec(block);
      if (etagMatch !== null) {
        const etagText: string = WebDavProvider.xmlUnescape(etagMatch[1].trim());
        // 部分服务器（如 fnOS）在 404 propstat 中返回空 getetag，视为无值。
        if (etagText.length > 2 && etagText !== '""') {
          item.etag = etagText;
        }
      }
      if (item.href.length > 0) {
        items.push(item);
      }
      match = responseRe.exec(text);
    }
    return items;
  }

  public async disconnect(): Promise<void> {
    // 请求实例已按次创建/销毁，无长生命周期资源需要释放。
  }

  /**
   * 发送 HTTP 请求（对齐 sync-engine 插件的重试与限流策略：
   * 401 不重试——认证失败立即上抛，不喂服务器防暴力破解计数，由冷却机制接管；
   * 408/425/429/5xx/网络异常用全抖动指数退避重试；429 触发自适应请求间距惩罚，
   * 成功响应逐步衰减）。每次尝试创建独立 HttpRequest 实例并在完成后销毁，
   * 防止并发认证头竞态丢失。
   */
  private async request(url: string, method: http.RequestMethod, expect: http.HttpDataType,
    body?: string | ArrayBuffer, extraHeaders?: Record<string, string>): Promise<http.HttpResponse> {
    if (this.baseUrl.length === 0) {
      throw new Error('webdav provider is not connected');
    }
    let attempt: number = 0;
    while (true) {
      try {
        const response: http.HttpResponse = await this.sendOnce(
          url, method, expect, body, extraHeaders);
        if (response.responseCode === 429) {
          this.pacingPenaltyMs = Math.min(Math.max(this.pacingPenaltyMs * 2, 10),
            WebDavProvider.MAX_PACING_PENALTY_MS);
        } else if (response.responseCode < 200 || response.responseCode >= 300) {
          this.pacingPenaltyMs = this.pacingPenaltyMs * 0.75;
          if (this.pacingPenaltyMs < 1) {
            this.pacingPenaltyMs = 0;
          }
        }
        if (WebDavProvider.isRetryableStatus(response.responseCode) &&
          attempt < WebDavProvider.MAX_RETRY_ATTEMPTS) {
          const waitMs: number = WebDavProvider.computeRetryDelayMs(attempt, response);
          attempt++;
          LOG.warn(`webdav HTTP ${response.responseCode}, retry #${attempt} after ${waitMs}ms`);
          await WebDavProvider.delay(waitMs);
          continue;
        }
        return response;
      } catch (error) {
        if (attempt < WebDavProvider.MAX_RETRY_ATTEMPTS) {
          const waitMs: number = WebDavProvider.computeRetryDelayMs(attempt, null);
          attempt++;
          const err = error as BusinessError;
          LOG.warn(`webdav transient error (${err.code ?? ''}), retry #${attempt} after ${waitMs}ms: ${err.message}`);
          await WebDavProvider.delay(waitMs);
          continue;
        }
        throw error as Error;
      }
    }
  }

  private async sendOnce(url: string, method: http.RequestMethod, expect: http.HttpDataType,
    body?: string | ArrayBuffer, extraHeaders?: Record<string, string>): Promise<http.HttpResponse> {
    if (this.pacingPenaltyMs > 0) {
      const elapsedMs: number = Date.now() - this.lastRequestFinishedAt;
      const waitMs: number = this.pacingPenaltyMs - elapsedMs;
      if (waitMs > 0) {
        await WebDavProvider.delay(waitMs);
      }
    }
    const request: http.HttpRequest = http.createHttp();
    try {
      const headers: Record<string, string> = this.buildHeaders();
      if (extraHeaders !== undefined) {
        const keys: string[] = Object.keys(extraHeaders);
        for (const key of keys) {
          const value: string | undefined = extraHeaders[key];
          if (value !== undefined) {
            headers[key] = value;
          }
        }
      }
      const options: http.HttpRequestOptions = {
        method: method,
        expectDataType: expect,
        header: headers,
        readTimeout: 30000,
        connectTimeout: 15000
      };
      if (this.config.skipCertVerify) {
        options.remoteValidation = 'skip';
      } else if (this.config.caCertPath.length > 0) {
        options.caPath = this.config.caCertPath;
      }
      // 空字符串 body 不能赋给 extraData：OH http 模块会抛 401 Parameter error
      // （推送 0 字节笔记曾被误判为认证失败触发 300s 冷却）；空 body 直接省略。
      if (body !== undefined && (typeof body !== 'string' || body.length > 0)) {
        options.extraData = body;
      }
      const response: http.HttpResponse = await request.request(url, options);
      this.lastRequestFinishedAt = Date.now();
      return response;
    } finally {
      request.destroy();
    }
  }

  /**
   * 可重试状态集合，对齐 sync-engine 插件：401 不在其中——认证失败立即上抛
   * （由 SyncViewModel 冷却机制暂停自动同步），绝不重试以免喂大 fnOS 等
   * 服务器的防暴力破解计数；425/500 一并纳入瞬时故障重试。
   */
  private static isRetryableStatus(code: number): boolean {
    return code === 408 || code === 425 || code === 429 ||
      code === 500 || code === 502 || code === 503 || code === 504;
  }

  /** 全抖动指数退避（对齐 sync-engine 插件 retryDelay）：random × min(1000×2^n, 30s)。 */
  private static computeRetryDelayMs(attempt: number, response: http.HttpResponse | null): number {
    if (response !== null) {
      const retryAfterRaw: string = WebDavProvider.headerValueOf(
        response, ['retry-after', 'Retry-After', 'RETRY-AFTER']);
      const seconds: number = Number(retryAfterRaw.trim());
      if (!Number.isNaN(seconds) && seconds > 0) {
        return Math.min(Math.max(Math.round(seconds * 1000), 300), 30000);
      }
    }
    const baseMs: number = Math.min(1000 * Math.pow(2, attempt), 30000);
    return Math.max(100, Math.round(Math.random() * baseMs));
  }

  private static async delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout((): void => {
        resolve();
      }, ms);
    });
  }

  /** 将 HTTP 状态码翻译为带排查建议的中文提示。 */
  private static describeCode(code: number, action: string): string {
    if (code === 400) {
      return `服务器拒绝请求(400)：若使用明文 http://，请确认端口没有指向 HTTPS 服务（nginx 会返回 400）`;
    }
    if (code === 401) {
      return `认证失败(401)：请检查 WebDAV 用户名与应用密码；` +
        `若凭据无误，可能已触发服务器防暴力破解保护，请稍候数分钟再试` +
        `（期间已暂停自动同步，可稍后手动重试）`;
    }
    if (code === 403) {
      return `无权限(403)，该账号可能没有此目录的读写权限`;
    }
    if (code === 404) {
      return `远端路径不存在(404)，请检查 WebDAV 远端目录配置 (${action})`;
    }
    if (code === 405) {
      return `方法不被允许(405)，服务端可能不支持 ${action}`;
    }
    if (code === 423) {
      return `远端文件被锁定(423)，可能正在被桌面端同步占用`;
    }
    if (code === 429) {
      return `WebDAV 请求过于频繁(429)，已自动退避重试但仍被限流，请稍后再试`;
    }
    if (code === 500 || code === 502 || code === 503 || code === 504) {
      return `WebDAV 服务端暂时不可用(${code})，网络稳定后将自动恢复`;
    }
    return `${action} failed with code ${code}`;
  }

  private buildHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'text/plain; charset=utf-8'
    };
    if (this.config.username.length > 0) {
      const raw: string = `${this.config.username}:${this.config.password}`;
      const encoder: util.TextEncoder = util.TextEncoder.create();
      const encoded: string = new util.Base64Helper().encodeToStringSync(encoder.encodeInto(raw));
      headers['Authorization'] = `Basic ${encoded}`;
    }
    return headers;
  }

  private static trimTrailingSlashes(url: string): string {
    let trimmed: string = url;
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  private static buildBaseUrl(serverUrl: string, remoteRoot: string): string {
    const base: string = serverUrl.replace(/\s+/g, '');
    if (base.length === 0) {
      throw new Error('服务器地址为空：请填写以 http:// 或 https:// 开头的完整地址');
    }
    const trimmed: string = WebDavProvider.trimTrailingSlashes(base);
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      throw new Error(`服务器地址无效：请以 http:// 或 https:// 开头，` +
        `如 https://dav.jianguoyun.com/dav（当前填写 "${serverUrl.trim()}"）`);
    }
    // 去掉根目录首尾斜杠（remoteRoot="/" 归一为空，避免拼出 "//" 请求路径）。
    const root: string = WebDavProvider.trimTrailingSlashes(
      remoteRoot.trim().replace(/^\/+/, ''));
    if (root.length === 0) {
      return trimmed;
    }
    return `${trimmed}/${WebDavProvider.encodePath(root)}`;
  }

  /** 按路径段做 URL 编码，支持中文/空格文件名。 */
  private static encodePath(path: string): string {
    const segments: string[] = path.split('/');
    const encoded: string[] = [];
    for (const segment of segments) {
      if (segment.length > 0) {
        encoded.push(encodeURIComponent(segment));
      }
    }
    return encoded.join('/');
  }

  /** MOVE Destination 头：默认 RFC 4918 绝对 URL；网关拒绝（502）后改用纯路径形式。 */
  private destinationHeaderOf(remotePath: string): string {
    if (this.preferPathDestination) {
      return this.destinationPathOf(remotePath);
    }
    return `${this.baseUrl}/${WebDavProvider.encodePath(remotePath)}`;
  }

  /** 从 baseUrl 提取 URL 路径前缀，拼出纯路径形式的 Destination（如 /webdav/obsidian/.trash/x.md）。 */
  private destinationPathOf(remotePath: string): string {
    let rest: string = this.baseUrl;
    const schemeIdx: number = rest.indexOf('://');
    if (schemeIdx >= 0) {
      rest = rest.substring(schemeIdx + 3);
    }
    const slashIdx: number = rest.indexOf('/');
    const basePath: string = slashIdx >= 0 ? rest.substring(slashIdx) : '';
    return `${basePath}/${WebDavProvider.encodePath(remotePath)}`;
  }

  private static parseManifest(payload: string): RemoteEntry[] {
    const entries: RemoteEntry[] = [];
    if (payload.trim().length === 0) {
      return entries;
    }
    let raw: WebDavManifestRaw;
    try {
      raw = JSON.parse(payload) as WebDavManifestRaw;
    } catch (error) {
      LOG.warn('manifest json parse failed, rebuilding from PROPFIND');
      return entries;
    }
    if (raw === undefined || raw === null || raw.files === undefined) {
      return entries;
    }
    for (const item of raw.files) {
      if (item === undefined || item.path === undefined || item.path.length === 0) {
        continue;
      }
      // 统一经由路径安全防火墙校验，拦截隐藏目录（.obsidian/.trash/.git）及非同步文件。
      if (!SyncPathGuard.isSafeSyncPath(item.path)) {
        LOG.warn(`manifest entry skipped (protected or unsupported): ${item.path}`);
        continue;
      }
      const entry: RemoteEntry = new RemoteEntry();
      entry.path = item.path;
      entry.etag = item.hash === undefined ? '' : item.hash;
      entry.mtime = item.mtime === undefined ? 0 : item.mtime;
      entry.size = item.size === undefined ? 0 : item.size;
      entry.isDir = false;
      entries.push(entry);
    }
    return entries;
  }

  /** 原子写入文本：先写临时文件并 fsync，再 rename 到目标（防中断截断损坏）。 */
  private static writeText(path: string, content: string): void {
    const tempPath: string = `${path}.sync-tmp`;
    const file = fileIo.openSync(tempPath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, content);
      fileIo.fsyncSync(file.fd);
    } catch (error) {
      fileIo.closeSync(file);
      WebDavProvider.removeTempFileSafe(tempPath);
      throw error as Error;
    }
    fileIo.closeSync(file);
    fileIo.renameSync(tempPath, path);
  }

  /** 原子写入二进制内容到沙箱文件（临时文件 + rename，防中断截断损坏）。 */
  private static writeBytes(path: string, data: ArrayBuffer): void {
    const tempPath: string = `${path}.sync-tmp`;
    const file = fileIo.openSync(tempPath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, data);
      fileIo.fsyncSync(file.fd);
    } catch (error) {
      fileIo.closeSync(file);
      WebDavProvider.removeTempFileSafe(tempPath);
      throw error as Error;
    }
    fileIo.closeSync(file);
    fileIo.renameSync(tempPath, path);
  }

  /** 删除遗留临时文件（写失败时清理，存在才删，删除失败不掩盖原异常）。 */
  private static removeTempFileSafe(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (error) {
      LOG.warn(`remove temp file failed: ${path}`);
    }
  }

  /** 读取沙箱文件的二进制内容。 */
  private static readBytes(path: string): ArrayBuffer {
    const source = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    const stat = fileIo.statSync(path);
    const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
    try {
      fileIo.readSync(source.fd, buffer);
    } finally {
      fileIo.closeSync(source);
    }
    return buffer;
  }

  /** 提取文本响应体：支持直接 string 及 UTF-8 ArrayBuffer（兼容 octet-stream MIME 返回）。 */
  private static extractTextPayload(payload: string | Object | ArrayBuffer,
    errorMessage: string): string {
    if (typeof payload === 'string') {
      return payload;
    }
    if (payload instanceof ArrayBuffer) {
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      return decoder.decodeToString(new Uint8Array(payload));
    }
    throw new Error(errorMessage);
  }

  /** 把 HTTP 响应体收敛为 ArrayBuffer，非二进制时返回 null。 */
  private static toArrayBuffer(payload: string | Object | ArrayBuffer): ArrayBuffer | null {
    if (typeof payload === 'string') {
      return null;
    }
    if (payload instanceof ArrayBuffer) {
      return payload;
    }
    return null;
  }

  /** 按候选头名列表提取字符串响应头值（大小写不敏感匹配）。 */
  private static headerValueOf(response: http.HttpResponse, keys: string[]): string {
    const headerMap: Record<string, string> = response.header as Record<string, string>;
    if (headerMap === undefined || headerMap === null) {
      return '';
    }
    for (const key of keys) {
      const value: string | undefined = headerMap[key];
      if (value !== undefined && typeof value === 'string') {
        return value;
      }
    }
    return '';
  }

  /** 提取响应头中的 ETag（大小写不敏感）。 */
  private static etagOf(response: http.HttpResponse): string {
    return WebDavProvider.headerValueOf(response, ['etag', 'Etag', 'ETag']);
  }

  /** 取相对路径的目录部分（不含末尾分隔符）。 */
  private static dirnameOf(path: string): string {
    const index: number = path.lastIndexOf('/');
    return index <= 0 ? '' : path.substring(0, index);
  }

  /** 发送二进制请求体（PUT/POST 上传附件）。 */
  private async requestBinary(url: string, method: http.RequestMethod,
    data: ArrayBuffer): Promise<http.HttpResponse> {
    return this.request(url, method, http.HttpDataType.STRING, data);
  }

  private static readText(path: string): string {
    return fileIo.readTextSync(path);
  }
}
