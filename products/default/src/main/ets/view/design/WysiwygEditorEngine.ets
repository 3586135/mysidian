import { resourceManager } from '@kit.LocalizationKit';
import {
  BlockTriggerResult,
  CodeToken,
  InlineTriggerResult,
  WysiwygBlockKind,
  WysiwygCodec,
  WysiwygDocument,
  WysiwygInline,
  WysiwygParagraph,
  WysiwygSpanKind,
  WysiwygTableCodec,
  WysiwygTableData,
  WysiwygTriggers
} from '@ohos/markdown';
import { FindReplaceUtils } from '../../viewmodel/FindReplaceUtils';
import { WysiwygMarginCache } from './WysiwygMarginCache';
import {
  DecodedSpanUrl,
  WysiwygImageRecord,
  WysiwygStyleHelper,
  WysiwygThemeColors
} from './WysiwygStyleHelper';
import { RenderedTableImage, WysiwygTableRenderer } from './WysiwygTableRenderer';

/** 撤销/重做快照。 */
class WysiwygUndoSnapshot {
  md: string = '';
  caret: number = 0;
}

/** 底部格式化工具栏激活态。 */
export class WysiwygFormatState {
  bold: boolean = false;
  italic: boolean = false;
  strike: boolean = false;
  highlight: boolean = false;
  code: boolean = false;
  headingLevel: number = 0;
  blockKind: string = '';

  public clone(): WysiwygFormatState {
    const s: WysiwygFormatState = new WysiwygFormatState();
    s.bold = this.bold;
    s.italic = this.italic;
    s.strike = this.strike;
    s.highlight = this.highlight;
    s.code = this.code;
    s.headingLevel = this.headingLevel;
    s.blockKind = this.blockKind;
    return s;
  }

  public equals(other: WysiwygFormatState): boolean {
    return this.bold === other.bold && this.italic === other.italic &&
      this.strike === other.strike && this.highlight === other.highlight &&
      this.code === other.code && this.headingLevel === other.headingLevel &&
      this.blockKind === other.blockKind;
  }
}

/** 光标附近补全检查载荷。 */
export class WysiwygCompletionQuery {
  paraTextUpToCaret: string = '';
  caretInPara: number = 0;
  paraStart: number = 0;
  globalCaret: number = 0;
}

/**
 * ArkUI RichEditor 原生所见即所得高性能引擎：
 * - 按键关键路径零全篇 getSpans/serialize 扫描（增量 prevPlainText + 局部 delta + 220ms 闲时防抖同步）
 * - 段落 Diff 局部撤销/重做（<5ms，不整篇闪烁或丢滚屏）
 * - B/I/~/==/` 明确工具栏激活态 + 输入法提交强制着染兜底
 * - [[]] 自动闭合、Tab / 点击空白处 / 移出时自动转成双链
 * - 所见 <-> 源码精确光标偏移映射
 */
export class WysiwygEditorEngine {
  private static readonly MAX_UNDO: number = 80;
  private static readonly UNDO_DEBOUNCE_MS: number = 480;
  private static readonly SYNC_DEBOUNCE_MS: number = 220;

  public readonly richController: RichEditorController = new RichEditorController();
  public readonly margins: WysiwygMarginCache = new WysiwygMarginCache();

  private resMgr: resourceManager.ResourceManager | null = null;
  private uiCtx: UIContext | null = null;
  private fontSize: number = 15;
  private ready: boolean = false;

  public hasFrontmatter: boolean = false;
  public frontmatterRaw: string = '';
  public frontmatterBlankAfter: boolean = true;

  private metas: WysiwygParagraph[] = [new WysiwygParagraph()];
  private prevPlainText: string = '';
  private expectedProgrammaticText: string | null = null;
  private pendingInitialMarkdown: string = '';
  private pendingRestoreCaret: number = 0;
  private pendingRequestFocus: boolean = false;
  private isLoadingDocument: boolean = false;
  private editorFocused: boolean = false;

  /** 防抖草稿同步状态：避免每次按键全篇序列化拖慢输入响应。 */
  private lastSyncedMarkdown: string = '';
  private dirtyForSync: boolean = false;
  private syncTimerId: number = -1;

  /** 工具栏光标态行内样式覆盖（保证中文 IME 上屏后依然稳定生效，工具栏同步高亮）。 */
  private typingOverrideActive: boolean = false;
  private typingOverrideStart: number = -1;
  private typingOverrideAnchor: number = -1;
  private typingOverrideLine: number = -1;
  private pendingTextMutation: boolean = false;
  private typingFlags: WysiwygFormatState = new WysiwygFormatState();
  private lastEmittedFormat: WysiwygFormatState = new WysiwygFormatState();

  /** 正在输入中的 `[[]]` 双链起点（左中括号首个 `[` 偏移），未激活为 -1。 */
  private activeWikiOpenCaret: number = -1;
  private lastCaretOffset: number = 0;

  private readonly imageMap: Map<string, WysiwygImageRecord> = new Map<string, WysiwygImageRecord>();
  private readonly tablePixelMaps: Map<number, PixelMap> = new Map<number, PixelMap>();
  private nextTableId: number = 1;
  private contentWidthVp: number = 340;
  private resolveAssetFn: (target: string) => string = (_target: string): string => '';
  private onMarkdownChangeFn: (md: string) => void = (_md: string): void => {};
  private onActiveKindFn: (kind: WysiwygBlockKind, lang: string) => void =
    (_kind: WysiwygBlockKind, _lang: string): void => {};
  private onTriggerImageFn: () => void = (): void => {};
  private onHistoryChangeFn: (undoDepth: number, redoDepth: number) => void =
    (_u: number, _r: number): void => {};
  private onFormatStateFn: (state: WysiwygFormatState) => void =
    (_s: WysiwygFormatState): void => {};
  private onEditTableFn: (tableId: number, rawMd: string) => void =
    (_id: number, _raw: string): void => {};

  private undoStack: WysiwygUndoSnapshot[] = [];
  private redoStack: WysiwygUndoSnapshot[] = [];
  private lastUndoPushMs: number = 0;

  public bindCallbacks(
    resolveAsset: (target: string) => string,
    onMarkdownChange: (md: string) => void,
    onActiveKind: (kind: WysiwygBlockKind, lang: string) => void,
    onTriggerImage: () => void,
    onHistoryChange: (undoDepth: number, redoDepth: number) => void =
      (_u: number, _r: number): void => {},
    onFormatState: (state: WysiwygFormatState) => void =
      (_s: WysiwygFormatState): void => {},
    onEditTable: (tableId: number, rawMd: string) => void =
      (_id: number, _raw: string): void => {}
  ): void {
    this.resolveAssetFn = resolveAsset;
    this.onMarkdownChangeFn = onMarkdownChange;
    this.onActiveKindFn = onActiveKind;
    this.onTriggerImageFn = onTriggerImage;
    this.onHistoryChangeFn = onHistoryChange;
    this.onFormatStateFn = onFormatState;
    this.onEditTableFn = onEditTable;
  }

  /** 更新编辑器内容可用宽度（横竖屏/分栏尺寸变化时重绘可视化表格以匹配宽度）。 */
  public setContentWidthVp(widthVp: number): void {
    const normalized: number = Math.max(240, Math.round(widthVp));
    if (Math.abs(normalized - this.contentWidthVp) < 8) {
      return;
    }
    this.contentWidthVp = normalized;
    if (this.ready && this.hasTableBlock()) {
      this.refreshRenderedTables();
    }
  }

  public setEnvironment(mgr: resourceManager.ResourceManager | null, uiCtx: UIContext | null,
    fontSize: number): void {
    const fontChanged: boolean = this.fontSize !== fontSize;
    this.resMgr = mgr;
    this.uiCtx = uiCtx;
    this.fontSize = fontSize;
    const themeChanged: boolean = this.margins.syncTheme(mgr);
    if (this.ready && (fontChanged || themeChanged)) {
      const caret: number = this.safeCaret();
      const md: string = this.exportMarkdown();
      this.loadMarkdown(md, caret);
    }
  }

  public setEditorFocused(focused: boolean): void {
    if (!focused) {
      this.pendingTextMutation = false;
    }
    if (!focused && this.editorFocused && this.activeWikiOpenCaret >= 0) {
      this.tryFinalizeWikiAround(this.lastCaretOffset, true);
    }
    if (!focused) {
      this.flushDebouncedSync();
    }
    this.editorFocused = focused;
  }

  public onEditorReady(): void {
    this.ready = true;
    this.margins.syncTheme(this.resMgr);
    const md: string = this.pendingInitialMarkdown;
    const caret: number = this.pendingRestoreCaret;
    const shouldFocus: boolean = this.pendingRequestFocus;
    this.pendingInitialMarkdown = '';
    this.pendingRestoreCaret = 0;
    this.pendingRequestFocus = false;
    this.loadMarkdownInternal(md, true, caret);
    if (shouldFocus) {
      this.requestFocus();
    }
  }

  public onDisappear(): void {
    this.flushDebouncedSync();
    this.clearSyncTimer();
    this.ready = false;
    this.margins.clear();
    this.clearTablePixelMaps();
  }

  /** 加载 Markdown（未就绪时先缓存，onReady 自动填充并恢复光标）。 */
  public loadMarkdown(md: string, restoreCaret: number = 0, focusAfterLoad: boolean = false): void {
    if (!this.ready) {
      this.pendingInitialMarkdown = md;
      this.pendingRestoreCaret = restoreCaret;
      this.pendingRequestFocus = focusAfterLoad;
      const doc: WysiwygDocument = WysiwygCodec.parse(md);
      this.hasFrontmatter = doc.hasFrontmatter;
      this.frontmatterRaw = doc.frontmatterRaw;
      this.frontmatterBlankAfter = doc.frontmatterBlankAfter;
      this.metas = doc.paragraphs;
      this.lastSyncedMarkdown = md;
      this.dirtyForSync = false;
      return;
    }
    this.loadMarkdownInternal(md, true, restoreCaret);
    if (focusAfterLoad) {
      this.requestFocus();
    }
  }

  /** 更新内存 Frontmatter 属性并同步草稿。 */
  public setFrontmatter(hasFm: boolean, nextRaw: string): void {
    this.pushUndoNow();
    this.hasFrontmatter = hasFm;
    this.frontmatterRaw = nextRaw;
    this.emitImmediateChange();
  }

  /** 把当前 RichEditor 内容 + 元数据无损序列化为完整 Markdown。 */
  public exportMarkdown(): string {
    return this.exportWithParagraphs()[0];
  }

  private exportWithParagraphs(): [string, WysiwygParagraph[]] {
    if (!this.ready) {
      const md: string = this.pendingInitialMarkdown.length > 0
        ? this.pendingInitialMarkdown : this.lastSyncedMarkdown;
      return [md, this.metas];
    }
    const spans = this.richController.getSpans();
    const paragraphs: WysiwygParagraph[] = WysiwygStyleHelper.extractParagraphs(
      spans, this.metas, this.imageMap);
    const doc: WysiwygDocument = new WysiwygDocument();
    doc.hasFrontmatter = this.hasFrontmatter;
    doc.frontmatterRaw = this.frontmatterRaw;
    doc.frontmatterBlankAfter = this.frontmatterBlankAfter;
    doc.paragraphs = paragraphs.length > 0 ? paragraphs : [new WysiwygParagraph()];
    const md: string = WysiwygCodec.serialize(doc);
    this.lastSyncedMarkdown = md;
    this.dirtyForSync = false;
    return [md, doc.paragraphs];
  }

  /** 计算当前 WYSIWYG 光标在对应 Markdown 源码中的字符偏移（切到源码模式保光标用）。 */
  public getSourceCaretOffset(): number {
    if (!this.ready) {
      return 0;
    }
    const caret: number = this.safeCaret();
    const spans = this.richController.getSpans();
    const paragraphs: WysiwygParagraph[] = WysiwygStyleHelper.extractParagraphs(
      spans, this.metas, this.imageMap);
    const doc: WysiwygDocument = new WysiwygDocument();
    doc.hasFrontmatter = this.hasFrontmatter;
    doc.frontmatterRaw = this.frontmatterRaw;
    doc.frontmatterBlankAfter = this.frontmatterBlankAfter;
    doc.paragraphs = paragraphs.length > 0 ? paragraphs : [new WysiwygParagraph()];

    const plain: string = WysiwygStyleHelper.collectPlainText(spans);
    const clamped: number = Math.max(0, Math.min(plain.length, caret));
    const pIdx: number = WysiwygTriggers.countNewlines(plain, 0, clamped);
    const range: [number, number] = WysiwygTriggers.lineRange(plain, pIdx);
    const col: number = clamped - range[0];
    return WysiwygCodec.sourceOffsetFromWysiwyg(doc, pIdx, col);
  }

  /** 返回纯文本（非必要不主动全量扫 span，优先使用增量缓存）。 */
  public getPlainText(): string {
    if (!this.ready) {
      return '';
    }
    return this.prevPlainText;
  }

  public getFullPlainTextFromController(): string {
    if (!this.ready) {
      return '';
    }
    return WysiwygStyleHelper.collectPlainText(this.richController.getSpans());
  }

  public getCaretOffset(): number {
    return this.safeCaret();
  }

  public getUndoDepth(): number {
    return this.undoStack.length;
  }

  public getRedoDepth(): number {
    return this.redoStack.length;
  }

  public requestFocus(): void {
    if (this.uiCtx !== null) {
      try {
        this.uiCtx.getFocusController().requestFocus('mysidian_wysiwyg_rich');
      } catch (error) {
      }
    }
  }

  /** 增量 Diff 极速撤销（不整篇销毁重构，单次扫描 <5ms 响应）。 */
  public undo(): void {
    if (this.undoStack.length === 0) {
      return;
    }
    this.clearSyncTimer();
    this.pendingTextMutation = false;
    let cachedCurParas: WysiwygParagraph[] | null = null;
    const current: WysiwygUndoSnapshot = new WysiwygUndoSnapshot();
    if (this.dirtyForSync) {
      const exported = this.exportWithParagraphs();
      current.md = exported[0];
      cachedCurParas = exported[1];
    } else {
      current.md = this.lastSyncedMarkdown;
    }
    current.caret = this.safeCaret();
    this.redoStack.push(current);
    const prev: WysiwygUndoSnapshot | undefined = this.undoStack.pop();
    if (prev !== undefined) {
      this.typingOverrideActive = false;
      this.activeWikiOpenCaret = -1;
      this.applySnapshotPatch(prev.md, prev.caret, cachedCurParas);
      this.onHistoryChangeFn(this.undoStack.length, this.redoStack.length);
      this.onMarkdownChangeFn(prev.md);
    }
  }

  /** 增量 Diff 极速重做。 */
  public redo(): void {
    if (this.redoStack.length === 0) {
      return;
    }
    this.clearSyncTimer();
    this.pendingTextMutation = false;
    let cachedCurParas: WysiwygParagraph[] | null = null;
    const current: WysiwygUndoSnapshot = new WysiwygUndoSnapshot();
    if (this.dirtyForSync) {
      const exported = this.exportWithParagraphs();
      current.md = exported[0];
      cachedCurParas = exported[1];
    } else {
      current.md = this.lastSyncedMarkdown;
    }
    current.caret = this.safeCaret();
    this.undoStack.push(current);
    const next: WysiwygUndoSnapshot | undefined = this.redoStack.pop();
    if (next !== undefined) {
      this.typingOverrideActive = false;
      this.activeWikiOpenCaret = -1;
      this.applySnapshotPatch(next.md, next.caret, cachedCurParas);
      this.onHistoryChangeFn(this.undoStack.length, this.redoStack.length);
      this.onMarkdownChangeFn(next.md);
    }
  }

  /** Tab 键快捷键处理：处于未闭合/编辑态 [[...]] 中时立刻收尾转为可点双链。 */
  public handleTabKey(): boolean {
    if (!this.ready) {
      return false;
    }
    const caret: number = this.safeCaret();
    if (this.tryFinalizeWikiAround(caret, true)) {
      return true;
    }
    return false;
  }

  /** 输入前关键路径：零全篇扫描！处理分割线拦截、Tab 收尾、右中括号越过与快速撤销快照。 */
  public handleAboutToIMEInput(value: RichEditorInsertValue): boolean {
    this.expectedProgrammaticText = null;
    const curText: string = this.prevPlainText;
    this.syncMetaCountToPlainText(curText);
    const offset: number = Math.max(0, Math.min(curText.length, value.insertOffset));
    const pIdx: number = WysiwygTriggers.countNewlines(curText, 0, offset);
    if (pIdx >= 0 && pIdx < this.metas.length && this.metas[pIdx].kind === WysiwygBlockKind.HR) {
      return false;
    }

    if (value.insertValue === '\t') {
      if (this.tryFinalizeWikiAround(offset, true)) {
        return false;
      }
    }

    // 光标处于 [[...|]] 右括号左侧时，用户手输 ']' 自动越过已补全的 ']]' 并闭合为双链，避免打出 ]]]]。
    if (value.insertValue === ']' && curText.charAt(offset) === ']') {
      const range: [number, number] = WysiwygTriggers.lineRange(curText, pIdx);
      const beforeInLine: string = curText.substring(range[0], offset);
      const lastOpen: number = beforeInLine.lastIndexOf('[[');
      if (lastOpen >= 0 && !beforeInLine.substring(lastOpen + 2).includes(']]')) {
        const after: string = curText.substring(offset, Math.min(range[1], offset + 2));
        const jumpTo: number = offset + (after === ']]' ? 2 : 1);
        this.pushUndoFromCache(offset);
        this.richController.setCaretOffset(jumpTo);
        this.tryFinalizeWikiAround(jumpTo, false);
        return false;
      }
    }

    this.pushUndoFromCache(offset);
    this.pendingTextMutation = true;
    return true;
  }

  /** 退格前拦截：处理空 `[[]]` 成对退格，及段首退格剥离标题/列表/引用块样式。 */
  public handleAboutToDelete(value: RichEditorDeleteValue): boolean {
    const curText: string = this.prevPlainText;
    this.syncMetaCountToPlainText(curText);
    if (value.direction !== RichEditorDeleteDirection.BACKWARD) {
      this.expectedProgrammaticText = null;
      this.pushUndoFromCache(value.offset);
      this.pendingTextMutation = true;
      return true;
    }

    const caret: number = this.safeCaret();
    // 空 [[]] 成对删除
    if (value.length === 1 && caret >= 2 && caret + 2 <= curText.length &&
      curText.substring(caret - 2, caret) === '[[' && curText.substring(caret, caret + 2) === ']]') {
      this.pushUndoNow();
      const nextText: string = `${curText.substring(0, caret - 2)}${curText.substring(caret + 2)}`;
      this.expectedProgrammaticText = nextText;
      this.richController.deleteSpans({ start: caret - 2, end: caret + 2 });
      this.prevPlainText = nextText;
      this.activeWikiOpenCaret = -1;
      this.richController.setCaretOffset(caret - 2);
      this.scheduleDebouncedSync();
      return false;
    }

    const pIdx: number = WysiwygTriggers.countNewlines(curText, 0, caret);
    if (pIdx >= 0 && pIdx < this.metas.length) {
      const range: [number, number] = WysiwygTriggers.lineRange(curText, pIdx);
      const atLineStart: boolean = caret === range[0] ||
        (range[0] > 0 && value.offset === range[0] - 1 && value.length === 1);
      const pKind: WysiwygBlockKind = this.metas[pIdx].kind;
      if (atLineStart && pKind !== WysiwygBlockKind.PARAGRAPH &&
        pKind !== WysiwygBlockKind.TABLE && pKind !== WysiwygBlockKind.IMAGE) {
        this.pushUndoNow();
        this.unwrapParagraphToPlain(pIdx);
        this.scheduleDebouncedSync();
        return false;
      }
    }
    this.expectedProgrammaticText = null;
    this.pushUndoFromCache(caret);
    this.pendingTextMutation = true;
    return true;
  }

  /**
   * 高性能内容变更同步：
   * 只读 [raStart, raEnd) 局部范围 Span，不再每敲一个字全篇扫描！
   */
  public handleDidChange(rangeBefore: TextRange, rangeAfter: TextRange): WysiwygCompletionQuery | null {
    this.pendingTextMutation = false;
    if (this.isLoadingDocument) {
      return null;
    }
    const oldText: string = this.prevPlainText;
    this.syncMetaCountToPlainText(oldText);
    const rbStart: number = Math.max(0, Math.min(oldText.length, rangeBefore.start !== undefined ? rangeBefore.start : 0));
    const rbEnd: number = Math.max(rbStart, Math.min(oldText.length, rangeBefore.end !== undefined ? rangeBefore.end : rbStart));
    const raStart: number = Math.max(0, rangeAfter.start !== undefined ? rangeAfter.start : rbStart);
    const raEnd: number = Math.max(raStart, rangeAfter.end !== undefined ? rangeAfter.end : raStart);

    let insertedSlice: string = '';
    if (raEnd > raStart) {
      const deltaSpans = this.richController.getSpans({ start: raStart, end: raEnd });
      insertedSlice = WysiwygStyleHelper.collectRangePlainText(deltaSpans);
    }
    let newText: string = '';
    if (raEnd > raStart && insertedSlice.length !== (raEnd - raStart)) {
      newText = this.getFullPlainTextFromController();
    } else {
      newText = `${oldText.substring(0, rbStart)}${insertedSlice}${oldText.substring(rbEnd)}`;
    }

    if (this.expectedProgrammaticText !== null) {
      if (newText === this.expectedProgrammaticText) {
        this.expectedProgrammaticText = null;
        this.prevPlainText = newText;
        const centeredWiki: number = this.activeWikiOpenCaret >= 0
          ? Math.min(newText.length, this.activeWikiOpenCaret + 2)
          : Math.min(newText.length, raEnd);
        this.lastCaretOffset = centeredWiki;
        this.emitActiveKind();
        this.emitFormatStateAtCaret(this.lastCaretOffset, newText);
        this.scheduleDebouncedSync();
        return this.activeWikiOpenCaret >= 0
          ? this.buildCompletionQuery(newText, this.lastCaretOffset) : null;
      }
      if (this.getFullPlainTextFromController() === this.expectedProgrammaticText) {
        return null;
      }
      this.expectedProgrammaticText = null;
    }

    const startLine: number = WysiwygTriggers.countNewlines(oldText, 0, rbStart);
    const endLine: number = WysiwygTriggers.countNewlines(oldText, 0, rbEnd);
    const oldSpanLines: number = Math.max(1, endLine - startLine + 1);
    const newSpanLines: number = WysiwygTriggers.countNewlines(newText, raStart, raEnd) + 1;

    let forcedWikiCaret: number = -1;
    if (oldSpanLines === 1 && newSpanLines === 1) {
      this.prevPlainText = newText;
      if (startLine < this.metas.length && this.metas[startLine].kind === WysiwygBlockKind.TABLE) {
        forcedWikiCaret = this.handleMutationOnTableLine(startLine, raStart, raEnd, insertedSlice, newText);
      } else {
        this.applyTypingOverrideIfMatching(startLine, rbStart, raStart, raEnd);
        forcedWikiCaret = this.tryLiveAutoPairWiki(startLine, raStart, raEnd, newText);
        this.tryLiveMarkdownTriggers(startLine, raStart, raEnd, this.prevPlainText);
      }
    } else if (oldSpanLines === 1 && newSpanLines === 2) {
      this.typingOverrideActive = false;
      this.handleSingleEnterSplit(startLine, oldText, newText, rbStart);
    } else {
      this.typingOverrideActive = false;
      this.spliceMetasMultiLine(startLine, oldSpanLines, newSpanLines, oldText, newText);
    }

    this.syncMetaCountToPlainText(this.prevPlainText);
    this.lastCaretOffset = forcedWikiCaret >= 0 ? forcedWikiCaret : this.safeCaret();
    this.emitActiveKind();
    this.emitFormatStateAtCaret(this.lastCaretOffset, this.prevPlainText);
    this.scheduleDebouncedSync();
    return this.buildCompletionQuery(this.prevPlainText, this.lastCaretOffset);
  }

  /** 光标/选区变化：零全篇扫描，保持主动工具栏高亮态 & 移出 [[...]] 自动完成双链。 */
  public handleSelectionChange(range: RichEditorRange): WysiwygCompletionQuery | null {
    if (this.isLoadingDocument) {
      return null;
    }
    const text: string = this.prevPlainText;
    this.syncMetaCountToPlainText(text);
    const startPos: number = range.start !== undefined ? Math.max(0, Math.min(text.length, range.start)) : 0;
    const endPos: number = range.end !== undefined ? Math.max(startPos, Math.min(text.length, range.end)) : startPos;

    if (this.pendingTextMutation || this.expectedProgrammaticText !== null) {
      // 按键/IME 上屏或程序化补全中间态的短暂选区偏移，交由随后的 handleDidChange 统一处理，不破坏工具栏高亮态。
      this.lastCaretOffset = startPos;
      return null;
    }

    // 1. 检测光标是否刚移出正在输入的 [[...|]]，移出即自动完成双链渲染
    if (this.activeWikiOpenCaret >= 0 && startPos === endPos) {
      if (!this.isInsideWikiSpanAt(startPos, text)) {
        if (this.tryFinalizeWikiAround(this.lastCaretOffset, true)) {
          return null;
        }
        this.activeWikiOpenCaret = -1;
      }
    }

    this.lastCaretOffset = startPos;
    const pIdx: number = WysiwygTriggers.countNewlines(text, 0, startPos);

    if (startPos === endPos) {
      if (this.typingOverrideActive &&
        (pIdx !== this.typingOverrideLine || startPos < this.typingOverrideStart ||
          startPos > this.typingOverrideAnchor)) {
        this.typingOverrideActive = false;
      }
      if (!this.typingOverrideActive && pIdx >= 0 && pIdx < this.metas.length) {
        this.applyTypingStyleForCaret(pIdx, startPos, text);
      }
    } else {
      this.typingOverrideActive = false;
    }

    this.emitActiveKind();
    this.emitFormatStateAtCaret(startPos, text);
    if (this.editorFocused && startPos === endPos) {
      return this.buildCompletionQuery(text);
    }
    return null;
  }

  /** 点击编辑器：优先处理任务勾选，否则若从未闭合的 [[...]] 点向空白/别处，触发自动闭合转双链。 */
  public handleTap(event: ClickEvent): boolean {
    this.pendingTextMutation = false;
    if (!this.ready || this.uiCtx === null) {
      return false;
    }
    const text: string = this.prevPlainText;
    this.syncMetaCountToPlainText(text);
    const lm: LayoutManager = this.richController.getLayoutManager();
    const pos: PositionWithAffinity | undefined = lm.getCharacterPositionAtCoordinate(
      this.uiCtx.vp2px(event.x), this.uiCtx.vp2px(event.y));
    const offset: number = pos !== undefined ? pos.position
      : lm.getGlyphPositionAtCoordinate(this.uiCtx.vp2px(event.x), this.uiCtx.vp2px(event.y)).position;
    const clamped: number = Math.max(0, Math.min(text.length, offset));

    if (this.activeWikiOpenCaret >= 0 && !this.isInsideWikiSpanAt(clamped, text)) {
      this.tryFinalizeWikiAround(this.lastCaretOffset, true);
    }

    const pIdx: number = WysiwygTriggers.countNewlines(this.prevPlainText, 0, Math.min(this.prevPlainText.length, clamped));
    if (pIdx < 0 || pIdx >= this.metas.length) {
      return false;
    }
    const meta: WysiwygParagraph = this.metas[pIdx];
    if (meta.kind !== WysiwygBlockKind.TASK) {
      return false;
    }
    const marginLeft: number = meta.indent * 18;
    const marginRight: number = marginLeft + 30;
    if (event.x >= marginLeft - 4 && event.x <= marginRight) {
      this.pushUndoNow();
      meta.checked = !meta.checked;
      this.applyParagraphVisualStyle(pIdx, this.prevPlainText);
      this.emitImmediateChange();
      return true;
    }
    return false;
  }

  /** 切换代码块语言标记。 */
  public setActiveCodeLang(lang: string): void {
    const text: string = this.prevPlainText;
    const pIdx: number = WysiwygTriggers.countNewlines(text, 0, this.safeCaret());
    if (pIdx < 0 || pIdx >= this.metas.length || this.metas[pIdx].kind !== WysiwygBlockKind.CODE) {
      return;
    }
    this.pushUndoNow();
    const clean: string = lang.trim();
    let i: number = pIdx;
    while (i > 0 && this.metas[i - 1].kind === WysiwygBlockKind.CODE) {
      i--;
    }
    while (i < this.metas.length && this.metas[i].kind === WysiwygBlockKind.CODE) {
      this.metas[i].lang = clean;
      this.rehighlightCodeLine(i);
      i++;
    }
    this.emitActiveKind();
    this.emitImmediateChange();
  }

  /** 响应底部键盘工具栏所有格式操作。 */
  public applyToolbarAction(action: string): void {
    if (!this.ready) {
      return;
    }
    if (action === 'undo') {
      this.undo();
      return;
    }
    if (action === 'redo') {
      this.redo();
      return;
    }
    if (action === 'image') {
      this.onTriggerImageFn();
      return;
    }
    if (action === 'bold' || action === '**' || action === 'italic' || action === '*' ||
      action === 'strike' || action === '~~' || action === 'highlight' || action === '==' ||
      action === 'code' || action === '`') {
      const normalized: string = action === '**' ? 'bold'
        : (action === '*' ? 'italic' : (action === '~~' ? 'strike'
          : (action === '==' ? 'highlight' : (action === '`' ? 'code' : action))));
      this.toggleInlineFormat(normalized);
      return;
    }

    this.pushUndoNow();
    if (action === 'heading' || action === '# ' || action === '## ' || action === '### ') {
      if (action === '# ') {
        this.toggleHeadingLevel(1);
      } else if (action === '## ') {
        this.toggleHeadingLevel(2);
      } else if (action === '### ') {
        this.toggleHeadingLevel(3);
      } else {
        this.cycleHeadingOnActiveParagraph();
      }
      this.emitImmediateChange();
      return;
    }
    if (action === 'list' || action === '- ') {
      this.toggleBlockKind(WysiwygBlockKind.BULLET);
      this.emitImmediateChange();
      return;
    }
    if (action === 'ordered' || action === '1. ') {
      this.toggleBlockKind(WysiwygBlockKind.ORDERED);
      this.emitImmediateChange();
      return;
    }
    if (action === 'task' || action === '- [ ] ') {
      this.toggleBlockKind(WysiwygBlockKind.TASK);
      this.emitImmediateChange();
      return;
    }
    if (action === 'quote' || action === '> ') {
      this.toggleBlockKind(WysiwygBlockKind.QUOTE);
      this.emitImmediateChange();
      return;
    }
    if (action === 'link' || action === '[[') {
      this.insertWikiPair();
      return;
    }
    if (action === 'tag' || action === '#') {
      this.insertTriggerText('#');
      return;
    }
    if (action === 'hr' || action === '---\n') {
      this.insertHorizontalRule();
      return;
    }
    if (action === 'table') {
      this.insertTableBlock();
    }
  }

  /** 插入 Vault 内图片附件为真实内联图片 Span。 */
  public insertImageTarget(target: string): void {
    if (!this.ready || target.length === 0) {
      return;
    }
    this.pushUndoNow();
    const curText: string = this.prevPlainText;
    this.syncMetaCountToPlainText(curText);
    const caret: number = this.safeCaret();
    const pIdx: number = WysiwygTriggers.countNewlines(curText, 0, caret);
    const range: [number, number] = WysiwygTriggers.lineRange(curText, pIdx);
    const onEmptyLine: boolean = range[0] === range[1];
    const resolved: string = this.resolveAssetFn(target);
    const rawMd: string = `![[${target}]]`;

    if (resolved.length === 0) {
      this.replaceSpanRangeWithPlain(caret, caret, rawMd, WysiwygStyleHelper.buildDefaultTextStyle(
        this.metas[pIdx], this.fontSize, WysiwygStyleHelper.resolveThemeColors(this.resMgr)), pIdx);
      this.emitImmediateChange();
      return;
    }

    const record: WysiwygImageRecord = new WysiwygImageRecord();
    record.target = target;
    record.rawMd = rawMd;
    this.imageMap.set(resolved, record);

    const imgW: number = 220;
    const imgH: number = 148;
    const imgOpt: RichEditorImageSpanOptions = {
      offset: caret,
      imageStyle: {
        size: [imgW, imgH],
        objectFit: ImageFit.Cover,
        layoutStyle: { borderRadius: 10, margin: { top: 4, bottom: 4 } }
      }
    };

    if (onEmptyLine) {
      this.metas[pIdx].kind = WysiwygBlockKind.IMAGE;
      const expectedAfterImg: string = `${curText.substring(0, caret)} \n${curText.substring(caret)}`;
      this.metas.splice(pIdx + 1, 0, new WysiwygParagraph());
      this.expectedProgrammaticText = expectedAfterImg;
      this.richController.addImageSpan(resolved, imgOpt);
      const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);
      this.richController.addTextSpan('\n', {
        offset: caret + 1,
        style: WysiwygStyleHelper.buildDefaultTextStyle(this.metas[pIdx + 1], this.fontSize, colors),
        paragraphStyle: WysiwygStyleHelper.buildParagraphStyle(
          this.metas[pIdx + 1], this.margins, this.resMgr, this.fontSize)
      });
      this.prevPlainText = expectedAfterImg;
      this.richController.setCaretOffset(caret + 2);
    } else {
      const insertAt: number = range[1];
      const expected: string = `${curText.substring(0, insertAt)}\n \n${curText.substring(insertAt)}`;
      const imgMeta: WysiwygParagraph = new WysiwygParagraph();
      imgMeta.kind = WysiwygBlockKind.IMAGE;
      this.metas.splice(pIdx + 1, 0, imgMeta, new WysiwygParagraph());
      this.expectedProgrammaticText = expected;
      const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);
      const bodyStyle: RichEditorTextStyle = WysiwygStyleHelper.buildDefaultTextStyle(
        new WysiwygParagraph(), this.fontSize, colors);
      const bodyPStyle: RichEditorParagraphStyle = WysiwygStyleHelper.buildParagraphStyle(
        new WysiwygParagraph(), this.margins, this.resMgr, this.fontSize);
      this.richController.addTextSpan('\n', { offset: insertAt, style: bodyStyle, paragraphStyle: bodyPStyle });
      this.richController.addImageSpan(resolved, {
        offset: insertAt + 1,
        imageStyle: imgOpt.imageStyle
      });
      this.richController.addTextSpan('\n', { offset: insertAt + 2, style: bodyStyle, paragraphStyle: bodyPStyle });
      this.prevPlainText = expected;
      this.richController.setCaretOffset(insertAt + 3);
    }
    this.emitActiveKind();
    this.emitImmediateChange();
  }

  /** 将补全候选写入当前行内，并吞掉右侧自动补全的 ']]' 防止出现重复括号。 */
  public applyCompletionCandidate(replaceFrom: number, replaceTo: number, title: string,
    insertText: string, kind: 'wiki' | 'tag'): void {
    if (!this.ready) {
      return;
    }
    const curText: string = this.prevPlainText;
    this.syncMetaCountToPlainText(curText);
    if (kind !== 'wiki') {
      this.pushUndoNow();
    }
    const safeTo: number = Math.max(0, Math.min(curText.length, replaceTo));
    const safeFrom: number = Math.max(0, Math.min(safeTo, replaceFrom));
    const pIdx: number = WysiwygTriggers.countNewlines(curText, 0, safeFrom);
    const meta: WysiwygParagraph = pIdx >= 0 && pIdx < this.metas.length ? this.metas[pIdx] : new WysiwygParagraph();
    const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);

    if (kind === 'wiki') {
      const wikiStart: number = safeFrom >= 2 && curText.substring(safeFrom - 2, safeFrom) === '[['
        ? safeFrom - 2 : safeFrom;
      let deleteEnd: number = safeTo;
      if (curText.substring(safeTo, safeTo + 2) === ']]') {
        deleteEnd = safeTo + 2;
      } else if (curText.charAt(safeTo) === ']') {
        deleteEnd = safeTo + 1;
      }
      const inline: WysiwygInline = new WysiwygInline();
      inline.kind = WysiwygSpanKind.WIKI_LINK;
      inline.target = title;
      inline.originalDisplay = title;
      inline.text = title;
      const styled: string = `${title} `;
      const nextText: string = `${curText.substring(0, wikiStart)}${styled}${curText.substring(deleteEnd)}`;
      this.expectedProgrammaticText = nextText;
      if (deleteEnd > wikiStart) {
        this.richController.deleteSpans({ start: wikiStart, end: deleteEnd });
      }
      this.richController.addTextSpan(title, {
        offset: wikiStart,
        style: WysiwygStyleHelper.buildInlineTextStyle(meta, inline, this.fontSize, colors),
        urlStyle: WysiwygStyleHelper.encodeSpanUrl(WysiwygSpanKind.WIKI_LINK, title, title)
      });
      const defStyle: RichEditorTextStyle = WysiwygStyleHelper.buildDefaultTextStyle(meta, this.fontSize, colors);
      this.richController.addTextSpan(' ', { offset: wikiStart + title.length, style: defStyle });
      this.prevPlainText = nextText;
      this.activeWikiOpenCaret = -1;
      const caretAfter: number = wikiStart + styled.length;
      this.lastCaretOffset = caretAfter;
      this.richController.setCaretOffset(caretAfter);
      this.richController.setTypingStyle(defStyle);
    } else {
      const hashStart: number = safeFrom >= 1 && curText.charAt(safeFrom - 1) === '#' ? safeFrom - 1 : safeFrom;
      const cleanTag: string = insertText.startsWith('#') ? insertText.substring(1) : insertText;
      const tagText: string = `#${cleanTag}`;
      const inline: WysiwygInline = new WysiwygInline();
      inline.kind = WysiwygSpanKind.TAG;
      inline.target = cleanTag;
      inline.text = tagText;
      const nextText: string = `${curText.substring(0, hashStart)}${tagText} ${curText.substring(safeTo)}`;
      this.expectedProgrammaticText = nextText;
      if (safeTo > hashStart) {
        this.richController.deleteSpans({ start: hashStart, end: safeTo });
      }
      this.richController.addTextSpan(tagText, {
        offset: hashStart,
        style: WysiwygStyleHelper.buildInlineTextStyle(meta, inline, this.fontSize, colors),
        urlStyle: WysiwygStyleHelper.encodeSpanUrl(WysiwygSpanKind.TAG, cleanTag)
      });
      const defStyle: RichEditorTextStyle = WysiwygStyleHelper.buildDefaultTextStyle(meta, this.fontSize, colors);
      this.richController.addTextSpan(' ', { offset: hashStart + tagText.length, style: defStyle });
      this.prevPlainText = nextText;
      const caretAfter: number = hashStart + tagText.length + 1;
      this.lastCaretOffset = caretAfter;
      this.richController.setCaretOffset(caretAfter);
      this.richController.setTypingStyle(defStyle);
    }
    this.emitImmediateChange();
  }

  /** 页内查找高亮选中。 */
  public selectRange(start: number, end: number): void {
    if (!this.ready) {
      return;
    }
    this.richController.setSelection(start, end);
  }

  /** 页内查找替换单个命中。 */
  public replaceRange(start: number, end: number, replacement: string): void {
    if (!this.ready) {
      return;
    }
    const curText: string = this.prevPlainText;
    if (start < 0 || end > curText.length || start >= end) {
      return;
    }
    this.pushUndoNow();
    const pIdx: number = WysiwygTriggers.countNewlines(curText, 0, start);
    const meta: WysiwygParagraph = pIdx < this.metas.length ? this.metas[pIdx] : new WysiwygParagraph();
    const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);
    const style: RichEditorTextStyle = WysiwygStyleHelper.buildDefaultTextStyle(meta, this.fontSize, colors);
    this.replaceSpanRangeWithPlain(start, end, replacement, style, pIdx);
    this.richController.setSelection(start, start + replacement.length);
    this.emitImmediateChange();
  }

  /** 页内全部替换（逆序替换以保偏移不变）。 */
  public replaceAllKeyword(keyword: string, replacement: string): void {
    if (!this.ready || keyword.length === 0) {
      return;
    }
    const curText: string = this.prevPlainText;
    const matches: number[] = FindReplaceUtils.findAll(curText, keyword);
    if (matches.length === 0) {
      return;
    }
    this.pushUndoNow();
    const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);
    let working: string = curText;
    for (let i: number = matches.length - 1; i >= 0; i--) {
      const start: number = matches[i];
      const end: number = start + keyword.length;
      const pIdx: number = WysiwygTriggers.countNewlines(working, 0, start);
      const meta: WysiwygParagraph = pIdx < this.metas.length ? this.metas[pIdx] : new WysiwygParagraph();
      working = `${working.substring(0, start)}${replacement}${working.substring(end)}`;
      this.expectedProgrammaticText = working;
      this.richController.deleteSpans({ start: start, end: end });
      if (replacement.length > 0) {
        this.richController.addTextSpan(replacement, {
          offset: start,
          style: WysiwygStyleHelper.buildDefaultTextStyle(meta, this.fontSize, colors)
        });
      }
    }
    this.prevPlainText = working;
    this.emitImmediateChange();
  }

  // ==================== 内部加载与增量 Diff 还原 ====================

  private loadMarkdownInternal(md: string, clearUndo: boolean, restoreCaret: number): void {
    if (!this.ready) {
      return;
    }
    this.isLoadingDocument = true;
    try {
      const doc: WysiwygDocument = WysiwygCodec.parse(md);
      this.hasFrontmatter = doc.hasFrontmatter;
      this.frontmatterRaw = doc.frontmatterRaw;
      this.frontmatterBlankAfter = doc.frontmatterBlankAfter;
      this.metas = doc.paragraphs.length > 0 ? doc.paragraphs : [new WysiwygParagraph()];
      this.imageMap.clear();
      const staleTablePms: PixelMap[] = Array.from(this.tablePixelMaps.values());
      this.tablePixelMaps.clear();
      this.typingOverrideActive = false;
      this.typingOverrideStart = -1;
      this.typingOverrideLine = -1;
      this.pendingTextMutation = false;
      this.activeWikiOpenCaret = -1;
      if (clearUndo) {
        this.undoStack = [];
        this.redoStack = [];
        this.onHistoryChangeFn(0, 0);
      }

      const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);
      let expectedPlain: string = '';

      this.expectedProgrammaticText = '';
      this.richController.deleteSpans();
      for (const stalePm of staleTablePms) {
        stalePm.release();
      }

      for (let i: number = 0; i < this.metas.length; i++) {
        const meta: WysiwygParagraph = this.metas[i];
        const pStyle: RichEditorParagraphStyle = this.paragraphStyleForIndex(this.metas, i);
        const defStyle: RichEditorTextStyle = WysiwygStyleHelper.buildDefaultTextStyle(
          meta, this.fontSize, colors);
        const appendTailNewline: boolean = i < this.metas.length - 1;
        expectedPlain = this.appendParagraphSpans(
          meta, pStyle, defStyle, colors, expectedPlain, -1, appendTailNewline);
        this.expectedProgrammaticText = expectedPlain;
      }

      this.prevPlainText = expectedPlain;
      this.expectedProgrammaticText = expectedPlain;
      this.lastSyncedMarkdown = md;
      this.dirtyForSync = false;

      const clampedCaret: number = Math.max(0, Math.min(expectedPlain.length, restoreCaret));
      this.lastCaretOffset = clampedCaret;
      this.richController.setCaretOffset(clampedCaret);
      const activeP: number = WysiwygTriggers.countNewlines(expectedPlain, 0, clampedCaret);
      if (activeP >= 0 && activeP < this.metas.length) {
        const m: WysiwygParagraph = this.metas[activeP];
        this.richController.setTypingParagraphStyle(this.paragraphStyleForIndex(this.metas, activeP));
        this.richController.setTypingStyle(
          WysiwygStyleHelper.buildDefaultTextStyle(m, this.fontSize, colors));
      }
      this.emitActiveKind();
      this.emitFormatStateAtCaret(clampedCaret, expectedPlain);
    } finally {
      this.isLoadingDocument = false;
    }
  }

  /**
   * 增量 Diff 局部段落替换：Undo / Redo 只删除并重写发生变更的中间段落，保留未变前后段落。
   */
  private applySnapshotPatch(targetMd: string, restoreCaret: number,
    cachedCurParas: WysiwygParagraph[] | null = null): void {
    const targetDoc: WysiwygDocument = WysiwygCodec.parse(targetMd);
    const nextMetas: WysiwygParagraph[] = targetDoc.paragraphs.length > 0
      ? targetDoc.paragraphs : [new WysiwygParagraph()];
    this.hasFrontmatter = targetDoc.hasFrontmatter;
    this.frontmatterRaw = targetDoc.frontmatterRaw;
    this.frontmatterBlankAfter = targetDoc.frontmatterBlankAfter;

    const curText: string = this.prevPlainText;
    const curLines: string[] = curText.split('\n');
    let curParas: WysiwygParagraph[] = [];
    if (cachedCurParas !== null) {
      curParas = cachedCurParas;
    } else {
      const curSpans = this.richController.getSpans();
      curParas = WysiwygStyleHelper.extractParagraphs(curSpans, this.metas, this.imageMap);
    }

    if (curLines.length !== curParas.length || curLines.length === 0 || nextMetas.length === 0) {
      this.loadMarkdownInternal(targetMd, false, restoreCaret);
      return;
    }

    const minLen: number = Math.min(curParas.length, nextMetas.length);
    let prefix: number = 0;
    while (prefix < minLen && this.paragraphEqual(curParas[prefix], nextMetas[prefix])) {
      prefix++;
    }
    let suffix: number = 0;
    while (suffix < minLen - prefix &&
      this.paragraphEqual(curParas[curParas.length - 1 - suffix], nextMetas[nextMetas.length - 1 - suffix])) {
      suffix++;
    }

    // 所有段落均完全相同（仅 Frontmatter 变化），零 RichEditor DOM 操作！
    if (prefix === curParas.length && prefix === nextMetas.length) {
      this.lastSyncedMarkdown = targetMd;
      this.dirtyForSync = false;
      const clamped: number = Math.max(0, Math.min(curText.length, restoreCaret));
      this.richController.setCaretOffset(clamped);
      this.emitFormatStateAtCaret(clamped, curText);
      return;
    }

    while (prefix > 0 && (prefix >= curParas.length || prefix >= nextMetas.length)) {
      prefix--;
    }
    while (suffix > 0 && (prefix + suffix >= curParas.length || prefix + suffix >= nextMetas.length)) {
      suffix--;
    }
    if (prefix === 0 && suffix === 0) {
      this.loadMarkdownInternal(targetMd, false, restoreCaret);
      return;
    }

    this.isLoadingDocument = true;
    try {
      const oldMidEndIdx: number = curParas.length - 1 - suffix;
      const newMidEndIdx: number = nextMetas.length - 1 - suffix;
      const patchStart: number = WysiwygTriggers.lineRange(curText, prefix)[0];
      const patchEnd: number = suffix > 0
        ? WysiwygTriggers.lineRange(curText, oldMidEndIdx)[1]
        : curText.length;

      let middlePlain: string = '';
      for (let i: number = prefix; i <= newMidEndIdx; i++) {
        middlePlain += WysiwygCodec.wysiwygParagraphPlainText(nextMetas[i]);
        if (i < newMidEndIdx) {
          middlePlain += '\n';
        }
      }
      const nextFullPlain: string = `${curText.substring(0, patchStart)}${middlePlain}${curText.substring(patchEnd)}`;
      this.expectedProgrammaticText = nextFullPlain;

      if (patchEnd > patchStart) {
        this.richController.deleteSpans({ start: patchStart, end: patchEnd });
      }

      const oldMidCount: number = oldMidEndIdx - prefix + 1;
      const insertedClones: WysiwygParagraph[] = [];
      for (let i: number = prefix; i <= newMidEndIdx; i++) {
        insertedClones.push(nextMetas[i].clone());
      }
      this.metas.splice(prefix, oldMidCount, ...insertedClones);

      const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);
      let insertCursor: number = patchStart;
      for (let i: number = prefix; i <= newMidEndIdx; i++) {
        const meta: WysiwygParagraph = this.metas[i];
        const pStyle: RichEditorParagraphStyle = this.paragraphStyleForIndex(this.metas, i);
        const defStyle: RichEditorTextStyle = WysiwygStyleHelper.buildDefaultTextStyle(
          meta, this.fontSize, colors);
        const beforeLen: number = insertCursor;
        const addNl: boolean = i < newMidEndIdx;
        const writtenEnd: string = this.appendParagraphSpans(
          meta, pStyle, defStyle, colors, '', insertCursor, addNl);
        insertCursor = beforeLen + writtenEnd.length;

        // 空行或带 suffix 边界换行需显式保证 ParagraphStyle 正确挂接
        if (writtenEnd.length === 0) {
          const paraEndOffset: number = Math.min(nextFullPlain.length,
            beforeLen + (i < this.metas.length - 1 ? 1 : 0));
          if (paraEndOffset > beforeLen) {
            this.richController.updateParagraphStyle({
              start: beforeLen,
              end: paraEndOffset,
              style: pStyle
            });
          }
        }
      }

      this.prevPlainText = nextFullPlain;
      this.expectedProgrammaticText = nextFullPlain;
      this.lastSyncedMarkdown = targetMd;
      this.dirtyForSync = false;

      const clampedCaret: number = Math.max(0, Math.min(nextFullPlain.length, restoreCaret));
      this.lastCaretOffset = clampedCaret;
      this.richController.setCaretOffset(clampedCaret);
      const activeP: number = WysiwygTriggers.countNewlines(nextFullPlain, 0, clampedCaret);
      if (activeP >= 0 && activeP < this.metas.length) {
        this.applyTypingStyleForCaret(activeP, clampedCaret, nextFullPlain);
      }
      this.emitActiveKind();
      this.emitFormatStateAtCaret(clampedCaret, nextFullPlain);
    } finally {
      this.isLoadingDocument = false;
    }
  }

  private paragraphEqual(a: WysiwygParagraph, b: WysiwygParagraph): boolean {
    return a.kind === b.kind && a.level === b.level && a.indent === b.indent &&
      a.ordinal === b.ordinal && a.checked === b.checked && a.lang === b.lang &&
      a.calloutType === b.calloutType && a.tableRawMd === b.tableRawMd &&
      WysiwygCodec.serializeInlines(a.inlines) === WysiwygCodec.serializeInlines(b.inlines);
  }

  private paragraphStyleForIndex(list: WysiwygParagraph[], i: number): RichEditorParagraphStyle {
    const meta: WysiwygParagraph = list[i];
    const isLastOfCompactGroup: boolean = (meta.kind === WysiwygBlockKind.CODE ||
      meta.kind === WysiwygBlockKind.MATH || meta.kind === WysiwygBlockKind.TABLE ||
      meta.kind === WysiwygBlockKind.HTML) && (i + 1 >= list.length ||
      list[i + 1].kind !== meta.kind ||
      (meta.blockGroupId !== 0 && list[i + 1].blockGroupId !== meta.blockGroupId));
    return WysiwygStyleHelper.buildParagraphStyle(
      meta, this.margins, this.resMgr, this.fontSize, isLastOfCompactGroup ? 10 : -1);
  }

  private appendParagraphSpans(
    meta: WysiwygParagraph,
    pStyle: RichEditorParagraphStyle,
    defStyle: RichEditorTextStyle,
    colors: WysiwygThemeColors,
    accPlain: string,
    insertOffsetBase: number,
    appendTailNewline: boolean
  ): string {
    let localPlain: string = accPlain;
    const useOffset: boolean = insertOffsetBase >= 0;
    let cursorOffset: number = insertOffsetBase;

    if (meta.kind === WysiwygBlockKind.TABLE) {
      if (meta.blockGroupId <= 0) {
        meta.blockGroupId = this.nextTableId++;
      }
      const tableId: number = meta.blockGroupId;
      const rendered: RenderedTableImage = WysiwygTableRenderer.render(
        meta.tableRawMd, this.contentWidthVp, this.fontSize, this.resMgr);
      if (rendered.pixelMap !== undefined) {
        const oldPm: PixelMap | undefined = this.tablePixelMaps.get(tableId);
        this.tablePixelMaps.set(tableId, rendered.pixelMap);
        const spanStart: number = useOffset ? cursorOffset : localPlain.length;
        this.expectedProgrammaticText = localPlain + ' ';
        localPlain += ' ';
        const imgOpt: RichEditorImageSpanOptions = this.buildTableImageOptions(
          rendered, tableId, useOffset ? cursorOffset : -1);
        if (useOffset) {
          cursorOffset += 1;
        }
        this.richController.addImageSpan(rendered.pixelMap, imgOpt);
        this.richController.updateParagraphStyle({ start: spanStart, end: spanStart + 1, style: pStyle });
        if (oldPm !== undefined && oldPm !== rendered.pixelMap) {
          oldPm.release();
        }
      } else {
        const fallbackTable: string = meta.tableRawMd.length > 0 ? meta.tableRawMd : '| 列1 | 列2 |';
        this.expectedProgrammaticText = localPlain + fallbackTable;
        localPlain += fallbackTable;
        const tOpts: RichEditorTextSpanOptions = { style: defStyle, paragraphStyle: pStyle };
        if (useOffset) {
          tOpts.offset = cursorOffset;
          cursorOffset += fallbackTable.length;
        }
        this.richController.addTextSpan(fallbackTable, tOpts);
      }
    } else if (meta.kind === WysiwygBlockKind.CODE) {
      const rawLine: string = this.concatInlineText(meta.inlines);
      if (rawLine.length > 0) {
        const tokens: CodeToken[] = WysiwygStyleHelper.tokenizeCodeLine(rawLine, meta.lang);
        for (const tok of tokens) {
          this.expectedProgrammaticText = localPlain + tok.text;
          localPlain += tok.text;
          const opts: RichEditorTextSpanOptions = {
            style: WysiwygStyleHelper.buildCodeTokenStyle(tok, this.fontSize, colors),
            paragraphStyle: pStyle
          };
          if (useOffset) {
            opts.offset = cursorOffset;
            cursorOffset += tok.text.length;
          }
          this.richController.addTextSpan(tok.text, opts);
        }
      }
    } else {
      for (const inline of meta.inlines) {
        if (inline.isImage) {
          const resolved: string = this.resolveAssetFn(inline.imageTarget);
          if (resolved.length > 0) {
            const rec: WysiwygImageRecord = new WysiwygImageRecord();
            rec.target = inline.imageTarget;
            rec.alt = inline.imageAlt;
            rec.width = inline.imageWidth;
            rec.rawMd = inline.imageRawMd;
            this.imageMap.set(resolved, rec);
            this.expectedProgrammaticText = localPlain + ' ';
            localPlain += ' ';
            const w: number = inline.imageWidth > 0 ? Math.min(320, Math.max(80, inline.imageWidth)) : 240;
            const imgOpt: RichEditorImageSpanOptions = {
              imageStyle: {
                size: [w, Math.round(w * 0.68)],
                objectFit: ImageFit.Cover,
                layoutStyle: { borderRadius: 10, margin: { top: 4, bottom: 4 } }
              }
            };
            if (useOffset) {
              imgOpt.offset = cursorOffset;
              cursorOffset += 1;
            }
            this.richController.addImageSpan(resolved, imgOpt);
            continue;
          }
          const fallbackTxt: string = inline.imageRawMd.length > 0
            ? inline.imageRawMd : `![[${inline.imageTarget}]]`;
          this.expectedProgrammaticText = localPlain + fallbackTxt;
          localPlain += fallbackTxt;
          const fOpts: RichEditorTextSpanOptions = { style: defStyle, paragraphStyle: pStyle };
          if (useOffset) {
            fOpts.offset = cursorOffset;
            cursorOffset += fallbackTxt.length;
          }
          this.richController.addTextSpan(fallbackTxt, fOpts);
          continue;
        }
        if (inline.text.length === 0) {
          continue;
        }
        this.expectedProgrammaticText = localPlain + inline.text;
        localPlain += inline.text;
        const tOpts: RichEditorTextSpanOptions = {
          style: WysiwygStyleHelper.buildInlineTextStyle(meta, inline, this.fontSize, colors),
          paragraphStyle: pStyle,
          urlStyle: WysiwygStyleHelper.encodeSpanUrl(inline.kind, inline.target, inline.originalDisplay)
        };
        if (useOffset) {
          tOpts.offset = cursorOffset;
          cursorOffset += inline.text.length;
        }
        this.richController.addTextSpan(inline.text, tOpts);
      }
    }

    if (appendTailNewline) {
      this.expectedProgrammaticText = localPlain + '\n';
      localPlain += '\n';
      const nlOpts: RichEditorTextSpanOptions = { style: defStyle, paragraphStyle: pStyle };
      if (useOffset) {
        nlOpts.offset = cursorOffset;
      }
      this.richController.addTextSpan('\n', nlOpts);
    }
    return localPlain;
  }

  // ==================== [[ ]] 自动配对与闭合转双链 ====================

  private insertWikiPair(): void {
    this.pushUndoNow();
    const curText: string = this.prevPlainText;
    this.syncMetaCountToPlainText(curText);
    const caret: number = this.safeCaret();
    const pIdx: number = WysiwygTriggers.countNewlines(curText, 0, caret);
    const meta: WysiwygParagraph = pIdx < this.metas.length ? this.metas[pIdx] : new WysiwygParagraph();
    const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);
    const style: RichEditorTextStyle = WysiwygStyleHelper.buildDefaultTextStyle(meta, this.fontSize, colors);
    const pair: string = '[[]]';
    const nextText: string = `${curText.substring(0, caret)}${pair}${curText.substring(caret)}`;
    this.expectedProgrammaticText = nextText;
    this.richController.addTextSpan(pair, {
      offset: caret,
      style: style,
      paragraphStyle: this.paragraphStyleForIndex(this.metas, pIdx)
    });
    this.prevPlainText = nextText;
    this.activeWikiOpenCaret = caret;
    const midCaret: number = caret + 2;
    this.lastCaretOffset = midCaret;
    this.richController.setCaretOffset(midCaret);
    this.scheduleDebouncedSync();
  }

  private tryLiveAutoPairWiki(lineIdx: number, raStart: number, raEnd: number, curText: string): number {
    if (lineIdx < 0 || lineIdx >= this.metas.length || raEnd <= raStart) {
      return -1;
    }
    const lineRange: [number, number] = WysiwygTriggers.lineRange(curText, lineIdx);
    const prefix: string = curText.substring(lineRange[0], raEnd);
    const suffix: string = curText.substring(raEnd, lineRange[1]);
    if (prefix.endsWith('[[') && !prefix.endsWith('![[')) {
      this.activeWikiOpenCaret = raEnd - 2;
      if (!suffix.startsWith(']')) {
        const nextText: string = `${curText.substring(0, raEnd)}]]${curText.substring(raEnd)}`;
        this.expectedProgrammaticText = nextText;
        const meta: WysiwygParagraph = this.metas[lineIdx];
        const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);
        this.richController.addTextSpan(']]', {
          offset: raEnd,
          style: WysiwygStyleHelper.buildDefaultTextStyle(meta, this.fontSize, colors)
        });
        this.prevPlainText = nextText;
        this.lastCaretOffset = raEnd;
        this.richController.setCaretOffset(raEnd);
        return raEnd;
      }
      return raEnd;
    }
    return -1;
  }

  private isInsideWikiSpanAt(pos: number, text: string): boolean {
    if (this.activeWikiOpenCaret < 0 || pos < this.activeWikiOpenCaret + 2) {
      return false;
    }
    const lineIdx: number = WysiwygTriggers.countNewlines(text, 0, this.activeWikiOpenCaret);
    const range: [number, number] = WysiwygTriggers.lineRange(text, lineIdx);
    if (pos > range[1]) {
      return false;
    }
    const lineStr: string = text.substring(range[0], range[1]);
    const relOpen: number = this.activeWikiOpenCaret - range[0];
    if (relOpen < 0 || lineStr.substring(relOpen, relOpen + 2) !== '[[') {
      return false;
    }
    const closeIdx: number = lineStr.indexOf(']]', relOpen + 2);
    const relEnd: number = closeIdx >= 0 ? closeIdx : lineStr.length;
    return pos - range[0] <= relEnd;
  }

  /**
   * 尝试把 anchorPos 所在行的 `[[笔记名]]` 或未闭合 `[[笔记名` 自动收尾转换为可视化双链 Span。
   */
  private tryFinalizeWikiAround(anchorPos: number, forceCloseUnclosed: boolean): boolean {
    const curText: string = this.prevPlainText;
    const clamped: number = Math.max(0, Math.min(curText.length, anchorPos));
    const pIdx: number = WysiwygTriggers.countNewlines(curText, 0, clamped);
    if (pIdx < 0 || pIdx >= this.metas.length) {
      return false;
    }
    const meta: WysiwygParagraph = this.metas[pIdx];
    if (meta.kind === WysiwygBlockKind.CODE || meta.kind === WysiwygBlockKind.TABLE ||
      meta.kind === WysiwygBlockKind.MATH || meta.kind === WysiwygBlockKind.HTML) {
      return false;
    }

    const range: [number, number] = WysiwygTriggers.lineRange(curText, pIdx);
    const lineStr: string = curText.substring(range[0], range[1]);
    const relAnchor: number = clamped - range[0];
    const openSearchFrom: number = this.activeWikiOpenCaret >= range[0] && this.activeWikiOpenCaret <= range[1]
      ? this.activeWikiOpenCaret - range[0]
      : lineStr.lastIndexOf('[[', relAnchor);
    if (openSearchFrom < 0 || (openSearchFrom > 0 && lineStr.charAt(openSearchFrom - 1) === '!')) {
      return false;
    }
    if (lineStr.substring(openSearchFrom, openSearchFrom + 2) !== '[[') {
      return false;
    }

    const closeIdx: number = lineStr.indexOf(']]', openSearchFrom + 2);
    let innerRaw: string = '';
    let absEnd: number = 0;
    if (closeIdx >= 0) {
      innerRaw = lineStr.substring(openSearchFrom + 2, closeIdx).trim();
      absEnd = range[0] + closeIdx + 2;
    } else if (forceCloseUnclosed) {
      const endPos: number = Math.max(openSearchFrom + 2, Math.min(lineStr.length, relAnchor));
      innerRaw = lineStr.substring(openSearchFrom + 2, endPos).trim();
      absEnd = range[0] + endPos;
    } else {
      return false;
    }

    this.activeWikiOpenCaret = -1;
    if (innerRaw.length === 0) {
      return false;
    }

    const absStart: number = range[0] + openSearchFrom;
    const pipe: number = innerRaw.indexOf('|');
    const display: string = pipe >= 0 && innerRaw.substring(pipe + 1).trim().length > 0
      ? innerRaw.substring(pipe + 1).trim()
      : innerRaw;

    // 跳过压入与转化后序列化相同的 [[...]] 冗余快照，保证用户按一次 ↶ 即立刻可见撤销。
    const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);
    const inline: WysiwygInline = new WysiwygInline();
    inline.kind = WysiwygSpanKind.WIKI_LINK;
    inline.target = innerRaw;
    inline.originalDisplay = display;
    inline.text = display;

    const addTrailingSpace: boolean = curText.charAt(absEnd) !== ' ';
    const inserted: string = addTrailingSpace ? `${display} ` : display;
    const nextText: string = `${curText.substring(0, absStart)}${inserted}${curText.substring(absEnd)}`;
    this.expectedProgrammaticText = nextText;
    this.richController.deleteSpans({ start: absStart, end: absEnd });
    this.richController.addTextSpan(display, {
      offset: absStart,
      style: WysiwygStyleHelper.buildInlineTextStyle(meta, inline, this.fontSize, colors),
      urlStyle: WysiwygStyleHelper.encodeSpanUrl(WysiwygSpanKind.WIKI_LINK, innerRaw, display)
    });
    const defStyle: RichEditorTextStyle = WysiwygStyleHelper.buildDefaultTextStyle(meta, this.fontSize, colors);
    if (addTrailingSpace) {
      this.richController.addTextSpan(' ', {
        offset: absStart + display.length,
        style: defStyle
      });
    }
    this.prevPlainText = nextText;
    const newCaret: number = absStart + inserted.length;
    this.lastCaretOffset = newCaret;
    this.richController.setCaretOffset(newCaret);
    this.richController.setTypingStyle(defStyle);
    this.emitImmediateChange();
    return true;
  }

  // ==================== 行首与行内实时触发 ====================

  private tryLiveMarkdownTriggers(lineIdx: number, raStart: number, raEnd: number, curText: string): void {
    if (lineIdx < 0 || lineIdx >= this.metas.length) {
      return;
    }
    const meta: WysiwygParagraph = this.metas[lineIdx];
    const immutableBlock: boolean = meta.kind === WysiwygBlockKind.CODE ||
      meta.kind === WysiwygBlockKind.TABLE || meta.kind === WysiwygBlockKind.MATH ||
      meta.kind === WysiwygBlockKind.HTML || meta.kind === WysiwygBlockKind.HR ||
      meta.kind === WysiwygBlockKind.IMAGE;
    if (immutableBlock) {
      return;
    }

    const lineRange: [number, number] = WysiwygTriggers.lineRange(curText, lineIdx);
    const caret: number = Math.max(lineRange[0], Math.min(lineRange[1], raEnd));
    const prefix: string = curText.substring(lineRange[0], caret);

    if (meta.kind === WysiwygBlockKind.PARAGRAPH) {
      const fullLine: string = curText.substring(lineRange[0], lineRange[1]);
      const blockTrig: BlockTriggerResult | null = WysiwygTriggers.matchBlockPrefix(prefix);
      if (blockTrig !== null) {
        this.applyBlockTrigger(lineIdx, lineRange[0], blockTrig, curText);
        return;
      }
      if (raEnd - raStart > 1 && raStart === lineRange[0]) {
        const leadingMatch: RegExpExecArray | null =
          /^(#{1,6}\s+|[-*+]\s+\[[ xX]?\]\s+|[-*+]\s+|\d+[.)]\s+|>\s+)/.exec(fullLine);
        if (leadingMatch !== null) {
          const leadTrig: BlockTriggerResult | null = WysiwygTriggers.matchBlockPrefix(leadingMatch[1]);
          if (leadTrig !== null) {
            this.applyBlockTrigger(lineIdx, lineRange[0], leadTrig, curText);
            return;
          }
        }
      }
    }

    if (raEnd > raStart) {
      const inlineTrig: InlineTriggerResult | null = WysiwygTriggers.matchInlineSyntax(prefix);
      if (inlineTrig !== null) {
        this.applyInlineTrigger(lineIdx, lineRange[0], inlineTrig, curText);
      }
    }
  }

  private applyBlockTrigger(lineIdx: number, lineStart: number, trig: BlockTriggerResult,
    curText: string): void {
    const delEnd: number = lineStart + trig.stripLength;
    const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);

    if (trig.kind === WysiwygBlockKind.HR) {
      const targetMeta: WysiwygParagraph = this.metas[lineIdx];
      targetMeta.kind = WysiwygBlockKind.HR;
      const newPara: WysiwygParagraph = new WysiwygParagraph();
      this.metas.splice(lineIdx + 1, 0, newPara);
      const hrInsert: string = `${WysiwygTriggers.HR_DISPLAY}\n`;
      const expected: string = `${curText.substring(0, lineStart)}${hrInsert}${curText.substring(delEnd)}`;
      this.expectedProgrammaticText = expected;
      this.richController.deleteSpans({ start: lineStart, end: delEnd });
      this.richController.addTextSpan(WysiwygTriggers.HR_DISPLAY, {
        offset: lineStart,
        style: WysiwygStyleHelper.buildDefaultTextStyle(targetMeta, this.fontSize, colors),
        paragraphStyle: WysiwygStyleHelper.buildParagraphStyle(
          targetMeta, this.margins, this.resMgr, this.fontSize)
      });
      const plainPStyle: RichEditorParagraphStyle = WysiwygStyleHelper.buildParagraphStyle(
        newPara, this.margins, this.resMgr, this.fontSize);
      const plainTStyle: RichEditorTextStyle = WysiwygStyleHelper.buildDefaultTextStyle(
        newPara, this.fontSize, colors);
      this.richController.addTextSpan('\n', {
        offset: lineStart + WysiwygTriggers.HR_DISPLAY.length,
        style: plainTStyle,
        paragraphStyle: WysiwygStyleHelper.buildParagraphStyle(
          targetMeta, this.margins, this.resMgr, this.fontSize)
      });
      this.prevPlainText = expected;
      const nextCaret: number = lineStart + hrInsert.length;
      this.lastCaretOffset = nextCaret;
      this.richController.setCaretOffset(nextCaret);
      this.richController.setTypingParagraphStyle(plainPStyle);
      this.richController.setTypingStyle(plainTStyle);
      return;
    }

    const meta: WysiwygParagraph = this.metas[lineIdx];
    meta.kind = trig.kind;
    meta.level = trig.level;
    meta.indent = trig.indent;
    meta.ordinal = trig.ordinal;
    meta.orderedDelimiter = trig.orderedDelimiter;
    meta.bulletChar = trig.bulletChar;
    meta.checked = trig.checked;

    const nextText: string = `${curText.substring(0, lineStart)}${curText.substring(delEnd)}`;
    this.expectedProgrammaticText = nextText;
    this.richController.deleteSpans({ start: lineStart, end: delEnd });
    this.prevPlainText = nextText;
    this.applyParagraphVisualStyle(lineIdx, nextText);
    if (trig.kind === WysiwygBlockKind.ORDERED) {
      this.renumberOrderedFrom(lineIdx, nextText);
    }
    this.lastCaretOffset = lineStart;
    this.richController.setCaretOffset(lineStart);
    this.richController.setTypingParagraphStyle(
      WysiwygStyleHelper.buildParagraphStyle(meta, this.margins, this.resMgr, this.fontSize));
    this.richController.setTypingStyle(
      WysiwygStyleHelper.buildDefaultTextStyle(meta, this.fontSize, colors));
  }

  private applyInlineTrigger(lineIdx: number, lineStart: number, trig: InlineTriggerResult,
    curText: string): void {
    const absStart: number = lineStart + trig.startOffset;
    const absEnd: number = lineStart + trig.endOffset;
    const meta: WysiwygParagraph = this.metas[lineIdx];
    const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);

    const inline: WysiwygInline = new WysiwygInline();
    inline.text = trig.text;
    inline.bold = trig.bold;
    inline.italic = trig.italic;
    inline.strike = trig.strike;
    inline.highlight = trig.highlight;
    inline.code = trig.code;
    inline.kind = trig.kind;
    inline.target = trig.target;
    inline.originalDisplay = trig.text;

    const insertedTotal: string = `${trig.text}${trig.trailingChar}`;
    const expected: string = `${curText.substring(0, absStart)}${insertedTotal}${curText.substring(absEnd)}`;
    this.expectedProgrammaticText = expected;
    this.richController.deleteSpans({ start: absStart, end: absEnd });
    this.richController.addTextSpan(trig.text, {
      offset: absStart,
      style: WysiwygStyleHelper.buildInlineTextStyle(meta, inline, this.fontSize, colors),
      urlStyle: WysiwygStyleHelper.encodeSpanUrl(trig.kind, trig.target, trig.text)
    });
    const defStyle: RichEditorTextStyle = WysiwygStyleHelper.buildDefaultTextStyle(meta, this.fontSize, colors);
    if (trig.trailingChar.length > 0) {
      this.richController.addTextSpan(trig.trailingChar, {
        offset: absStart + trig.text.length,
        style: defStyle
      });
    }
    this.prevPlainText = expected;
    this.activeWikiOpenCaret = -1;
    const nextCaret: number = absStart + insertedTotal.length;
    this.lastCaretOffset = nextCaret;
    this.richController.setCaretOffset(nextCaret);
    this.richController.setTypingStyle(defStyle);
  }

  private handleSingleEnterSplit(lineIdx: number, oldText: string, newText: string,
    splitPosInOld: number): void {
    const oldMeta: WysiwygParagraph = lineIdx < this.metas.length
      ? this.metas[lineIdx] : new WysiwygParagraph();
    const oldRange: [number, number] = WysiwygTriggers.lineRange(oldText, lineIdx);
    const oldLineStr: string = oldText.substring(oldRange[0], oldRange[1]);

    if (oldMeta.kind === WysiwygBlockKind.PARAGRAPH) {
      if (lineIdx >= 1 && splitPosInOld >= oldRange[1] &&
        this.metas[lineIdx - 1].kind === WysiwygBlockKind.PARAGRAPH &&
        WysiwygTableCodec.isDelimiterLine(oldLineStr.trim())) {
        const prevRange: [number, number] = WysiwygTriggers.lineRange(oldText, lineIdx - 1);
        const prevLineStr: string = oldText.substring(prevRange[0], prevRange[1]).trim();
        if (prevLineStr.includes('|')) {
          const headerCells: string[] = WysiwygTableCodec.splitRow(prevLineStr);
          if (headerCells.length >= 1) {
            const tableData: WysiwygTableData = new WysiwygTableData();
            tableData.headers = headerCells;
            tableData.aligns = WysiwygTableCodec.parseAligns(oldLineStr.trim(), headerCells.length);
            tableData.rows = [];
            WysiwygTableCodec.appendRow(tableData);
            const rawMd: string = WysiwygTableCodec.toMarkdown(tableData);
            const tMeta: WysiwygParagraph = WysiwygCodec.buildTableParagraph(rawMd);
            tMeta.blockGroupId = this.nextTableId++;
            const rendered: RenderedTableImage = WysiwygTableRenderer.render(
              rawMd, this.contentWidthVp, this.fontSize, this.resMgr);
            if (rendered.pixelMap !== undefined) {
              this.pushUndoNow();
              this.tablePixelMaps.set(tMeta.blockGroupId, rendered.pixelMap);
              this.metas.splice(lineIdx - 1, 2, tMeta, new WysiwygParagraph());
              const nextText: string = `${newText.substring(0, prevRange[0])} ${newText.substring(oldRange[1])}`;
              const tPStyle: RichEditorParagraphStyle = this.paragraphStyleForIndex(this.metas, lineIdx - 1);
              this.isLoadingDocument = true;
              try {
                this.expectedProgrammaticText = nextText;
                this.richController.deleteSpans({ start: prevRange[0], end: oldRange[1] });
                this.richController.addImageSpan(rendered.pixelMap,
                  this.buildTableImageOptions(rendered, tMeta.blockGroupId, prevRange[0]));
                this.richController.updateParagraphStyle({
                  start: prevRange[0],
                  end: prevRange[0] + 1,
                  style: tPStyle
                });
                this.prevPlainText = nextText;
                this.expectedProgrammaticText = nextText;
                this.applyParagraphVisualStyle(lineIdx, nextText);
                const nextCaret: number = Math.min(nextText.length, prevRange[0] + 2);
                this.richController.setCaretOffset(nextCaret);
                this.applyTypingStyleForCaret(lineIdx, nextCaret, nextText);
              } finally {
                this.isLoadingDocument = false;
              }
              return;
            }
          }
        }
      }
      const enterTrig: BlockTriggerResult | null = WysiwygTriggers.matchEnterBlock(oldLineStr);
      if (enterTrig !== null && splitPosInOld >= oldRange[1]) {
        this.pushUndoNow();
        if (enterTrig.kind === WysiwygBlockKind.CODE || enterTrig.kind === WysiwygBlockKind.MATH) {
          oldMeta.kind = enterTrig.kind;
          oldMeta.lang = enterTrig.lang;
          const delStart: number = oldRange[0];
          const delEnd: number = Math.min(newText.length, oldRange[1] + 1);
          const nextText: string = `${newText.substring(0, delStart)}${newText.substring(delEnd)}`;
          this.expectedProgrammaticText = nextText;
          this.richController.deleteSpans({ start: delStart, end: delEnd });
          this.prevPlainText = nextText;
          this.applyParagraphVisualStyle(lineIdx, nextText);
          this.richController.setCaretOffset(delStart);
          this.applyTypingStyleForCaret(lineIdx, delStart, nextText);
          return;
        }
        if (enterTrig.kind === WysiwygBlockKind.HR) {
          oldMeta.kind = WysiwygBlockKind.HR;
          this.metas.splice(lineIdx + 1, 0, new WysiwygParagraph());
          const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);
          const nextText: string = `${newText.substring(0, oldRange[0])}${WysiwygTriggers.HR_DISPLAY}${newText.substring(oldRange[1])}`;
          this.expectedProgrammaticText = nextText;
          this.richController.deleteSpans({ start: oldRange[0], end: oldRange[1] });
          this.richController.addTextSpan(WysiwygTriggers.HR_DISPLAY, {
            offset: oldRange[0],
            style: WysiwygStyleHelper.buildDefaultTextStyle(oldMeta, this.fontSize, colors)
          });
          this.prevPlainText = nextText;
          this.applyParagraphVisualStyle(lineIdx, nextText);
          this.applyParagraphVisualStyle(lineIdx + 1, nextText);
          const nextCaret: number = oldRange[0] + WysiwygTriggers.HR_DISPLAY.length + 1;
          this.richController.setCaretOffset(nextCaret);
          this.applyTypingStyleForCaret(lineIdx + 1, nextCaret, nextText);
          return;
        }
      }
      this.metas.splice(lineIdx + 1, 0, new WysiwygParagraph());
      this.prevPlainText = newText;
      this.applyParagraphVisualStyle(lineIdx + 1, newText);
      const nextCaret: number = this.safeCaret();
      this.applyTypingStyleForCaret(lineIdx + 1, nextCaret, newText);
      return;
    }

    if (oldMeta.kind === WysiwygBlockKind.CODE || oldMeta.kind === WysiwygBlockKind.MATH) {
      const trimmed: string = oldLineStr.trim();
      const isCloseFence: boolean = (oldMeta.kind === WysiwygBlockKind.CODE && trimmed === '```') ||
        (oldMeta.kind === WysiwygBlockKind.MATH && trimmed === '$$');
      if (isCloseFence) {
        this.pushUndoNow();
        oldMeta.kind = WysiwygBlockKind.PARAGRAPH;
        oldMeta.lang = '';
        const delStart: number = oldRange[0];
        const delEnd: number = Math.min(newText.length, oldRange[1] + 1);
        const nextText: string = `${newText.substring(0, delStart)}${newText.substring(delEnd)}`;
        this.expectedProgrammaticText = nextText;
        this.richController.deleteSpans({ start: delStart, end: delEnd });
        this.prevPlainText = nextText;
        this.applyParagraphVisualStyle(lineIdx, nextText);
        this.richController.setCaretOffset(delStart);
        this.applyTypingStyleForCaret(lineIdx, delStart, nextText);
        return;
      }
      const nextCode: WysiwygParagraph = oldMeta.clone();
      this.metas.splice(lineIdx + 1, 0, nextCode);
      this.prevPlainText = newText;
      this.applyParagraphVisualStyle(lineIdx + 1, newText);
      return;
    }

    if (oldMeta.kind === WysiwygBlockKind.HEADING) {
      if (splitPosInOld <= oldRange[0] && oldLineStr.length > 0) {
        const cloned: WysiwygParagraph = oldMeta.clone();
        oldMeta.kind = WysiwygBlockKind.PARAGRAPH;
        oldMeta.level = 0;
        this.metas.splice(lineIdx + 1, 0, cloned);
        this.prevPlainText = newText;
        this.applyParagraphVisualStyle(lineIdx, newText);
        this.applyParagraphVisualStyle(lineIdx + 1, newText);
        this.applyTypingStyleForCaret(lineIdx + 1, this.safeCaret(), newText);
      } else {
        const plain: WysiwygParagraph = new WysiwygParagraph();
        this.metas.splice(lineIdx + 1, 0, plain);
        this.prevPlainText = newText;
        this.applyParagraphVisualStyle(lineIdx + 1, newText);
        this.applyTypingStyleForCaret(lineIdx + 1, this.safeCaret(), newText);
      }
      return;
    }

    const isContinuable: boolean = oldMeta.kind === WysiwygBlockKind.BULLET ||
      oldMeta.kind === WysiwygBlockKind.ORDERED || oldMeta.kind === WysiwygBlockKind.TASK ||
      oldMeta.kind === WysiwygBlockKind.QUOTE || oldMeta.kind === WysiwygBlockKind.CALLOUT;
    if (isContinuable) {
      if (oldLineStr.trim().length === 0) {
        this.pushUndoNow();
        const delPos: number = oldRange[0];
        const nextText: string = `${newText.substring(0, delPos)}${newText.substring(Math.min(newText.length, delPos + 1))}`;
        oldMeta.kind = WysiwygBlockKind.PARAGRAPH;
        oldMeta.indent = 0;
        oldMeta.checked = false;
        this.expectedProgrammaticText = nextText;
        this.richController.deleteSpans({ start: delPos, end: delPos + 1 });
        this.prevPlainText = nextText;
        this.applyParagraphVisualStyle(lineIdx, nextText);
        this.richController.setCaretOffset(delPos);
        this.applyTypingStyleForCaret(lineIdx, delPos, nextText);
        return;
      }
      const nextItem: WysiwygParagraph = oldMeta.clone();
      if (nextItem.kind === WysiwygBlockKind.TASK) {
        nextItem.checked = false;
      } else if (nextItem.kind === WysiwygBlockKind.ORDERED) {
        nextItem.ordinal = oldMeta.ordinal + 1;
      } else if (nextItem.kind === WysiwygBlockKind.CALLOUT) {
        nextItem.kind = WysiwygBlockKind.QUOTE;
      }
      this.metas.splice(lineIdx + 1, 0, nextItem);
      this.prevPlainText = newText;
      this.applyParagraphVisualStyle(lineIdx + 1, newText);
      if (nextItem.kind === WysiwygBlockKind.ORDERED) {
        this.renumberOrderedFrom(lineIdx + 1, newText);
      }
      return;
    }

    if ((oldMeta.kind === WysiwygBlockKind.TABLE || oldMeta.kind === WysiwygBlockKind.IMAGE) &&
      splitPosInOld <= oldRange[0] && oldLineStr.length > 0) {
      const clonedBlock: WysiwygParagraph = oldMeta.clone();
      const blankAbove: WysiwygParagraph = new WysiwygParagraph();
      this.metas.splice(lineIdx, 1, blankAbove, clonedBlock);
      this.prevPlainText = newText;
      this.applyParagraphVisualStyle(lineIdx, newText);
      this.applyParagraphVisualStyle(lineIdx + 1, newText);
      return;
    }

    this.metas.splice(lineIdx + 1, 0, new WysiwygParagraph());
    this.prevPlainText = newText;
    this.applyParagraphVisualStyle(lineIdx + 1, newText);
    const tailCaret: number = this.safeCaret();
    this.applyTypingStyleForCaret(lineIdx + 1, tailCaret, newText);
  }

  private spliceMetasMultiLine(startLine: number, oldCount: number, newCount: number, oldText: string,
    newText: string): void {
    const replacements: WysiwygParagraph[] = [];
    let lead: WysiwygParagraph = startLine < this.metas.length
      ? this.metas[startLine].clone() : new WysiwygParagraph();
    if (newCount === 1 && oldCount >= 2 && startLine + oldCount - 1 < this.metas.length) {
      const firstRange: [number, number] = WysiwygTriggers.lineRange(oldText, startLine);
      if (firstRange[0] === firstRange[1] && this.metas[startLine + oldCount - 1].kind !== WysiwygBlockKind.PARAGRAPH) {
        lead = this.metas[startLine + oldCount - 1].clone();
      }
    }
    replacements.push(lead);
    for (let i: number = 1; i < newCount; i++) {
      replacements.push(lead.kind === WysiwygBlockKind.CODE ? lead.clone() : new WysiwygParagraph());
    }
    this.metas.splice(startLine, oldCount, ...replacements);
    this.prevPlainText = newText;
    this.applyParagraphVisualStyle(startLine, newText);
  }

  private unwrapParagraphToPlain(pIdx: number): void {
    const meta: WysiwygParagraph = this.metas[pIdx];
    meta.kind = WysiwygBlockKind.PARAGRAPH;
    meta.level = 0;
    meta.indent = 0;
    meta.checked = false;
    meta.lang = '';
    const curText: string = this.prevPlainText;
    this.applyParagraphVisualStyle(pIdx, curText);
    const range: [number, number] = WysiwygTriggers.lineRange(curText, pIdx);
    this.richController.setCaretOffset(range[0]);
    this.applyTypingStyleForCaret(pIdx, range[0], curText);
  }

  private toggleBlockKind(targetKind: WysiwygBlockKind): void {
    const text: string = this.prevPlainText;
    this.syncMetaCountToPlainText(text);
    const sel: RichEditorSelection = this.richController.getSelection();
    const selStart: number = sel.selection[0] >= 0 ? sel.selection[0] : this.safeCaret();
    const selEnd: number = sel.selection[1] >= 0 ? sel.selection[1] : selStart;
    const startIdx: number = WysiwygTriggers.countNewlines(text, 0, Math.min(text.length, selStart));
    const endIdx: number = WysiwygTriggers.countNewlines(text, 0, Math.min(text.length, selEnd));
    let allSame: boolean = true;
    for (let i: number = startIdx; i <= endIdx && i < this.metas.length; i++) {
      if (this.metas[i].kind !== targetKind) {
        allSame = false;
        break;
      }
    }
    let ord: number = 1;
    for (let i: number = startIdx; i <= endIdx && i < this.metas.length; i++) {
      const m: WysiwygParagraph = this.metas[i];
      if (allSame) {
        m.kind = WysiwygBlockKind.PARAGRAPH;
        m.checked = false;
        m.indent = 0;
      } else {
        m.kind = targetKind;
        m.level = 0;
        m.checked = false;
        m.ordinal = ord++;
      }
      this.applyParagraphVisualStyle(i, text);
    }
    if (!allSame && targetKind === WysiwygBlockKind.ORDERED) {
      this.renumberOrderedFrom(startIdx, text);
    }
    this.typingOverrideActive = false;
    this.applyTypingStyleForCaret(startIdx, selStart, text);
    this.emitActiveKind();
    this.emitFormatStateAtCaret(selStart, text);
  }

  private toggleHeadingLevel(targetLevel: number): void {
    const text: string = this.prevPlainText;
    this.syncMetaCountToPlainText(text);
    const caret: number = this.safeCaret();
    const pIdx: number = WysiwygTriggers.countNewlines(text, 0, caret);
    if (pIdx < 0 || pIdx >= this.metas.length) {
      return;
    }
    const m: WysiwygParagraph = this.metas[pIdx];
    if (m.kind === WysiwygBlockKind.HEADING && m.level === targetLevel) {
      m.kind = WysiwygBlockKind.PARAGRAPH;
      m.level = 0;
    } else {
      m.kind = WysiwygBlockKind.HEADING;
      m.level = targetLevel;
    }
    this.typingOverrideActive = false;
    this.applyParagraphVisualStyle(pIdx, text);
    this.applyTypingStyleForCaret(pIdx, caret, text);
    this.emitActiveKind();
    this.emitFormatStateAtCaret(caret, text);
  }

  private cycleHeadingOnActiveParagraph(): void {
    const text: string = this.prevPlainText;
    this.syncMetaCountToPlainText(text);
    const caret: number = this.safeCaret();
    const pIdx: number = WysiwygTriggers.countNewlines(text, 0, caret);
    if (pIdx < 0 || pIdx >= this.metas.length) {
      return;
    }
    const m: WysiwygParagraph = this.metas[pIdx];
    if (m.kind !== WysiwygBlockKind.HEADING) {
      m.kind = WysiwygBlockKind.HEADING;
      m.level = 1;
    } else if (m.level < 4) {
      m.level++;
    } else {
      m.kind = WysiwygBlockKind.PARAGRAPH;
      m.level = 0;
    }
    this.typingOverrideActive = false;
    this.applyParagraphVisualStyle(pIdx, text);
    this.applyTypingStyleForCaret(pIdx, caret, text);
    this.emitActiveKind();
    this.emitFormatStateAtCaret(caret, text);
  }

  // ==================== B / I / ~ / == / ` 即时状态与 IME 着染 ====================

  private toggleInlineFormat(action: string): void {
    const sel: RichEditorSelection = this.richController.getSelection();
    const sStart: number = sel.selection[0];
    const sEnd: number = sel.selection[1];
    const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);

    if (sStart < 0 || sEnd <= sStart) {
      const caret: number = sStart >= 0 ? sStart : this.safeCaret();
      const pIdx: number = WysiwygTriggers.countNewlines(this.prevPlainText, 0, caret);
      if (!this.typingOverrideActive || pIdx !== this.typingOverrideLine ||
        caret < this.typingOverrideStart || caret > this.typingOverrideAnchor) {
        this.typingFlags = this.inspectInlineFlagsAt(caret, this.prevPlainText);
        this.typingOverrideStart = caret;
      }
      if (action === 'bold') {
        this.typingFlags.bold = !this.typingFlags.bold;
      } else if (action === 'italic') {
        this.typingFlags.italic = !this.typingFlags.italic;
      } else if (action === 'strike') {
        this.typingFlags.strike = !this.typingFlags.strike;
      } else if (action === 'code') {
        this.typingFlags.code = !this.typingFlags.code;
        if (this.typingFlags.code) {
          this.typingFlags.highlight = false;
        }
      } else if (action === 'highlight') {
        this.typingFlags.highlight = !this.typingFlags.highlight;
        if (this.typingFlags.highlight) {
          this.typingFlags.code = false;
        }
      }
      this.typingOverrideActive = true;
      this.typingOverrideLine = pIdx;
      this.typingOverrideAnchor = caret;

      const meta: WysiwygParagraph = pIdx < this.metas.length ? this.metas[pIdx] : new WysiwygParagraph();
      const nextStyle: RichEditorTextStyle = this.textStyleFromFlags(meta, this.typingFlags, colors);
      this.richController.setTypingStyle(nextStyle);
      this.emitFormatStateFromFlags(meta, this.typingFlags);
      return;
    }

    this.pushUndoNow();
    const spans = this.richController.getSpans({ start: sStart, end: sEnd });
    const textSpans: RichEditorTextSpanResult[] = [];
    for (const sp of spans) {
      if (!WysiwygStyleHelper.isImageSpanResult(sp)) {
        textSpans.push(WysiwygStyleHelper.asTextSpan(sp));
      }
    }
    if (textSpans.length === 0) {
      return;
    }

    const turnOn: boolean = !this.allSpansHaveFormat(textSpans, action);
    for (const sp of textSpans) {
      const spanStart: number = sp.spanPosition.spanRange[0] + sp.offsetInSpan[0];
      const spanEnd: number = sp.spanPosition.spanRange[0] + sp.offsetInSpan[1];
      if (spanEnd <= spanStart) {
        continue;
      }
      const nextStyle: RichEditorTextStyle = this.applyFormatToResult(sp.textStyle, action, turnOn, colors);
      this.richController.updateSpanStyle({
        start: spanStart,
        end: spanEnd,
        textStyle: nextStyle,
        urlStyle: sp.urlStyle
      });
    }
    this.emitFormatStateAtCaret(sStart, this.prevPlainText);
    this.emitImmediateChange();
  }

  private applyTypingOverrideIfMatching(lineIdx: number, rbStart: number, raStart: number,
    raEnd: number): void {
    if (!this.typingOverrideActive) {
      return;
    }
    if (lineIdx !== this.typingOverrideLine) {
      this.typingOverrideActive = false;
      return;
    }
    const meta: WysiwygParagraph = lineIdx < this.metas.length ? this.metas[lineIdx] : new WysiwygParagraph();
    const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);
    const style: RichEditorTextStyle = this.textStyleFromFlags(meta, this.typingFlags, colors);
    if (raEnd <= raStart) {
      // 退格删改仍在当前覆盖区间内：保持激活态，防止退一格后丢失刚点的 B/I 状态
      if (raEnd >= this.typingOverrideStart && raEnd <= this.typingOverrideAnchor) {
        this.typingOverrideAnchor = raEnd;
        this.richController.setTypingStyle(style);
      } else {
        this.typingOverrideActive = false;
      }
      return;
    }
    if (raStart < this.typingOverrideStart || rbStart > this.typingOverrideAnchor) {
      this.typingOverrideActive = false;
      return;
    }
    this.richController.updateSpanStyle({ start: raStart, end: raEnd, textStyle: style });
    this.typingOverrideAnchor = raEnd;
    this.richController.setTypingStyle(style);
  }

  private textStyleFromFlags(meta: WysiwygParagraph, flags: WysiwygFormatState,
    colors: WysiwygThemeColors): RichEditorTextStyle {
    const inline: WysiwygInline = new WysiwygInline();
    inline.bold = flags.bold;
    inline.italic = flags.italic;
    inline.strike = flags.strike;
    inline.highlight = flags.highlight;
    inline.code = flags.code;
    return WysiwygStyleHelper.buildInlineTextStyle(meta, inline, this.fontSize, colors);
  }

  private inspectInlineFlagsAt(caret: number, curText: string): WysiwygFormatState {
    const flags: WysiwygFormatState = new WysiwygFormatState();
    const pIdx: number = WysiwygTriggers.countNewlines(curText, 0, Math.min(curText.length, caret));
    if (pIdx < 0 || pIdx >= this.metas.length) {
      return flags;
    }
    const meta: WysiwygParagraph = this.metas[pIdx];
    const range: [number, number] = WysiwygTriggers.lineRange(curText, pIdx);
    if (caret <= range[0] || meta.kind === WysiwygBlockKind.CODE ||
      meta.kind === WysiwygBlockKind.TABLE || meta.kind === WysiwygBlockKind.MATH ||
      meta.kind === WysiwygBlockKind.HTML) {
      return flags;
    }
    const probe = this.richController.getSpans({ start: Math.max(range[0], caret - 1), end: caret });
    if (probe.length === 0 || WysiwygStyleHelper.isImageSpanResult(probe[0])) {
      return flags;
    }
    const ts: RichEditorTextSpanResult = WysiwygStyleHelper.asTextSpan(probe[0]);
    if (ts.urlStyle !== undefined && ts.urlStyle.url !== undefined && String(ts.urlStyle.url).length > 0) {
      return flags;
    }
    const fam: string = ts.textStyle.fontFamily !== undefined ? ts.textStyle.fontFamily.toLowerCase() : '';
    if (fam.includes('monospace')) {
      flags.code = true;
      return flags;
    }
    if (meta.kind !== WysiwygBlockKind.HEADING && meta.kind !== WysiwygBlockKind.CALLOUT) {
      flags.bold = WysiwygStyleHelper.isBoldWeight(ts.textStyle.fontWeight);
    }
    flags.italic = ts.textStyle.fontStyle === FontStyle.Italic;
    if (meta.kind !== WysiwygBlockKind.TASK && ts.textStyle.decoration !== undefined &&
      ts.textStyle.decoration.type === TextDecorationType.LineThrough) {
      flags.strike = true;
    }
    const bg: string = ts.textStyle.textBackgroundStyle !== undefined &&
      ts.textStyle.textBackgroundStyle.color !== undefined
      ? String(ts.textStyle.textBackgroundStyle.color).toLowerCase() : '';
    if (bg.length > 0 && bg !== '#00000000' && bg !== '0' &&
      ts.textStyle.textBackgroundStyle?.color !== Color.Transparent) {
      flags.highlight = true;
    }
    return flags;
  }

  private emitFormatStateAtCaret(caret: number, curText: string): void {
    const pIdx: number = WysiwygTriggers.countNewlines(curText, 0, Math.min(curText.length, caret));
    const meta: WysiwygParagraph = pIdx >= 0 && pIdx < this.metas.length ? this.metas[pIdx] : new WysiwygParagraph();
    const overrideMatchesCaret: boolean = this.typingOverrideActive &&
      pIdx === this.typingOverrideLine &&
      caret >= this.typingOverrideStart &&
      caret <= this.typingOverrideAnchor;
    const flags: WysiwygFormatState = overrideMatchesCaret
      ? this.typingFlags.clone()
      : this.inspectInlineFlagsAt(caret, curText);
    this.emitFormatStateFromFlags(meta, flags);
  }

  private emitFormatStateFromFlags(meta: WysiwygParagraph, flags: WysiwygFormatState): void {
    const state: WysiwygFormatState = flags.clone();
    state.headingLevel = meta.kind === WysiwygBlockKind.HEADING ? meta.level : 0;
    if (meta.kind === WysiwygBlockKind.BULLET || meta.kind === WysiwygBlockKind.ORDERED ||
      meta.kind === WysiwygBlockKind.TASK || meta.kind === WysiwygBlockKind.QUOTE) {
      state.blockKind = meta.kind;
    } else {
      state.blockKind = '';
    }
    if (!state.equals(this.lastEmittedFormat)) {
      this.lastEmittedFormat = state;
      this.onFormatStateFn(state);
    }
  }

  private allSpansHaveFormat(spans: RichEditorTextSpanResult[], action: string): boolean {
    for (const sp of spans) {
      const ts: RichEditorTextStyleResult = sp.textStyle;
      if (action === 'bold' && !WysiwygStyleHelper.isBoldWeight(ts.fontWeight)) {
        return false;
      }
      if (action === 'italic' && ts.fontStyle !== FontStyle.Italic) {
        return false;
      }
      if (action === 'strike' && (ts.decoration === undefined ||
        ts.decoration.type !== TextDecorationType.LineThrough)) {
        return false;
      }
      const isMono: boolean = ts.fontFamily !== undefined && ts.fontFamily.toLowerCase().includes('monospace');
      if (action === 'code' && !isMono) {
        return false;
      }
      if (action === 'highlight') {
        const bg: string = ts.textBackgroundStyle !== undefined && ts.textBackgroundStyle.color !== undefined
          ? String(ts.textBackgroundStyle.color).toLowerCase() : '';
        if (isMono || bg.length === 0 || bg === '#00000000' || bg === '0') {
          return false;
        }
      }
    }
    return true;
  }

  private applyFormatToResult(ts: RichEditorTextStyleResult, action: string, turnOn: boolean,
    colors: WysiwygThemeColors): RichEditorTextStyle {
    const curBold: boolean = WysiwygStyleHelper.isBoldWeight(ts.fontWeight);
    const curItalic: boolean = ts.fontStyle === FontStyle.Italic;
    const curStrike: boolean = ts.decoration !== undefined && ts.decoration.type === TextDecorationType.LineThrough;
    const curCode: boolean = ts.fontFamily !== undefined && ts.fontFamily.toLowerCase().includes('monospace');
    const bgStr: string = ts.textBackgroundStyle !== undefined && ts.textBackgroundStyle.color !== undefined
      ? String(ts.textBackgroundStyle.color).toLowerCase() : '';
    const curHl: boolean = !curCode && bgStr.length > 0 && bgStr !== '0' && bgStr !== '#00000000' &&
      ts.textBackgroundStyle?.color !== Color.Transparent;

    const bold: boolean = action === 'bold' ? turnOn : curBold;
    const italic: boolean = action === 'italic' ? turnOn : curItalic;
    const strike: boolean = action === 'strike' ? turnOn : curStrike;
    const code: boolean = action === 'code' ? turnOn : curCode;
    const hl: boolean = action === 'highlight' ? turnOn : (!code && curHl);

    return {
      fontSize: code ? Math.max(12, this.fontSize - 1) : (ts.fontSize > 0 ? ts.fontSize : this.fontSize),
      fontWeight: bold ? FontWeight.Bold : FontWeight.Normal,
      fontStyle: italic ? FontStyle.Italic : FontStyle.Normal,
      fontFamily: code ? 'monospace' : 'HarmonyOS Sans',
      fontColor: code ? $r('app.color.design_text_secondary') : ts.fontColor,
      textBackgroundStyle: code ? { color: colors.codeBg, radius: 4 }
        : (hl ? { color: colors.highlightBg, radius: 4 } : { color: Color.Transparent, radius: 0 }),
      decoration: {
        type: strike ? TextDecorationType.LineThrough
          : (ts.decoration !== undefined && ts.decoration.type === TextDecorationType.Underline
            ? TextDecorationType.Underline : TextDecorationType.None),
        color: ts.fontColor
      }
    };
  }

  private insertTriggerText(token: string): void {
    const curText: string = this.prevPlainText;
    this.syncMetaCountToPlainText(curText);
    const caret: number = this.safeCaret();
    const pIdx: number = WysiwygTriggers.countNewlines(curText, 0, caret);
    const meta: WysiwygParagraph = pIdx < this.metas.length ? this.metas[pIdx] : new WysiwygParagraph();
    const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);
    const style: RichEditorTextStyle = WysiwygStyleHelper.buildDefaultTextStyle(meta, this.fontSize, colors);
    this.replaceSpanRangeWithPlain(caret, caret, token, style, pIdx);
    this.lastCaretOffset = caret + token.length;
    this.richController.setCaretOffset(this.lastCaretOffset);
    this.scheduleDebouncedSync();
  }

  private insertHorizontalRule(): void {
    const curText: string = this.prevPlainText;
    this.syncMetaCountToPlainText(curText);
    const caret: number = this.safeCaret();
    const pIdx: number = WysiwygTriggers.countNewlines(curText, 0, caret);
    const range: [number, number] = WysiwygTriggers.lineRange(curText, pIdx);
    const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);
    const hrStyle: WysiwygParagraph = new WysiwygParagraph();
    hrStyle.kind = WysiwygBlockKind.HR;
    const hrTextStyle: RichEditorTextStyle = WysiwygStyleHelper.buildDefaultTextStyle(hrStyle, this.fontSize, colors);
    const hrPStyle: RichEditorParagraphStyle = WysiwygStyleHelper.buildParagraphStyle(
      hrStyle, this.margins, this.resMgr, this.fontSize);
    const bodyPara: WysiwygParagraph = new WysiwygParagraph();
    const bodyTextStyle: RichEditorTextStyle = WysiwygStyleHelper.buildDefaultTextStyle(bodyPara, this.fontSize, colors);
    const bodyPStyle: RichEditorParagraphStyle = WysiwygStyleHelper.buildParagraphStyle(
      bodyPara, this.margins, this.resMgr, this.fontSize);

    if (range[0] === range[1]) {
      this.metas[pIdx] = hrStyle;
      this.metas.splice(pIdx + 1, 0, bodyPara);
      const nextText: string = `${curText.substring(0, caret)}${WysiwygTriggers.HR_DISPLAY}\n${curText.substring(caret)}`;
      this.expectedProgrammaticText = nextText;
      this.richController.addTextSpan(WysiwygTriggers.HR_DISPLAY, {
        offset: caret, style: hrTextStyle, paragraphStyle: hrPStyle
      });
      this.richController.addTextSpan('\n', {
        offset: caret + WysiwygTriggers.HR_DISPLAY.length, style: bodyTextStyle, paragraphStyle: hrPStyle
      });
      this.prevPlainText = nextText;
      this.lastCaretOffset = caret + WysiwygTriggers.HR_DISPLAY.length + 1;
      this.richController.setCaretOffset(this.lastCaretOffset);
      this.richController.setTypingParagraphStyle(bodyPStyle);
      this.richController.setTypingStyle(bodyTextStyle);
    } else {
      const insertAt: number = range[1];
      this.metas.splice(pIdx + 1, 0, hrStyle, bodyPara);
      const inserted: string = `\n${WysiwygTriggers.HR_DISPLAY}\n`;
      const nextText: string = `${curText.substring(0, insertAt)}${inserted}${curText.substring(insertAt)}`;
      this.expectedProgrammaticText = nextText;
      this.richController.addTextSpan('\n', { offset: insertAt, style: bodyTextStyle, paragraphStyle: bodyPStyle });
      this.richController.addTextSpan(WysiwygTriggers.HR_DISPLAY, {
        offset: insertAt + 1, style: hrTextStyle, paragraphStyle: hrPStyle
      });
      this.richController.addTextSpan('\n', {
        offset: insertAt + 1 + WysiwygTriggers.HR_DISPLAY.length, style: bodyTextStyle, paragraphStyle: hrPStyle
      });
      this.prevPlainText = nextText;
      this.lastCaretOffset = insertAt + inserted.length;
      this.richController.setCaretOffset(this.lastCaretOffset);
      this.richController.setTypingParagraphStyle(bodyPStyle);
      this.richController.setTypingStyle(bodyTextStyle);
    }
    this.emitActiveKind();
    this.emitImmediateChange();
  }

  private insertTableBlock(): void {
    const curText: string = this.prevPlainText;
    this.syncMetaCountToPlainText(curText);
    this.pushUndoNow();
    const caret: number = this.safeCaret();
    const pIdx: number = WysiwygTriggers.countNewlines(curText, 0, caret);
    const range: [number, number] = WysiwygTriggers.lineRange(curText, pIdx);
    const defaultMd: string = WysiwygTableCodec.toMarkdown(WysiwygTableCodec.defaultTable());
    const tMeta: WysiwygParagraph = WysiwygCodec.buildTableParagraph(defaultMd);
    tMeta.blockGroupId = this.nextTableId++;
    const rendered: RenderedTableImage = WysiwygTableRenderer.render(
      defaultMd, this.contentWidthVp, this.fontSize, this.resMgr);

    if (rendered.pixelMap === undefined) {
      this.emitActiveKind();
      this.emitImmediateChange();
      return;
    }

    this.tablePixelMaps.set(tMeta.blockGroupId, rendered.pixelMap);
    const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);
    const bodyPara: WysiwygParagraph = new WysiwygParagraph();
    const bodyStyle: RichEditorTextStyle = WysiwygStyleHelper.buildDefaultTextStyle(
      bodyPara, this.fontSize, colors);
    const emptyLine: boolean = range[0] === range[1];
    const insertIdx: number = emptyLine ? pIdx : pIdx + 1;
    const isAtEnd: boolean = emptyLine ? pIdx + 1 >= this.metas.length : pIdx + 1 >= this.metas.length;

    if (emptyLine) {
      if (isAtEnd) {
        this.metas.splice(pIdx, 1, tMeta, bodyPara);
      } else {
        this.metas.splice(pIdx, 1, tMeta);
      }
    } else {
      if (isAtEnd) {
        this.metas.splice(pIdx + 1, 0, tMeta, bodyPara);
      } else {
        this.metas.splice(pIdx + 1, 0, tMeta);
      }
    }

    const tPStyle: RichEditorParagraphStyle = this.paragraphStyleForIndex(this.metas, insertIdx);
    const bodyPStyle: RichEditorParagraphStyle = WysiwygStyleHelper.buildParagraphStyle(
      bodyPara, this.margins, this.resMgr, this.fontSize);

    const leadNl: string = emptyLine ? '' : '\n';
    const tailNl: string = isAtEnd ? '\n' : '';
    const insertAt: number = emptyLine ? range[0] : range[1];
    const insertedStr: string = `${leadNl} ${tailNl}`;
    const nextText: string = `${curText.substring(0, insertAt)}${insertedStr}${curText.substring(insertAt)}`;

    let cursor: number = insertAt;
    this.isLoadingDocument = true;
    try {
      this.expectedProgrammaticText = nextText;
      if (leadNl.length > 0) {
        const curPStyle: RichEditorParagraphStyle = this.paragraphStyleForIndex(this.metas, pIdx);
        this.richController.addTextSpan('\n', { offset: cursor, style: bodyStyle, paragraphStyle: curPStyle });
        cursor += 1;
      }
      this.richController.addImageSpan(rendered.pixelMap,
        this.buildTableImageOptions(rendered, tMeta.blockGroupId, cursor));
      this.richController.updateParagraphStyle({ start: cursor, end: cursor + 1, style: tPStyle });
      cursor += 1;
      if (tailNl.length > 0) {
        this.richController.addTextSpan('\n', { offset: cursor, style: bodyStyle, paragraphStyle: bodyPStyle });
        cursor += 1;
      }
      this.prevPlainText = nextText;
      this.expectedProgrammaticText = nextText;
      this.lastCaretOffset = cursor;
      this.richController.setCaretOffset(cursor);
      this.applyTypingStyleForCaret(emptyLine && !isAtEnd ? insertIdx : insertIdx + (isAtEnd ? 1 : 0), cursor, nextText);
    } finally {
      this.isLoadingDocument = false;
    }
    this.emitActiveKind();
    this.emitImmediateChange();
    this.onEditTableFn(tMeta.blockGroupId, tMeta.tableRawMd);
  }

  /** 用户在可视化表格编辑器保存修改或点击删除表格后回写文档。 */
  public applyTableEdit(tableId: number, nextRawMd: string): void {
    const pIdx: number = this.findTableParagraphIndex(tableId);
    if (pIdx < 0) {
      return;
    }
    const curText: string = this.prevPlainText;
    this.syncMetaCountToPlainText(curText);
    const meta: WysiwygParagraph = this.metas[pIdx];
    const trimmedMd: string = nextRawMd.trim();
    if (trimmedMd.length > 0 && trimmedMd === meta.tableRawMd.trim()) {
      return;
    }

    this.pushUndoNow();
    const range: [number, number] = WysiwygTriggers.lineRange(curText, pIdx);
    const oldPm: PixelMap | undefined = this.tablePixelMaps.get(tableId);

    if (trimmedMd.length === 0) {
      this.tablePixelMaps.delete(tableId);
      this.isLoadingDocument = true;
      try {
        if (this.metas.length <= 1) {
          this.metas = [new WysiwygParagraph()];
          this.expectedProgrammaticText = '';
          this.richController.deleteSpans();
          this.prevPlainText = '';
          this.lastCaretOffset = 0;
          this.richController.setCaretOffset(0);
          this.applyParagraphVisualStyle(0, '');
          this.applyTypingStyleForCaret(0, 0, '');
        } else {
          const delStart: number = pIdx > 0 ? range[0] - 1 : range[0];
          const delEnd: number = pIdx > 0 ? range[1] : Math.min(curText.length, range[1] + 1);
          const nextText: string = `${curText.substring(0, delStart)}${curText.substring(delEnd)}`;
          this.metas.splice(pIdx, 1);
          this.expectedProgrammaticText = nextText;
          this.richController.deleteSpans({ start: delStart, end: delEnd });
          this.prevPlainText = nextText;
          this.expectedProgrammaticText = nextText;
          const nextCaret: number = Math.max(0, Math.min(nextText.length, delStart));
          this.lastCaretOffset = nextCaret;
          this.richController.setCaretOffset(nextCaret);
          const activeP: number = WysiwygTriggers.countNewlines(nextText, 0, nextCaret);
          this.applyParagraphVisualStyle(activeP, nextText);
          this.applyTypingStyleForCaret(activeP, nextCaret, nextText);
        }
      } finally {
        this.isLoadingDocument = false;
      }
      if (oldPm !== undefined) {
        oldPm.release();
      }
      this.emitActiveKind();
      this.emitImmediateChange();
      return;
    }

    meta.tableRawMd = trimmedMd;
    const inline: WysiwygInline = WysiwygInline.plain('');
    inline.isImage = true;
    inline.imageTarget = 'table';
    inline.imageRawMd = trimmedMd;
    meta.inlines = [inline];

    const rendered: RenderedTableImage = WysiwygTableRenderer.render(
      trimmedMd, this.contentWidthVp, this.fontSize, this.resMgr);
    if (rendered.pixelMap === undefined) {
      if (oldPm !== undefined) {
        this.tablePixelMaps.delete(tableId);
        oldPm.release();
      }
      this.emitImmediateChange();
      return;
    }

    const nextText: string = `${curText.substring(0, range[0])} ${curText.substring(range[1])}`;
    const pStyle: RichEditorParagraphStyle = this.paragraphStyleForIndex(this.metas, pIdx);
    this.isLoadingDocument = true;
    try {
      this.expectedProgrammaticText = nextText;
      if (range[1] > range[0]) {
        this.richController.deleteSpans({ start: range[0], end: range[1] });
      }
      this.richController.addImageSpan(rendered.pixelMap,
        this.buildTableImageOptions(rendered, tableId, range[0]));
      this.richController.updateParagraphStyle({ start: range[0], end: range[0] + 1, style: pStyle });
      this.tablePixelMaps.set(tableId, rendered.pixelMap);
      this.prevPlainText = nextText;
      this.expectedProgrammaticText = nextText;
      const nextCaret: number = Math.min(nextText.length, range[0] + 1);
      this.lastCaretOffset = nextCaret;
      this.richController.setCaretOffset(nextCaret);
    } finally {
      this.isLoadingDocument = false;
    }
    if (oldPm !== undefined && oldPm !== rendered.pixelMap) {
      oldPm.release();
    }
    this.emitActiveKind();
    this.emitImmediateChange();
  }

  private buildTableImageOptions(
    rendered: RenderedTableImage,
    tableId: number,
    offset: number
  ): RichEditorImageSpanOptions {
    const opts: RichEditorImageSpanOptions = {
      imageStyle: {
        size: [rendered.widthVp, rendered.heightVp],
        objectFit: ImageFit.Contain,
        layoutStyle: { borderRadius: 10, margin: { top: 4, bottom: 4 } }
      },
      gesture: {
        onClick: (): void => {
          this.handleTableSpanClick(tableId);
        }
      }
    };
    if (offset >= 0) {
      opts.offset = offset;
    }
    return opts;
  }

  private handleTableSpanClick(tableId: number): void {
    const pIdx: number = this.findTableParagraphIndex(tableId);
    if (pIdx < 0) {
      return;
    }
    this.onEditTableFn(tableId, this.metas[pIdx].tableRawMd);
  }

  private findTableParagraphIndex(tableId: number): number {
    for (let i: number = 0; i < this.metas.length; i++) {
      if (this.metas[i].kind === WysiwygBlockKind.TABLE && this.metas[i].blockGroupId === tableId) {
        return i;
      }
    }
    return -1;
  }

  private hasTableBlock(): boolean {
    for (const meta of this.metas) {
      if (meta.kind === WysiwygBlockKind.TABLE) {
        return true;
      }
    }
    return false;
  }

  private clearTablePixelMaps(): void {
    for (const pm of this.tablePixelMaps.values()) {
      pm.release();
    }
    this.tablePixelMaps.clear();
  }

  private refreshRenderedTables(): void {
    if (!this.ready || this.isLoadingDocument) {
      return;
    }
    const savedCaret: number = this.safeCaret();
    const curText: string = this.prevPlainText;
    this.isLoadingDocument = true;
    try {
      for (let i: number = this.metas.length - 1; i >= 0; i--) {
        const meta: WysiwygParagraph = this.metas[i];
        if (meta.kind !== WysiwygBlockKind.TABLE) {
          continue;
        }
        const range: [number, number] = WysiwygTriggers.lineRange(curText, i);
        if (range[1] - range[0] !== 1) {
          continue;
        }
        if (meta.blockGroupId <= 0) {
          meta.blockGroupId = this.nextTableId++;
        }
        const tableId: number = meta.blockGroupId;
        const rendered: RenderedTableImage = WysiwygTableRenderer.render(
          meta.tableRawMd, this.contentWidthVp, this.fontSize, this.resMgr);
        if (rendered.pixelMap === undefined) {
          continue;
        }
        const oldPm: PixelMap | undefined = this.tablePixelMaps.get(tableId);
        this.tablePixelMaps.set(tableId, rendered.pixelMap);
        this.richController.deleteSpans({ start: range[0], end: range[1] });
        this.richController.addImageSpan(rendered.pixelMap,
          this.buildTableImageOptions(rendered, tableId, range[0]));
        this.richController.updateParagraphStyle({
          start: range[0],
          end: range[0] + 1,
          style: this.paragraphStyleForIndex(this.metas, i)
        });
        if (oldPm !== undefined && oldPm !== rendered.pixelMap) {
          oldPm.release();
        }
      }
      this.richController.setCaretOffset(Math.max(0, Math.min(curText.length, savedCaret)));
    } finally {
      this.isLoadingDocument = false;
    }
  }

  private handleMutationOnTableLine(
    lineIdx: number,
    raStart: number,
    raEnd: number,
    insertedSlice: string,
    newText: string
  ): number {
    const lineR: [number, number] = WysiwygTriggers.lineRange(newText, lineIdx);
    const meta: WysiwygParagraph = this.metas[lineIdx];
    if (lineR[1] === lineR[0]) {
      const oldPm: PixelMap | undefined = this.tablePixelMaps.get(meta.blockGroupId);
      this.tablePixelMaps.delete(meta.blockGroupId);
      if (oldPm !== undefined) {
        oldPm.release();
      }
      meta.kind = WysiwygBlockKind.PARAGRAPH;
      meta.tableRawMd = '';
      meta.blockGroupId = 0;
      meta.inlines = [];
      this.applyParagraphVisualStyle(lineIdx, newText);
      this.applyTypingStyleForCaret(lineIdx, lineR[0], newText);
      return lineR[0];
    }
    if (raEnd > raStart && insertedSlice.length > 0) {
      const typedBeforeTable: boolean = raStart <= lineR[0];
      const splitAt: number = typedBeforeTable ? raEnd : raStart;
      const nextText: string = `${newText.substring(0, splitAt)}\n${newText.substring(splitAt)}`;
      this.expectedProgrammaticText = nextText;
      this.richController.addTextSpan('\n', { offset: splitAt });
      if (typedBeforeTable) {
        const tblClone: WysiwygParagraph = meta.clone();
        this.metas.splice(lineIdx, 1, new WysiwygParagraph(), tblClone);
        this.prevPlainText = nextText;
        this.applyParagraphVisualStyle(lineIdx, nextText);
        this.applyParagraphVisualStyle(lineIdx + 1, nextText);
        this.richController.setCaretOffset(raEnd);
        this.applyTypingStyleForCaret(lineIdx, raEnd, nextText);
        return raEnd;
      }
      this.metas.splice(lineIdx + 1, 0, new WysiwygParagraph());
      this.prevPlainText = nextText;
      this.applyParagraphVisualStyle(lineIdx + 1, nextText);
      const nextCaret: number = raEnd + 1;
      this.richController.setCaretOffset(nextCaret);
      this.applyTypingStyleForCaret(lineIdx + 1, nextCaret, nextText);
      return nextCaret;
    }
    return -1;
  }

  private applyParagraphVisualStyle(pIdx: number, fullText: string): void {
    if (pIdx < 0 || pIdx >= this.metas.length) {
      return;
    }
    const meta: WysiwygParagraph = this.metas[pIdx];
    const pStyle: RichEditorParagraphStyle = this.paragraphStyleForIndex(this.metas, pIdx);
    const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);
    const range: [number, number] = WysiwygTriggers.lineRange(fullText, pIdx);
    const spanEnd: number = Math.min(fullText.length, range[1] + 1);
    if (spanEnd > range[0]) {
      this.richController.updateParagraphStyle({
        start: range[0],
        end: spanEnd,
        style: pStyle
      });
    }
    if (range[1] > range[0]) {
      if (meta.kind === WysiwygBlockKind.CODE) {
        this.rehighlightCodeLine(pIdx);
        return;
      }
      const spans = this.richController.getSpans({ start: range[0], end: range[1] });
      for (const sp of spans) {
        if (WysiwygStyleHelper.isImageSpanResult(sp)) {
          continue;
        }
        const ts: RichEditorTextSpanResult = WysiwygStyleHelper.asTextSpan(sp);
        const s0: number = ts.spanPosition.spanRange[0] + ts.offsetInSpan[0];
        const s1: number = ts.spanPosition.spanRange[0] + ts.offsetInSpan[1];
        if (s1 <= s0) {
          continue;
        }
        const inline: WysiwygInline = this.inlineFromExistingSpan(meta, ts);
        this.richController.updateSpanStyle({
          start: s0,
          end: s1,
          textStyle: WysiwygStyleHelper.buildInlineTextStyle(meta, inline, this.fontSize, colors),
          urlStyle: ts.urlStyle
        });
      }
    }
  }

  private rehighlightCodeLine(pIdx: number): void {
    if (pIdx < 0 || pIdx >= this.metas.length) {
      return;
    }
    const curText: string = this.prevPlainText;
    const range: [number, number] = WysiwygTriggers.lineRange(curText, pIdx);
    if (range[1] <= range[0]) {
      return;
    }
    const lineStr: string = curText.substring(range[0], range[1]);
    const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);
    const tokens: CodeToken[] = WysiwygStyleHelper.tokenizeCodeLine(lineStr, this.metas[pIdx].lang);
    let cursor: number = range[0];
    for (const tok of tokens) {
      const len: number = tok.text.length;
      if (len > 0) {
        this.richController.updateSpanStyle({
          start: cursor,
          end: cursor + len,
          textStyle: WysiwygStyleHelper.buildCodeTokenStyle(tok, this.fontSize, colors)
        });
        cursor += len;
      }
    }
  }

  private inlineFromExistingSpan(meta: WysiwygParagraph, sp: RichEditorTextSpanResult): WysiwygInline {
    const inline: WysiwygInline = new WysiwygInline();
    inline.text = sp.value;
    const urlStr: string | undefined = sp.urlStyle !== undefined && sp.urlStyle.url !== undefined
      ? String(sp.urlStyle.url) : undefined;
    const decoded: DecodedSpanUrl = WysiwygStyleHelper.decodeSpanUrl(urlStr);
    inline.kind = decoded.kind;
    inline.target = decoded.target;
    inline.originalDisplay = decoded.originalDisplay;
    if (decoded.kind === WysiwygSpanKind.PLAIN) {
      const fam: string = sp.textStyle.fontFamily !== undefined ? sp.textStyle.fontFamily.toLowerCase() : '';
      inline.code = fam.includes('monospace');
      inline.bold = meta.kind !== WysiwygBlockKind.HEADING &&
        WysiwygStyleHelper.isBoldWeight(sp.textStyle.fontWeight);
      inline.italic = sp.textStyle.fontStyle === FontStyle.Italic;
      inline.strike = meta.kind !== WysiwygBlockKind.TASK &&
        sp.textStyle.decoration !== undefined &&
        sp.textStyle.decoration.type === TextDecorationType.LineThrough;
      const bg: string = sp.textStyle.textBackgroundStyle !== undefined &&
        sp.textStyle.textBackgroundStyle.color !== undefined
        ? String(sp.textStyle.textBackgroundStyle.color).toLowerCase() : '';
      inline.highlight = !inline.code && bg.length > 0 && bg !== '#00000000' && bg !== '0' &&
        sp.textStyle.textBackgroundStyle?.color !== Color.Transparent;
    }
    return inline;
  }

  private renumberOrderedFrom(anchorIdx: number, fullText: string): void {
    let i: number = anchorIdx;
    while (i > 0 && this.metas[i - 1].kind === WysiwygBlockKind.ORDERED &&
      this.metas[i - 1].indent === this.metas[anchorIdx].indent) {
      i--;
    }
    let ord: number = 1;
    while (i < this.metas.length && this.metas[i].kind === WysiwygBlockKind.ORDERED) {
      if (this.metas[i].indent === this.metas[anchorIdx].indent) {
        if (i === anchorIdx && ord === 1 && this.metas[i].ordinal > 1) {
          ord = this.metas[i].ordinal;
        }
        if (this.metas[i].ordinal !== ord) {
          this.metas[i].ordinal = ord;
          this.applyParagraphVisualStyle(i, fullText);
        }
        ord++;
      }
      i++;
    }
  }

  private applyTypingStyleForCaret(pIdx: number, caret: number, curText: string): void {
    if (pIdx < 0 || pIdx >= this.metas.length) {
      return;
    }
    const meta: WysiwygParagraph = this.metas[pIdx];
    const colors: WysiwygThemeColors = WysiwygStyleHelper.resolveThemeColors(this.resMgr);
    this.richController.setTypingParagraphStyle(this.paragraphStyleForIndex(this.metas, pIdx));

    const range: [number, number] = WysiwygTriggers.lineRange(curText, pIdx);
    const defaultStyle: RichEditorTextStyle = WysiwygStyleHelper.buildDefaultTextStyle(
      meta, this.fontSize, colors);
    if (caret <= range[0] || meta.kind === WysiwygBlockKind.HEADING ||
      meta.kind === WysiwygBlockKind.CODE || meta.kind === WysiwygBlockKind.TABLE ||
      meta.kind === WysiwygBlockKind.MATH || meta.kind === WysiwygBlockKind.HTML) {
      this.richController.setTypingStyle(defaultStyle);
      return;
    }
    const flags: WysiwygFormatState = this.inspectInlineFlagsAt(caret, curText);
    if (flags.bold || flags.italic || flags.strike || flags.highlight || flags.code) {
      this.richController.setTypingStyle(this.textStyleFromFlags(meta, flags, colors));
    } else {
      this.richController.setTypingStyle(defaultStyle);
    }
  }

  private replaceSpanRangeWithPlain(start: number, end: number, text: string,
    style: RichEditorTextStyle, pIdx: number): void {
    const curText: string = this.prevPlainText;
    const pStyle: RichEditorParagraphStyle = pIdx < this.metas.length
      ? this.paragraphStyleForIndex(this.metas, pIdx)
      : WysiwygStyleHelper.buildParagraphStyle(new WysiwygParagraph(), this.margins, this.resMgr, this.fontSize);
    const nextText: string = `${curText.substring(0, start)}${text}${curText.substring(end)}`;
    this.expectedProgrammaticText = nextText;
    if (end > start) {
      this.richController.deleteSpans({ start: start, end: end });
    }
    if (text.length > 0) {
      this.richController.addTextSpan(text, { offset: start, style: style, paragraphStyle: pStyle });
    }
    this.prevPlainText = nextText;
  }

  private syncMetaCountToPlainText(text: string): void {
    const lineCount: number = text.split('\n').length;
    while (this.metas.length < lineCount) {
      this.metas.push(new WysiwygParagraph());
    }
    if (this.metas.length > lineCount) {
      this.metas.splice(lineCount);
    }
  }

  private buildCompletionQuery(text: string, caretHint: number = -1): WysiwygCompletionQuery | null {
    const caret: number = caretHint >= 0
      ? Math.max(0, Math.min(text.length, caretHint))
      : Math.max(0, Math.min(text.length, this.safeCaret()));
    const pIdx: number = WysiwygTriggers.countNewlines(text, 0, caret);
    const range: [number, number] = WysiwygTriggers.lineRange(text, pIdx);
    const linePrefix: string = text.substring(range[0], caret);
    if (!linePrefix.includes('[[') && !linePrefix.includes('#')) {
      return null;
    }
    const q: WysiwygCompletionQuery = new WysiwygCompletionQuery();
    q.paraTextUpToCaret = linePrefix;
    q.caretInPara = caret - range[0];
    q.paraStart = range[0];
    q.globalCaret = caret;
    return q;
  }

  private concatInlineText(inlines: WysiwygInline[]): string {
    let text: string = '';
    for (const item of inlines) {
      text += item.text;
    }
    return text;
  }

  private safeCaret(): number {
    if (!this.ready) {
      return 0;
    }
    return Math.max(0, this.richController.getCaretOffset());
  }

  /** 在按键即将发生前，以零开销（尽量直接复用 lastSyncedMarkdown）压入撤销快照。 */
  private pushUndoFromCache(caretHint: number): void {
    if (!this.ready) {
      return;
    }
    const now: number = Date.now();
    if (now - this.lastUndoPushMs < WysiwygEditorEngine.UNDO_DEBOUNCE_MS && this.undoStack.length > 0) {
      return;
    }
    const snapMd: string = this.dirtyForSync ? this.exportMarkdown() : this.lastSyncedMarkdown;
    this.commitUndoSnapshot(snapMd, caretHint);
  }

  private pushUndoNow(): void {
    if (!this.ready) {
      return;
    }
    const md: string = this.dirtyForSync ? this.exportMarkdown() : this.lastSyncedMarkdown;
    this.commitUndoSnapshot(md, this.safeCaret());
  }

  private commitUndoSnapshot(md: string, caret: number): void {
    if (this.undoStack.length > 0 && this.undoStack[this.undoStack.length - 1].md === md) {
      this.lastUndoPushMs = Date.now();
      return;
    }
    const snap: WysiwygUndoSnapshot = new WysiwygUndoSnapshot();
    snap.md = md;
    snap.caret = caret;
    this.undoStack.push(snap);
    if (this.undoStack.length > WysiwygEditorEngine.MAX_UNDO) {
      this.undoStack.shift();
    }
    this.redoStack = [];
    this.lastUndoPushMs = Date.now();
    this.onHistoryChangeFn(this.undoStack.length, this.redoStack.length);
  }

  private scheduleDebouncedSync(): void {
    this.dirtyForSync = true;
    this.clearSyncTimer();
    this.syncTimerId = setTimeout((): void => {
      this.syncTimerId = -1;
      if (this.ready && this.dirtyForSync) {
        this.emitImmediateChange();
      }
    }, WysiwygEditorEngine.SYNC_DEBOUNCE_MS);
  }

  private flushDebouncedSync(): void {
    if (this.syncTimerId >= 0) {
      clearTimeout(this.syncTimerId);
      this.syncTimerId = -1;
    }
    if (this.ready && this.dirtyForSync) {
      this.emitImmediateChange();
    }
  }

  private clearSyncTimer(): void {
    if (this.syncTimerId >= 0) {
      clearTimeout(this.syncTimerId);
      this.syncTimerId = -1;
    }
  }

  private emitActiveKind(): void {
    const text: string = this.prevPlainText;
    const pIdx: number = WysiwygTriggers.countNewlines(text, 0, this.safeCaret());
    if (pIdx >= 0 && pIdx < this.metas.length) {
      this.onActiveKindFn(this.metas[pIdx].kind, this.metas[pIdx].lang);
    }
  }

  private emitImmediateChange(): void {
    this.clearSyncTimer();
    this.onMarkdownChangeFn(this.exportMarkdown());
  }
}
