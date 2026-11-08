import { webview } from '@kit.ArkWeb';

/**
 * ArkWeb 兜底渲染：用于原始 HTML 块。
 * 通过 loadData 注入内容，并关闭脚本、文件与网络访问权限。
 */
@ComponentV2
export struct MdWebFallback {
  @Param html: string = '';
  @Param contentHeight: number = 220;
  private controller: webview.WebviewController = new webview.WebviewController();

  build() {
    Web({
      src: 'about:blank',
      controller: this.controller
    })
      .javaScriptAccess(false)
      .domStorageAccess(false)
      .fileAccess(false)
      .imageAccess(false)
      .onlineImageAccess(false)
      .width('100%')
      .height(this.contentHeight)
      .onControllerAttached(() => {
        this.controller.loadData(this.buildHtml(), 'text/html', 'UTF-8');
      })
  }

  private buildHtml(): string {
    const safe: string = this.html.replace(/<script[\s\S]*?<\/script>/gi, '');
    return '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, ' +
      'initial-scale=1"><style>body{margin:0;padding:8px;font-size:15px;line-height:1.6;' +
      'font-family:sans-serif;}img{max-width:100%;}@media (prefers-color-scheme: dark){' +
      'body{color:#e6e6e6;background:#1b1b1b;}}</style></head><body>' + safe + '</body></html>';
  }
}
