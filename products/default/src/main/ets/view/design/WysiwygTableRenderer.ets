import { resourceManager } from '@kit.LocalizationKit';
import {
  WysiwygCodec,
  WysiwygInline,
  WysiwygSpanKind,
  WysiwygTableAlign,
  WysiwygTableCodec,
  WysiwygTableData
} from '@ohos/markdown';
import { DesignPalette } from '../../viewmodel/DesignPalette';
import { DesignTokens } from '../../viewmodel/DesignTokens';

/** 离屏渲染得到的原生 PixelMap Markdown 表格载体。 */
export class RenderedTableImage {
  pixelMap: PixelMap | undefined = undefined;
  widthVp: number = 0;
  heightVp: number = 0;
  rawMd: string = '';
}

class TablePalette {
  isDark: boolean = false;
  cardBg: string = '#FFFFFF';
  headerBg: string = '#F3F4F6';
  zebraBg: string = '#FAFAFA';
  border: string = '#D1D5DB';
  headerBorder: string = '#9CA3AF';
  textPrimary: string = '#1C1917';
  textMuted: string = '#78716C';
  accent: string = '#7C3AED';
  codeBg: string = 'rgba(0,0,0,0.06)';
  highlightBg: string = 'rgba(255,193,7,0.24)';
  editBadgeBg: string = 'rgba(0,0,0,0.06)';
}

class CellFrag {
  text: string = '';
  font: string = '';
  color: string = '#1C1917';
  width: number = 0;
  isCode: boolean = false;
  isHighlight: boolean = false;
  isStrike: boolean = false;
  isLink: boolean = false;
}

class CellLine {
  frags: CellFrag[] = [];
  width: number = 0;
}

/**
 * 原生 OffscreenCanvas Markdown 表格渲染器：
 * 为 RichEditor 内的单表格段落生成高清晰 PixelMap ImageSpan，
 * 支持浅/深色主题、列对齐（左/中/右）、自适应换行、表头强调、斑马纹、
 * 与行内 Markdown 富文本（粗体/斜体/代码/删除线/高亮/双链/标签）。
 */
export class WysiwygTableRenderer {
  private static readonly MIN_COL_WIDTH_VP: number = 52;
  private static readonly MAX_NATURAL_COL_VP: number = 220;
  private static readonly MAX_CANVAS_HEIGHT_VP: number = 2800;

  /** 解析当前深浅色主题对应的表格绘图色板。 */
  private static resolvePalette(mgr: resourceManager.ResourceManager | null): TablePalette {
    const p: TablePalette = new TablePalette();
    if (mgr === null) {
      return p;
    }
    const dark: boolean = DesignPalette.isDarkMode(mgr);
    p.isDark = dark;
    const textPrim: string = DesignPalette.color(mgr, 'design_text_primary');
    const textSec: string = DesignPalette.color(mgr, 'design_text_secondary');
    const surface: string = DesignPalette.color(mgr, 'design_surface_solid');
    const accent: string = DesignPalette.color(mgr, 'design_accent');
    const divider: string = DesignPalette.color(mgr, 'design_divider');

    p.textPrimary = textPrim !== DesignPalette.FALLBACK ? textPrim : (dark ? '#F5F5F4' : '#1C1917');
    p.textMuted = textSec !== DesignPalette.FALLBACK ? textSec : (dark ? '#A8A29E' : '#78716C');
    p.cardBg = surface !== DesignPalette.FALLBACK ? surface : (dark ? '#1F1F23' : '#FFFFFF');
    p.accent = accent !== DesignPalette.FALLBACK ? accent : (dark ? '#A78BFA' : '#7C3AED');

    if (dark) {
      p.headerBg = 'rgba(255,255,255,0.075)';
      p.zebraBg = 'rgba(255,255,255,0.028)';
      p.border = divider !== DesignPalette.FALLBACK ? DesignPalette.rgba(divider, 0.72) : 'rgba(255,255,255,0.16)';
      p.headerBorder = 'rgba(255,255,255,0.24)';
      p.codeBg = 'rgba(255,255,255,0.10)';
      p.highlightBg = 'rgba(255,193,7,0.28)';
      p.editBadgeBg = DesignPalette.rgba(p.accent, 0.22);
    } else {
      p.headerBg = DesignPalette.rgba(p.accent, 0.065);
      p.zebraBg = 'rgba(0,0,0,0.018)';
      p.border = divider !== DesignPalette.FALLBACK ? DesignPalette.rgba(divider, 0.85) : 'rgba(0,0,0,0.12)';
      p.headerBorder = DesignPalette.rgba(p.accent, 0.28);
      p.codeBg = 'rgba(0,0,0,0.055)';
      p.highlightBg = 'rgba(255,193,7,0.22)';
      p.editBadgeBg = DesignPalette.rgba(p.accent, 0.10);
    }
    return p;
  }

  /** 将原始 Markdown 表格文本离屏渲染为适配编辑器宽度的 PixelMap。 */
  public static render(
    rawMd: string,
    maxWidthVp: number,
    baseFontSize: number,
    mgr: resourceManager.ResourceManager | null
  ): RenderedTableImage {
    const out: RenderedTableImage = new RenderedTableImage();
    out.rawMd = rawMd;
    const data: WysiwygTableData = WysiwygTableCodec.parseFromMarkdown(rawMd);
    const colCount: number = Math.max(1, data.headers.length);
    const palette: TablePalette = WysiwygTableRenderer.resolvePalette(mgr);

    const safeMaxW: number = Math.max(220, Math.min(DesignTokens.READING_MAX_WIDTH - 48, maxWidthVp));
    const cellFontSize: number = Math.max(12, Math.min(16, baseFontSize - 1));
    const lineHeight: number = Math.round(cellFontSize * 1.48);
    const padX: number = colCount >= 4 || safeMaxW < 360 ? 8 : 11;
    const padY: number = 8;

    // 使用轻量临时画布准确测量各单元格自然宽度与换行行数
    const measureCanvas: OffscreenCanvas = new OffscreenCanvas(safeMaxW, 80);
    const measureCtx: OffscreenCanvasRenderingContext2D =
      measureCanvas.getContext('2d', new RenderingContextSettings(true));

    const headerInlines: WysiwygInline[][] = [];
    for (let c: number = 0; c < colCount; c++) {
      headerInlines.push(WysiwygCodec.parseInlines(data.headers[c]));
    }
    const rowInlines: WysiwygInline[][][] = [];
    for (let r: number = 0; r < data.rows.length; r++) {
      const cells: WysiwygInline[][] = [];
      for (let c: number = 0; c < colCount; c++) {
        const rawCell: string = c < data.rows[r].length ? data.rows[r][c] : '';
        cells.push(WysiwygCodec.parseInlines(rawCell));
      }
      rowInlines.push(cells);
    }

    const colWidths: number[] = WysiwygTableRenderer.distributeColumnWidths(
      measureCtx, headerInlines, rowInlines, colCount, safeMaxW, padX, cellFontSize);

    let totalW: number = 0;
    for (const w of colWidths) {
      totalW += w;
    }

    // 计算每行换行后的实际行数据与精确行高
    const headerLines: CellLine[][] = [];
    let headerMaxLines: number = 1;
    for (let c: number = 0; c < colCount; c++) {
      const lines: CellLine[] = WysiwygTableRenderer.wrapCellInlines(
        measureCtx, headerInlines[c], colWidths[c] - padX * 2, cellFontSize, true, palette);
      headerLines.push(lines);
      if (lines.length > headerMaxLines) {
        headerMaxLines = lines.length;
      }
    }
    const headerH: number = Math.max(34, headerMaxLines * lineHeight + padY * 2);

    const bodyLines: CellLine[][][] = [];
    const rowHeights: number[] = [];
    let renderedRows: number = 0;
    let truncatedRows: number = 0;
    let accumulatedH: number = headerH;

    for (let r: number = 0; r < rowInlines.length; r++) {
      const rowCells: CellLine[][] = [];
      let maxLines: number = 1;
      for (let c: number = 0; c < colCount; c++) {
        const lines: CellLine[] = WysiwygTableRenderer.wrapCellInlines(
          measureCtx, rowInlines[r][c], colWidths[c] - padX * 2, cellFontSize, false, palette);
        rowCells.push(lines);
        if (lines.length > maxLines) {
          maxLines = lines.length;
        }
      }
      const rowH: number = Math.max(32, maxLines * lineHeight + padY * 2);
      if (accumulatedH + rowH > WysiwygTableRenderer.MAX_CANVAS_HEIGHT_VP - 28 && r > 0) {
        truncatedRows = rowInlines.length - r;
        break;
      }
      bodyLines.push(rowCells);
      rowHeights.push(rowH);
      accumulatedH += rowH;
      renderedRows++;
    }

    const footerH: number = truncatedRows > 0 ? 26 : 0;
    const totalH: number = Math.max(headerH, accumulatedH + footerH);

    // 创建最终画布并按圆角容器裁切渲染
    const canvas: OffscreenCanvas = new OffscreenCanvas(totalW, totalH);
    const ctx: OffscreenCanvasRenderingContext2D =
      canvas.getContext('2d', new RenderingContextSettings(true));

    const radius: number = 10;
    ctx.save();
    WysiwygTableRenderer.traceRoundedRect(ctx, 0.5, 0.5, totalW - 1, totalH - 1, radius);
    ctx.clip();

    // 卡片底色与表头底色
    ctx.fillStyle = palette.cardBg;
    ctx.fillRect(0, 0, totalW, totalH);
    ctx.fillStyle = palette.headerBg;
    ctx.fillRect(0, 0, totalW, headerH);

    // 偶数/奇数数据行斑马纹
    let curY: number = headerH;
    for (let r: number = 0; r < renderedRows; r++) {
      const rh: number = rowHeights[r];
      if (r % 2 === 1) {
        ctx.fillStyle = palette.zebraBg;
        ctx.fillRect(0, curY, totalW, rh);
      }
      curY += rh;
    }

    // 单元格内网格线
    ctx.lineWidth = 0.75;
    ctx.strokeStyle = palette.border;
    let colX: number = 0;
    for (let c: number = 0; c < colCount - 1; c++) {
      colX += colWidths[c];
      ctx.beginPath();
      ctx.moveTo(colX + 0.5, 0);
      ctx.lineTo(colX + 0.5, totalH - footerH);
      ctx.stroke();
    }

    // 表头底部加粗分隔线与数据行水平分割线
    ctx.lineWidth = 1.2;
    ctx.strokeStyle = palette.headerBorder;
    ctx.beginPath();
    ctx.moveTo(0, headerH + 0.5);
    ctx.lineTo(totalW, headerH + 0.5);
    ctx.stroke();

    ctx.lineWidth = 0.75;
    ctx.strokeStyle = palette.border;
    curY = headerH;
    for (let r: number = 0; r < renderedRows - 1; r++) {
      curY += rowHeights[r];
      ctx.beginPath();
      ctx.moveTo(0, curY + 0.5);
      ctx.lineTo(totalW, curY + 0.5);
      ctx.stroke();
    }

    // 绘制表头各列文本（保留最后一列右上角轻量编辑角标间距）
    colX = 0;
    for (let c: number = 0; c < colCount; c++) {
      const cw: number = colWidths[c];
      const align: WysiwygTableAlign = c < data.aligns.length ? data.aligns[c] : 'left';
      const extraRightReserve: number = c === colCount - 1 ? 16 : 0;
      WysiwygTableRenderer.drawCellLines(
        ctx, headerLines[c], colX, 0, cw - extraRightReserve, headerH,
        padX, lineHeight, align, palette);
      colX += cw;
    }

    // 表头右上角极简轻量可点击编辑提示角标
    const badgeSize: number = 18;
    const badgeX: number = totalW - badgeSize - 6;
    const badgeY: number = 6;
    ctx.fillStyle = palette.editBadgeBg;
    WysiwygTableRenderer.traceRoundedRect(ctx, badgeX, badgeY, badgeSize, badgeSize, 5);
    ctx.fill();
    ctx.fillStyle = palette.accent;
    ctx.font = `600 11vp sans-serif`;
    ctx.textBaseline = 'middle';
    ctx.textAlign = 'center';
    ctx.fillText('✎', badgeX + badgeSize / 2, badgeY + badgeSize / 2 + 0.5);
    ctx.textAlign = 'left';

    // 绘制数据行文本
    curY = headerH;
    for (let r: number = 0; r < renderedRows; r++) {
      const rh: number = rowHeights[r];
      colX = 0;
      for (let c: number = 0; c < colCount; c++) {
        const cw: number = colWidths[c];
        const align: WysiwygTableAlign = c < data.aligns.length ? data.aligns[c] : 'left';
        WysiwygTableRenderer.drawCellLines(
          ctx, bodyLines[r][c], colX, curY, cw, rh, padX, lineHeight, align, palette);
        colX += cw;
      }
      curY += rh;
    }

    // 超高表格底部渐隐省略栏提示
    if (truncatedRows > 0) {
      ctx.fillStyle = palette.headerBg;
      ctx.fillRect(0, totalH - footerH, totalW, footerH);
      ctx.fillStyle = palette.textMuted;
      ctx.font = `11vp sans-serif`;
      ctx.textBaseline = 'middle';
      ctx.textAlign = 'center';
      ctx.fillText(`还有 ${truncatedRows} 行未展开（点击表格可编辑全部行）`, totalW / 2, totalH - footerH / 2);
      ctx.textAlign = 'left';
    }

    ctx.restore();

    // 最外层圆角边框描边
    ctx.lineWidth = 1;
    ctx.strokeStyle = palette.border;
    WysiwygTableRenderer.traceRoundedRect(ctx, 0.5, 0.5, totalW - 1, totalH - 1, radius);
    ctx.stroke();

    out.pixelMap = ctx.getPixelMap(0, 0, totalW, totalH);
    // 确保实际展示宽度不超出当前编辑器容器宽度（多列窄屏等比自适应）
    if (totalW > safeMaxW) {
      const ratio: number = safeMaxW / totalW;
      out.widthVp = safeMaxW;
      out.heightVp = Math.max(40, Math.round(totalH * ratio));
    } else {
      out.widthVp = totalW;
      out.heightVp = totalH;
    }
    return out;
  }

  private static distributeColumnWidths(
    ctx: OffscreenCanvasRenderingContext2D,
    headerInlines: WysiwygInline[][],
    rowInlines: WysiwygInline[][][],
    colCount: number,
    maxW: number,
    padX: number,
    fontSize: number
  ): number[] {
    const natural: number[] = [];
    for (let c: number = 0; c < colCount; c++) {
      let maxTextW: number = WysiwygTableRenderer.measureSingleLine(ctx, headerInlines[c], fontSize, true) +
        (c === colCount - 1 ? 18 : 0);
      const scanRows: number = Math.min(rowInlines.length, 40);
      for (let r: number = 0; r < scanRows; r++) {
        const cellW: number = WysiwygTableRenderer.measureSingleLine(ctx, rowInlines[r][c], fontSize, false);
        if (cellW > maxTextW) {
          maxTextW = cellW;
        }
      }
      const rawW: number = Math.ceil(maxTextW) + padX * 2 + 4;
      const clamped: number = Math.max(
        WysiwygTableRenderer.MIN_COL_WIDTH_VP,
        Math.min(WysiwygTableRenderer.MAX_NATURAL_COL_VP, rawW)
      );
      natural.push(clamped);
    }

    let sumW: number = 0;
    for (const w of natural) {
      sumW += w;
    }

    // 少列且总宽未撑满容器时，按自然比例扩展至舒适宽度或容器全宽
    if (sumW <= maxW) {
      const result: number[] = [];
      let assigned: number = 0;
      for (let c: number = 0; c < colCount; c++) {
        if (c === colCount - 1) {
          result.push(maxW - assigned);
        } else {
          const share: number = Math.floor((natural[c] / sumW) * maxW);
          result.push(share);
          assigned += share;
        }
      }
      return result;
    }

    // 多列或长文本超出容器时，保持清晰字号尽量压在容器内换行
    const minNeeded: number = colCount * WysiwygTableRenderer.MIN_COL_WIDTH_VP;
    const targetTotal: number = Math.max(maxW, minNeeded);
    const result: number[] = [];
    let assigned: number = 0;
    const flexTotal: number = Math.max(1, sumW - minNeeded);
    const extraPool: number = Math.max(0, targetTotal - minNeeded);
    for (let c: number = 0; c < colCount; c++) {
      if (c === colCount - 1) {
        result.push(targetTotal - assigned);
      } else {
        const extra: number = natural[c] - WysiwygTableRenderer.MIN_COL_WIDTH_VP;
        const share: number = WysiwygTableRenderer.MIN_COL_WIDTH_VP +
          Math.floor((Math.max(0, extra) / flexTotal) * extraPool);
        result.push(share);
        assigned += share;
      }
    }
    return result;
  }

  private static measureSingleLine(
    ctx: OffscreenCanvasRenderingContext2D,
    inlines: WysiwygInline[],
    fontSize: number,
    isHeader: boolean
  ): number {
    let total: number = 0;
    for (const inline of inlines) {
      if (inline.text.length === 0) {
        continue;
      }
      ctx.font = WysiwygTableRenderer.buildCanvasFont(inline, fontSize, isHeader);
      const pad: number = inline.code ? 6 : 0;
      total += ctx.measureText(inline.text).width + pad;
    }
    return total;
  }

  private static wrapCellInlines(
    ctx: OffscreenCanvasRenderingContext2D,
    inlines: WysiwygInline[],
    availWidth: number,
    fontSize: number,
    isHeader: boolean,
    palette: TablePalette
  ): CellLine[] {
    const safeAvail: number = Math.max(24, availWidth);
    const lines: CellLine[] = [];
    let curLine: CellLine = new CellLine();

    for (const inline of inlines) {
      if (inline.text.length === 0) {
        continue;
      }
      const font: string = WysiwygTableRenderer.buildCanvasFont(inline, fontSize, isHeader);
      const color: string = WysiwygTableRenderer.pickInlineColor(inline, isHeader, palette);
      const isLink: boolean = inline.kind === WysiwygSpanKind.WIKI_LINK ||
        inline.kind === WysiwygSpanKind.MD_LINK;
      ctx.font = font;

      const tokens: string[] = WysiwygTableRenderer.tokenizeForWrap(inline.text);
      for (const token of tokens) {
        let tokenW: number = ctx.measureText(token).width;
        if (inline.code && token.trim().length > 0) {
          tokenW += 6;
        }
        if (curLine.frags.length > 0 && curLine.width + tokenW > safeAvail && token.trim().length > 0) {
          lines.push(curLine);
          curLine = new CellLine();
        }
        // 单个极长英文单词/URL 超出行宽时按字符安全折行
        if (tokenW > safeAvail && token.length > 1) {
          const chars: string[] = Array.from(token);
          for (const ch of chars) {
            const cw: number = ctx.measureText(ch).width;
            if (curLine.frags.length > 0 && curLine.width + cw > safeAvail) {
              lines.push(curLine);
              curLine = new CellLine();
            }
            curLine = WysiwygTableRenderer.pushFrag(curLine, ch, font, color, cw, inline, isLink);
          }
          continue;
        }
        // 避免新行开头挂入纯空白
        if (curLine.frags.length === 0 && token.trim().length === 0) {
          continue;
        }
        curLine = WysiwygTableRenderer.pushFrag(curLine, token, font, color, tokenW, inline, isLink);
      }
    }

    if (curLine.frags.length > 0 || lines.length === 0) {
      lines.push(curLine);
    }
    return lines;
  }

  private static pushFrag(
    line: CellLine,
    text: string,
    font: string,
    color: string,
    width: number,
    inline: WysiwygInline,
    isLink: boolean
  ): CellLine {
    const prev: CellFrag | undefined = line.frags.length > 0 ? line.frags[line.frags.length - 1] : undefined;
    if (prev !== undefined &&
      prev.font === font &&
      prev.color === color &&
      prev.isCode === inline.code &&
      prev.isHighlight === inline.highlight &&
      prev.isStrike === inline.strike &&
      prev.isLink === isLink) {
      prev.text += text;
      prev.width += width;
      line.width += width;
      return line;
    }
    const frag: CellFrag = new CellFrag();
    frag.text = text;
    frag.font = font;
    frag.color = color;
    frag.width = width;
    frag.isCode = inline.code;
    frag.isHighlight = inline.highlight;
    frag.isStrike = inline.strike;
    frag.isLink = isLink;
    line.frags.push(frag);
    line.width += width;
    return line;
  }

  /** 将单元格文本切分为保留空格边界与逐字可断的 CJK/词组切片。 */
  private static tokenizeForWrap(text: string): string[] {
    const tokens: string[] = [];
    let buf: string = '';
    for (const ch of Array.from(text)) {
      const code: number = ch.charCodeAt(0);
      const isBreakableChar: boolean = ch === ' ' || ch === '\t' || code > 0x2E80;
      if (isBreakableChar) {
        if (buf.length > 0) {
          tokens.push(buf);
          buf = '';
        }
        tokens.push(ch);
      } else {
        buf += ch;
      }
    }
    if (buf.length > 0) {
      tokens.push(buf);
    }
    return tokens;
  }

  private static drawCellLines(
    ctx: OffscreenCanvasRenderingContext2D,
    lines: CellLine[],
    cellX: number,
    cellY: number,
    cellW: number,
    cellH: number,
    padX: number,
    lineHeight: number,
    align: WysiwygTableAlign,
    palette: TablePalette
  ): void {
    const contentH: number = lines.length * lineHeight;
    let startY: number = cellY + Math.max(6, (cellH - contentH) / 2);
    const innerW: number = Math.max(12, cellW - padX * 2);

    ctx.textBaseline = 'middle';
    ctx.textAlign = 'left';

    for (let i: number = 0; i < lines.length; i++) {
      const line: CellLine = lines[i];
      const midY: number = startY + i * lineHeight + lineHeight / 2;
      let cursorX: number = cellX + padX;
      if (align === 'center') {
        cursorX = cellX + padX + Math.max(0, (innerW - line.width) / 2);
      } else if (align === 'right') {
        cursorX = cellX + padX + Math.max(0, innerW - line.width);
      }

      for (const frag of line.frags) {
        if (frag.isHighlight) {
          ctx.fillStyle = palette.highlightBg;
          ctx.fillRect(cursorX, midY - lineHeight * 0.36, frag.width, lineHeight * 0.74);
        }
        if (frag.isCode) {
          ctx.fillStyle = palette.codeBg;
          WysiwygTableRenderer.traceRoundedRect(
            ctx, cursorX, midY - lineHeight * 0.36, Math.max(6, frag.width), lineHeight * 0.74, 4);
          ctx.fill();
        }
        ctx.font = frag.font;
        ctx.fillStyle = frag.color;
        const textX: number = frag.isCode ? cursorX + 3 : cursorX;
        ctx.fillText(frag.text, textX, midY);

        if (frag.isLink) {
          ctx.lineWidth = 0.8;
          ctx.strokeStyle = frag.color;
          ctx.beginPath();
          ctx.moveTo(cursorX, midY + lineHeight * 0.32);
          ctx.lineTo(cursorX + frag.width, midY + lineHeight * 0.32);
          ctx.stroke();
        }
        if (frag.isStrike) {
          ctx.lineWidth = 1;
          ctx.strokeStyle = frag.color;
          ctx.beginPath();
          ctx.moveTo(cursorX, midY);
          ctx.lineTo(cursorX + frag.width, midY);
          ctx.stroke();
        }
        cursorX += frag.width;
      }
    }
  }

  private static buildCanvasFont(inline: WysiwygInline, baseSize: number, isHeader: boolean): string {
    const size: number = inline.code ? Math.max(11, baseSize - 1) : baseSize;
    const weight: string = isHeader || inline.bold ? '600 ' : '';
    const style: string = inline.italic ? 'italic ' : '';
    const family: string = inline.code ? 'monospace' : 'sans-serif';
    return `${style}${weight}${size}vp ${family}`;
  }

  private static pickInlineColor(inline: WysiwygInline, isHeader: boolean, palette: TablePalette): string {
    if (inline.kind === WysiwygSpanKind.WIKI_LINK ||
      inline.kind === WysiwygSpanKind.MD_LINK ||
      inline.kind === WysiwygSpanKind.TAG) {
      return palette.accent;
    }
    return isHeader ? palette.textPrimary : palette.textPrimary;
  }

  private static traceRoundedRect(
    ctx: OffscreenCanvasRenderingContext2D,
    x: number,
    y: number,
    w: number,
    h: number,
    r: number
  ): void {
    const radius: number = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + radius, y);
    ctx.lineTo(x + w - radius, y);
    ctx.arcTo(x + w, y, x + w, y + radius, radius);
    ctx.lineTo(x + w, y + h - radius);
    ctx.arcTo(x + w, y + h, x + w - radius, y + h, radius);
    ctx.lineTo(x + radius, y + h);
    ctx.arcTo(x, y + h, x, y + h - radius, radius);
    ctx.lineTo(x, y + radius);
    ctx.arcTo(x, y, x + radius, y, radius);
    ctx.closePath();
  }
}
