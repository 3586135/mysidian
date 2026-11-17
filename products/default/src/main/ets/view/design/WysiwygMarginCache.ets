import { resourceManager } from '@kit.LocalizationKit';
import { WysiwygBlockKind } from '@ohos/markdown';
import { DesignPalette } from '../../viewmodel/DesignPalette';

/**
 * 为 RichEditor 的 LeadingMarginPlaceholder 生成并缓存矢量级 OffscreenCanvas 像素图：
 * - 无序列表圆点 / 嵌套空心圈
 * - 有序列表序号
 * - 待办任务未勾选/已勾选方框
 * - 引用与 Callout 左侧强调竖条
 * - 代码块/表格/数学块左侧细轨道
 */
export class WysiwygMarginCache {
  private readonly cache: Map<string, PixelMap> = new Map<string, PixelMap>();
  private lastThemeSignature: string = '';

  /** 根据深浅色主题刷新缓存签名，主题变化时自动释放旧图并返回是否发生切换。 */
  public syncTheme(mgr: resourceManager.ResourceManager | null): boolean {
    const signature: string = mgr === null ? 'default'
      : `${DesignPalette.color(mgr, 'design_accent')}|${DesignPalette.color(mgr, 'design_text_secondary')}|${DesignPalette.color(mgr, 'design_stroke')}`;
    if (signature !== this.lastThemeSignature) {
      const hadPrev: boolean = this.lastThemeSignature.length > 0;
      this.clear();
      this.lastThemeSignature = signature;
      return hadPrev;
    }
    return false;
  }

  /** 获取段落前导空白区占位（非列表/引用等普通段返回 undefined）。 */
  public getPlaceholder(mgr: resourceManager.ResourceManager | null, kind: WysiwygBlockKind,
    indent: number, ordinal: number, orderedDelim: string, checked: boolean,
    fontSize: number): LeadingMarginPlaceholder | undefined {
    const lineH: number = Math.max(20, Math.round(fontSize * 1.45));
    const safeIndent: number = Math.min(4, Math.max(0, indent));
    if (kind === WysiwygBlockKind.BULLET) {
      const width: number = safeIndent * 18 + 22;
      const key: string = `ul_${safeIndent}_${lineH}`;
      return { pixelMap: this.getOrBuildBullet(key, width, lineH, safeIndent, mgr), size: [width, lineH] };
    }
    if (kind === WysiwygBlockKind.ORDERED) {
      const label: string = `${Math.max(1, ordinal)}${orderedDelim}`;
      const width: number = safeIndent * 18 + Math.max(26, label.length * 9 + 10);
      const key: string = `ol_${safeIndent}_${label}_${lineH}`;
      return { pixelMap: this.getOrBuildOrdered(key, width, lineH, label, fontSize, mgr), size: [width, lineH] };
    }
    if (kind === WysiwygBlockKind.TASK) {
      const width: number = safeIndent * 18 + 26;
      const key: string = `task_${safeIndent}_${checked ? 1 : 0}_${lineH}`;
      return { pixelMap: this.getOrBuildTask(key, width, lineH, checked, mgr), size: [width, lineH] };
    }
    if (kind === WysiwygBlockKind.QUOTE || kind === WysiwygBlockKind.CALLOUT) {
      const width: number = 16;
      const key: string = `quote_${lineH}`;
      return { pixelMap: this.getOrBuildBar(key, width, lineH, 3.5, true, mgr), size: [width, lineH] };
    }
    if (kind === WysiwygBlockKind.CODE || kind === WysiwygBlockKind.MATH) {
      const width: number = 14;
      const key: string = `code_${lineH}`;
      return { pixelMap: this.getOrBuildBar(key, width, lineH, 2.5, false, mgr), size: [width, lineH] };
    }
    return undefined;
  }

  public clear(): void {
    this.cache.forEach((pm: PixelMap): void => {
      try {
        pm.release();
      } catch (error) {
      }
    });
    this.cache.clear();
  }

  private resolveColor(mgr: resourceManager.ResourceManager | null, name: string, fallback: string): string {
    if (mgr === null) {
      return fallback;
    }
    const c: string = DesignPalette.color(mgr, name);
    return c === DesignPalette.FALLBACK ? fallback : c;
  }

  private getOrBuildBullet(key: string, width: number, height: number, indent: number,
    mgr: resourceManager.ResourceManager | null): PixelMap {
    const hit: PixelMap | undefined = this.cache.get(key);
    if (hit !== undefined) {
      return hit;
    }
    const canvas: OffscreenCanvas = new OffscreenCanvas(width, height);
    const ctx: OffscreenCanvasRenderingContext2D = canvas.getContext('2d', new RenderingContextSettings(true));
    const color: string = this.resolveColor(mgr, 'design_text_secondary', '#6E6660');
    const cx: number = indent * 18 + 11;
    const cy: number = height / 2;
    ctx.beginPath();
    ctx.arc(cx, cy, 3.1, 0, Math.PI * 2);
    if (indent >= 1) {
      ctx.strokeStyle = color;
      ctx.lineWidth = 1.4;
      ctx.stroke();
    } else {
      ctx.fillStyle = color;
      ctx.fill();
    }
    const pm: PixelMap = ctx.getPixelMap(0, 0, width, height);
    this.cache.set(key, pm);
    return pm;
  }

  private getOrBuildOrdered(key: string, width: number, height: number, label: string,
    fontSize: number, mgr: resourceManager.ResourceManager | null): PixelMap {
    const hit: PixelMap | undefined = this.cache.get(key);
    if (hit !== undefined) {
      return hit;
    }
    const canvas: OffscreenCanvas = new OffscreenCanvas(width, height);
    const ctx: OffscreenCanvasRenderingContext2D = canvas.getContext('2d', new RenderingContextSettings(true));
    ctx.fillStyle = this.resolveColor(mgr, 'design_text_secondary', '#6E6660');
    ctx.font = `${Math.max(12, Math.round(fontSize * 0.88))}vp sans-serif`;
    ctx.textAlign = 'right';
    ctx.textBaseline = 'middle';
    ctx.fillText(label, width - 6, height / 2 + 0.5);
    const pm: PixelMap = ctx.getPixelMap(0, 0, width, height);
    this.cache.set(key, pm);
    return pm;
  }

  private getOrBuildTask(key: string, width: number, height: number, checked: boolean,
    mgr: resourceManager.ResourceManager | null): PixelMap {
    const hit: PixelMap | undefined = this.cache.get(key);
    if (hit !== undefined) {
      return hit;
    }
    const canvas: OffscreenCanvas = new OffscreenCanvas(width, height);
    const ctx: OffscreenCanvasRenderingContext2D = canvas.getContext('2d', new RenderingContextSettings(true));
    const boxSize: number = 15;
    const left: number = width - 22;
    const top: number = (height - boxSize) / 2;
    this.traceRoundedRect(ctx, left, top, boxSize, boxSize, 4);
    if (checked) {
      ctx.fillStyle = this.resolveColor(mgr, 'design_accent', '#6F5BD6');
      ctx.fill();
      ctx.beginPath();
      ctx.strokeStyle = this.resolveColor(mgr, 'design_on_accent', '#FFFFFF');
      ctx.lineWidth = 1.9;
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.moveTo(left + 3.6, top + 7.6);
      ctx.lineTo(left + 6.4, top + 10.6);
      ctx.lineTo(left + 11.4, top + 4.8);
      ctx.stroke();
    } else {
      ctx.strokeStyle = this.resolveColor(mgr, 'design_text_secondary', '#6E6660');
      ctx.lineWidth = 1.5;
      ctx.stroke();
    }
    const pm: PixelMap = ctx.getPixelMap(0, 0, width, height);
    this.cache.set(key, pm);
    return pm;
  }

  private getOrBuildBar(key: string, width: number, height: number, barW: number, accent: boolean,
    mgr: resourceManager.ResourceManager | null): PixelMap {
    const hit: PixelMap | undefined = this.cache.get(key);
    if (hit !== undefined) {
      return hit;
    }
    const canvas: OffscreenCanvas = new OffscreenCanvas(width, height);
    const ctx: OffscreenCanvasRenderingContext2D = canvas.getContext('2d', new RenderingContextSettings(true));
    this.traceRoundedRect(ctx, 2, 2, barW, Math.max(8, height - 4), barW / 2);
    if (accent) {
      ctx.fillStyle = this.resolveColor(mgr, 'design_accent', '#6F5BD6');
    } else {
      const dark: boolean = mgr !== null && DesignPalette.isDarkMode(mgr);
      const base: string = this.resolveColor(mgr, 'design_text_secondary', '#6E6660');
      ctx.fillStyle = DesignPalette.rgba(base, dark ? 0.42 : 0.28);
    }
    ctx.fill();
    const pm: PixelMap = ctx.getPixelMap(0, 0, width, height);
    this.cache.set(key, pm);
    return pm;
  }

  private traceRoundedRect(ctx: OffscreenCanvasRenderingContext2D, x: number, y: number,
    w: number, h: number, r: number): void {
    const rad: number = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + rad, y);
    ctx.lineTo(x + w - rad, y);
    ctx.arcTo(x + w, y, x + w, y + rad, rad);
    ctx.lineTo(x + w, y + h - rad);
    ctx.arcTo(x + w, y + h, x + w - rad, y + h, rad);
    ctx.lineTo(x + rad, y + h);
    ctx.arcTo(x, y + h, x, y + h - rad, rad);
    ctx.lineTo(x, y + rad);
    ctx.arcTo(x, y, x + rad, y, rad);
    ctx.closePath();
  }
}
