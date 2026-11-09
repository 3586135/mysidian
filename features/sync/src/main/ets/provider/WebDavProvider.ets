import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { RemoteEntry, SyncConfig, SyncProvider } from '@ohos/domain';
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

/**
 * WebDAV 同步供应方。
 *
 * 平台的 http 模块不支持 PROPFIND / MKCOL 自定义方法，
 * 因此采用「清单文件 + GET/PUT」协议：
 * 远端目录保存 mysidian-manifest.json 记录文件清单与哈希，
 * 笔记文件按相对路径直接存放。绝大多数 WebDAV 服务端可直接工作。
 */
export class WebDavProvider implements SyncProvider {
  private static readonly MANIFEST: string = 'mysidian-manifest.json';
  private config: SyncConfig = new SyncConfig();
  private httpRequest: http.HttpRequest | null = null;
  private baseUrl: string = '';

  public async connect(config: SyncConfig): Promise<void> {
    this.config = config;
    this.baseUrl = WebDavProvider.buildBaseUrl(config.serverUrl, config.remoteRoot);
    this.httpRequest = http.createHttp();
    LOG.info(`webdav connected: ${this.baseUrl}`);
  }

  public async list(remoteDir: string): Promise<RemoteEntry[]> {
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

  public async push(localPath: string, entry: RemoteEntry): Promise<void> {
    const url: string = `${this.baseUrl}/${WebDavProvider.encodePath(entry.path)}`;
    const content: string = WebDavProvider.readText(localPath);
    const response: http.HttpResponse = await this.request(url, http.RequestMethod.PUT,
      http.HttpDataType.STRING, content);
    if (response.responseCode === 409) {
      throw new Error(`远端目录不存在(409)，请先在 WebDAV 服务端创建目录: ${this.baseUrl}`);
    }
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(WebDavProvider.describeCode(response.responseCode, 'webdav push'));
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

  public async disconnect(): Promise<void> {
    if (this.httpRequest !== null) {
      this.httpRequest.destroy();
      this.httpRequest = null;
    }
  }

  private async request(url: string, method: http.RequestMethod, expect: http.HttpDataType,
    body?: string): Promise<http.HttpResponse> {
    const request: http.HttpRequest | null = this.httpRequest;
    if (request === null) {
      throw new Error('webdav provider is not connected');
    }
    const options: http.HttpRequestOptions = {
      method: method,
      expectDataType: expect,
      header: this.buildHeaders(),
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

  private buildHeaders(): Object {
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

  private static writeText(path: string, content: string): void {
    const file = fileIo.openSync(path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, content);
    } finally {
      fileIo.closeSync(file);
    }
  }

  private static readText(path: string): string {
    return fileIo.readTextSync(path);
  }
}
