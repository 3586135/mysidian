import { webview } from '@kit.ArkWeb';

/**
 * ArkWeb 兜底渲染：用于原始 HTML 块。
 * 通过 loadData 注入内容，并关闭脚本、文件与网络访问权限。
 */
@ComponentV2
export struct MdWebFallback {
  @Param html: string = '';
  @Param contentHeight: number = 0;
  private computedContentHeight: number = 220;
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
      .height(this.contentHeight > 0 ? this.contentHeight : this.computedContentHeight)
      .onControllerAttached(() => {
        this.controller.loadData(this.buildHtml(), 'text/html', 'UTF-8');
        this.computedContentHeight = this.estimateHeight();
      })
      .onVisibleAreaChange([0.0, 1.0], () => {})
  }

  /** 根据 HTML 内容估算渲染高度（不含脚本标签的纯文本行高法）。 */
  private estimateHeight(): number {
    const plain: string = this.html
      .replace(/<script[\s\S]*?<\/script>/gi, '')
      .replace(/<style[\s\S]*?<\/style>/gi, '')
      .replace(/<[^>]+>/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
    if (plain.length === 0) {
      return 220;
    }
    const charsPerLine: number = 40;
    const lines: number = Math.ceil(plain.length / charsPerLine);
    const pxPerLine: number = 24;
    return Math.min(220 + lines * pxPerLine, 600);
  }

  private buildHtml(): string {
    const safe: string = this.html.replace(/<script[\s\S]*?<\/script>/gi, '');
    return '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, ' +
      'initial-scale=1"><style>body{margin:0;padding:8px;font-size:15px;line-height:1.6;' +
      'font-family:sans-serif;}img{max-width:100%;}@media (prefers-color-scheme: dark){' +
      'body{color:#e6e6e6;background:#1b1b1b;}}</style></head><body>' + safe + '</body></html>';
  }
}
