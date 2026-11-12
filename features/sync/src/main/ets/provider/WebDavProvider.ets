import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { RemoteEntry, SyncConfig, SyncFileFilter, SyncProvider } from '@ohos/domain';
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

/**
 * WebDAV 同步供应方。
 *
 * 清单的读写走 @ohos.http；目录真实枚举（用于发现清单之外的新文件与外部修改）
 * 通过 PROPFIND 实现：http.RequestMethod 枚举运行时即字符串，此处单点受控扩展
 * PROPFIND 方法（模拟器上 rcp 手动 Authorization 头会被丢弃导致 401，故弃用 rcp）。
 * 远端目录保存 mysidian-manifest.json 记录文件清单与哈希，
 * 笔记文件按相对路径直接存放。绝大多数 WebDAV 服务端可直接工作。
 */
export class WebDavProvider implements SyncProvider {
  private static readonly MANIFEST: string = 'mysidian-manifest.json';
  private static readonly MAX_PROPFIND_DEPTH: number = 8;
  private static readonly PROPFIND_CONCURRENCY: number = 1;
  /** 受控单点扩展：http.RequestMethod 枚举运行时即字符串，WebDAV 标准 PROPFIND 方法。 */
  private static readonly PROPFIND_METHOD: http.RequestMethod = 'PROPFIND' as http.RequestMethod;
  /** 受控单点扩展：http.RequestMethod 枚举运行时即字符串，WebDAV 标准 MKCOL 方法。 */
  private static readonly MKCOL_METHOD: http.RequestMethod = 'MKCOL' as http.RequestMethod;
  private static readonly PROPFIND_BODY: string =
    '<?xml version="1.0" encoding="utf-8"?>' +
    '<d:propfind xmlns:d="DAV:">' +
    '<d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/><d:getetag/></d:prop>' +
    '</d:propfind>';
  private config: SyncConfig = new SyncConfig();
  private baseUrl: string = '';

  public async connect(config: SyncConfig): Promise<void> {
    this.config = config;
    this.baseUrl = WebDavProvider.buildBaseUrl(config.serverUrl, config.remoteRoot);
    LOG.info(`webdav connected: ${this.baseUrl}`);
  }

  public async list(remoteDir: string): Promise<RemoteEntry[]> {
    const manifestEntries: RemoteEntry[] = await this.listManifest();
    const realEntries: RemoteEntry[] | null = await this.propfindEntries();
    if (realEntries === null) {
      return manifestEntries;
    }
    // 以 PROPFIND 的真实文件为准；清单提供已知哈希，用于三方比较。
    const hashByPath: Map<string, string> = new Map<string, string>();
    for (const entry of manifestEntries) {
      hashByPath.set(entry.path, entry.etag);
    }
    const result: RemoteEntry[] = [];
    const seen: Set<string> = new Set<string>();
    for (const real of realEntries) {
      const entry: RemoteEntry = new RemoteEntry();
      entry.path = real.path;
      const known: string | undefined = hashByPath.get(real.path);
      entry.etag = known === undefined ? '' : known;
      entry.size = real.size;
      entry.mtime = real.mtime;
      entry.isDir = false;
      result.push(entry);
      seen.add(real.path);
    }
    // 清单中记录但服务端已不存在的文件：保留原有行为（本地存在则重新上传）。
    for (const manifest of manifestEntries) {
      if (!seen.has(manifest.path)) {
        result.push(manifest);
      }
    }
    LOG.info(`webdav list: manifest=${manifestEntries.length}, real=${realEntries.length}`);
    return result;
  }

  public async readRemote(path: string): Promise<string> {
    const url: string = `${this.baseUrl}/${WebDavProvider.encodePath(path)}`;
    const response: http.HttpResponse = await this.request(url, http.RequestMethod.GET,
      http.HttpDataType.STRING);
    if (response.responseCode !== 200) {
      throw new Error(WebDavProvider.describeCode(response.responseCode, 'webdav readRemote'));
    }
    const payload: string | Object | ArrayBuffer = response.result;
    if (typeof payload !== 'string') {
      throw new Error('webdav file response is not text');
    }
    return payload;
  }

  public async pull(entry: RemoteEntry, destPath: string): Promise<void> {
    const url: string = `${this.baseUrl}/${WebDavProvider.encodePath(entry.path)}`;
    const response: http.HttpResponse = await this.request(url, http.RequestMethod.GET,
      http.HttpDataType.STRING);
    if (response.responseCode !== 200) {
      throw new Error(WebDavProvider.describeCode(response.responseCode, 'webdav pull'));
    }
    const payload: string | Object | ArrayBuffer = response.result;
    if (typeof payload !== 'string') {
      throw new Error('webdav file response is not text');
    }
    WebDavProvider.writeText(destPath, payload);
  }

  public async push(localPath: string, entry: RemoteEntry): Promise<string> {
    const url: string = `${this.baseUrl}/${WebDavProvider.encodePath(entry.path)}`;
    const content: string = WebDavProvider.readText(localPath);
    const response: http.HttpResponse = await this.request(url, http.RequestMethod.PUT,
      http.HttpDataType.STRING, content);
    if (response.responseCode === 404 || response.responseCode === 409) {
      // 父目录不存在：先建目录再重试一次（与 pushBinary 一致，
      // 否则含子目录的仓库首次同步必然 409 失败）。
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
    const url: string = `${this.baseUrl}/${WebDavProvider.encodePath(entry.path)}`;
    const data: ArrayBuffer = WebDavProvider.readBytes(localPath);
    const response: http.HttpResponse = await this.requestBinary(url, http.RequestMethod.PUT, data);
    if (response.responseCode === 404 || response.responseCode === 409) {
      // 父目录不存在：先建目录再重试一次。
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

  /** 在远端创建目录（幂等：已存在视为成功；深路径逐级创建）。 */
  public async mkdirRemote(remoteDir: string): Promise<void> {
    const trimmed: string = remoteDir.replace(/^\/+/, '').replace(/\/+$/, '');
    if (trimmed.length === 0) {
      return;
    }
    // 逐级 MKCOL：一次性对深路径 MKCOL 会因父目录不存在而 409
    // （如 attachments/a/b.png 只建一层时 a/b 仍缺失）。
    const segments: string[] = trimmed.split('/');
    let current: string = '';
    for (const segment of segments) {
      if (segment.length === 0) {
        continue;
      }
      current = current.length === 0 ? segment : `${current}/${segment}`;
      const url: string = `${this.baseUrl}/${WebDavProvider.encodePath(current)}`;
      const response: http.HttpResponse = await this.request(url, WebDavProvider.MKCOL_METHOD,
        http.HttpDataType.STRING);
      // 405（已存在）与 301（已存在）视为幂等成功。
      if (response.responseCode === 405 || response.responseCode === 301) {
        continue;
      }
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(WebDavProvider.describeCode(response.responseCode, 'webdav mkdir'));
      }
    }
  }

  /** 删除远端文件（本地删除传播；远端已不存在视为成功）。 */
  public async deleteRemote(path: string): Promise<void> {
    const url: string = `${this.baseUrl}/${WebDavProvider.encodePath(path)}`;
    const response: http.HttpResponse = await this.request(url, http.RequestMethod.DELETE,
      http.HttpDataType.STRING);
    // 404：远端已不存在（清单幽灵条目 / 双端同时删除），幂等成功。
    if (response.responseCode === 404) {
      return;
    }
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(WebDavProvider.describeCode(response.responseCode, 'webdav delete'));
    }
  }

  public async stat(path: string): Promise<RemoteEntry | null> {
    const entries: RemoteEntry[] = await this.list('');
    for (const entry of entries) {
      if (entry.path === path) {
        return entry;
      }
    }
    return null;
  }

  public async putManifest(entries: RemoteEntry[]): Promise<void> {
    const files: WebDavFileRaw[] = [];
    for (const entry of entries) {
      const item: WebDavFileRaw = new WebDavFileRaw();
      item.path = entry.path;
      item.hash = entry.etag;
      item.mtime = entry.mtime;
      item.size = entry.size;
      files.push(item);
    }
    const manifest: WebDavManifestRaw = new WebDavManifestRaw();
    manifest.version = '1';
    manifest.files = files;
    const body: string = JSON.stringify(manifest);
    const url: string = `${this.baseUrl}/${WebDavProvider.MANIFEST}`;
    const response: http.HttpResponse = await this.request(url, http.RequestMethod.PUT,
      http.HttpDataType.STRING, body);
    if (response.responseCode === 409) {
      throw new Error(`远端目录不存在(409)，请先在 WebDAV 服务端创建目录: ${this.baseUrl}`);
    }
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(WebDavProvider.describeCode(response.responseCode, 'webdav manifest write'));
    }
  }

  /** 读取远端清单条目；清单不存在视为空。 */
  private async listManifest(): Promise<RemoteEntry[]> {
    const url: string = `${this.baseUrl}/${WebDavProvider.MANIFEST}`;
    const response: http.HttpResponse = await this.request(url, http.RequestMethod.GET,
      http.HttpDataType.STRING);
    if (response.responseCode === 404) {
      return [];
    }
    if (response.responseCode !== 200) {
      throw new Error(WebDavProvider.describeCode(response.responseCode, 'webdav list'));
    }
    const payload: string | Object | ArrayBuffer = response.result;
    if (typeof payload !== 'string') {
      throw new Error('webdav manifest response is not text');
    }
    return WebDavProvider.parseManifest(payload);
  }

  /**
   * 通过 PROPFIND 枚举远端真实 .md 文件（可发现清单之外的新文件与外部修改）。
   * BFS 逐目录枚举（Depth:1）并并发请求（每批 8 个），visited 集合保证
   * 每个目录只枚举一次、每个文件只收录一次（尾斜杠差异不会造成重复）。
   * 服务端不支持或网络异常时返回 null，调用方回退清单协议。
   */
  private async propfindEntries(): Promise<RemoteEntry[] | null> {
    try {
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
      return files;
    } catch (error) {
      const err = error as BusinessError;
      LOG.info(`propfind unavailable, fallback to manifest: ${err.message}`);
      return null;
    }
  }

  /** PROPFIND 单个远端目录（Depth:1），返回其子目录与 .md 文件。 */
  private async propfindOneDir(item: PropfindQueueDir): Promise<PropfindDirResult> {
    const result: PropfindDirResult = new PropfindDirResult();
    if (item.depth > WebDavProvider.MAX_PROPFIND_DEPTH) {
      return result;
    }
    const url: string = item.dir.length === 0 ? this.baseUrl
      : `${this.baseUrl}/${WebDavProvider.encodePath(item.dir)}`;
    const response: http.HttpResponse = await this.request(url, WebDavProvider.PROPFIND_METHOD,
      http.HttpDataType.STRING, WebDavProvider.PROPFIND_BODY,
      { 'Depth': '1', 'Content-Type': 'application/xml;charset=utf-8' });
    if (response.responseCode !== 207 && response.responseCode !== 200) {
      LOG.error(`propfind ${response.responseCode} on ${url}`);
      throw new Error(`propfind failed with ${response.responseCode}`);
    }
    const payload: string | Object | ArrayBuffer = response.result;
    if (typeof payload !== 'string') {
      throw new Error('propfind response is not text');
    }
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
        if (name.startsWith('.') || name === 'conflicts') {
          continue;
        }
        result.subDirs.push(rel);
        continue;
      }
      if (name.startsWith('.') || rel === WebDavProvider.MANIFEST) {
        continue;
      }
      if (!SyncFileFilter.isSyncable(name)) {
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

  /** 取路径最后一段名称。 */
  private static lastNameOf(path: string): string {
    const idx: number = path.lastIndexOf('/');
    return idx < 0 ? path : path.substring(idx + 1);
  }

  /** 将 multistatus XML 中的 href 转为相对 baseUrl 的路径；无法映射时返回 null。 */
  private hrefToRelative(href: string): string | null {
    if (href.length === 0) {
      return null;
    }
    const basePath: string = WebDavProvider.urlPathOf(this.baseUrl);
    let decoded: string = '';
    try {
      decoded = decodeURIComponent(href);
    } catch (error) {
      decoded = href;
    }
    let path: string = decoded;
    if (basePath.length > 0 && path.startsWith(basePath)) {
      path = path.substring(basePath.length);
    } else {
      // 部分服务端返回相对 href：回退按路径段匹配远端根目录。
      // 用整段比较而非 indexOf 子串定位，避免根目录名是其它路径段
      // 的子串时（如 notes2026/）解析错位。
      const rootName: string = this.config.remoteRoot.trim();
      const rootSegs: string[] = rootName.split('/').filter(
        (seg: string): boolean => seg.length > 0);
      if (rootSegs.length === 0) {
        return null;
      }
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

  /**
   * 相对路径安全校验：拒绝绝对路径、反斜杠、空段与 "."/".." 穿越段。
   * PROPFIND 与远端清单两条入口共用，防止被篡改清单把文件写出沙箱。
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
   * 发送单个 HTTP 请求。每次创建独立 HttpRequest 实例并在完成后销毁：
   * 单实例并发在途请求会导致认证头竞态丢失（fnOS 返回 401），
   * 独立实例可安全支撑 PROPFIND / 拉取的并发批处理。
   */
  private async request(url: string, method: http.RequestMethod, expect: http.HttpDataType,
    body?: string | ArrayBuffer, extraHeaders?: Record<string, string>): Promise<http.HttpResponse> {
    if (this.baseUrl.length === 0) {
      throw new Error('webdav provider is not connected');
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
      if (body !== undefined) {
        options.extraData = body;
      }
      return await request.request(url, options);
    } finally {
      request.destroy();
    }
  }

  /** 将 HTTP 状态码翻译为带排查建议的中文提示。 */
  private static describeCode(code: number, action: string): string {
    if (code === 400) {
      return `服务器拒绝请求(400)：若使用明文 http://，请确认端口没有指向 HTTPS 服务（nginx 会返回 400）`;
    }
    if (code === 401) {
      return `认证失败(401)，请检查 WebDAV 用户名与密码`;
    }
    if (code === 403) {
      return `无权限(403)，该账号可能没有此目录的读写权限`;
    }
    if (code === 405) {
      return `方法不被允许(405)，服务端可能不支持 ${action}`;
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

  private static buildBaseUrl(serverUrl: string, remoteRoot: string): string {
    const base: string = serverUrl.replace(/\s+/g, '');
    if (base.length === 0) {
      throw new Error('服务器地址为空：请填写以 http:// 或 https:// 开头的完整地址');
    }
    let trimmed: string = base;
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      throw new Error(`服务器地址无效：请以 http:// 或 https:// 开头，` +
        `如 https://dav.jianguoyun.com/dav（当前填写 "${serverUrl.trim()}"）`);
    }
    const root: string = remoteRoot.trim();
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

  private static parseManifest(payload: string): RemoteEntry[] {
    const entries: RemoteEntry[] = [];
    if (payload.trim().length === 0) {
      return entries;
    }
    const raw: WebDavManifestRaw = JSON.parse(payload) as WebDavManifestRaw;
    if (raw === undefined || raw === null || raw.files === undefined) {
      return entries;
    }
    for (const item of raw.files) {
      if (item === undefined || item.path === undefined || item.path.length === 0) {
        continue;
      }
      // 路径穿越防护：清单来自远端，可能被篡改/损坏，
      // 与 PROPFIND 分支保持同一套段校验。
      if (!WebDavProvider.isSafeRelativePath(item.path)) {
        LOG.warn(`manifest entry skipped (unsafe path): ${item.path}`);
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
    } finally {
      fileIo.closeSync(file);
    }
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
    } finally {
      fileIo.closeSync(file);
    }
    fileIo.renameSync(tempPath, path);
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

  /** 提取响应头中的 ETag（大小写不敏感）。 */
  private static etagOf(response: http.HttpResponse): string {
    const headerMap: Record<string, string> = response.header as Record<string, string>;
    const keys: string[] = ['etag', 'Etag', 'ETag'];
    for (const key of keys) {
      const value: string | undefined = headerMap[key];
      if (value !== undefined && typeof value === 'string') {
        return value;
      }
    }
    return '';
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
