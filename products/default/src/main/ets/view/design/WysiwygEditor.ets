import { resourceManager } from '@kit.LocalizationKit';
import { WysiwygBlockKind, WysiwygTriggers } from '@ohos/markdown';
import { DesignTokens } from '../../viewmodel/DesignTokens';
import { WysiwygCompletionQuery, WysiwygEditorEngine, WysiwygFormatState } from './WysiwygEditorEngine';
import { WysiwygPropertiesCard } from './WysiwygPropertiesCard';

/** 供宿主 EditorPane 操控 WYSIWYG 编辑器的稳定桥接器。 */
export class WysiwygEditorBridge {
  public loadMarkdown: (md: string) => void = (_md: string): void => {};
  public exportMarkdown: () => string = (): string => '';
  public getPlainText: () => string = (): string => '';
  public getCaretOffset: () => number = (): number => 0;
  public getSourceCaretOffset: () => number = (): number => 0;
  public applyToolbarAction: (action: string) => void = (_action: string): void => {};
  public insertImageTarget: (target: string) => void = (_target: string): void => {};
  public applyCompletionCandidate: (replaceFrom: number, replaceTo: number, title: string,
    insertText: string, kind: 'wiki' | 'tag') => void =
    (_f: number, _t: number, _title: string, _ins: string, _k: 'wiki' | 'tag'): void => {};
  public selectRange: (start: number, end: number) => void = (_s: number, _e: number): void => {};
  public replaceRange: (start: number, end: number, replacement: string) => void =
    (_s: number, _e: number, _r: string): void => {};
  public replaceAllKeyword: (keyword: string, replacement: string) => void =
    (_k: string, _r: string): void => {};
  public undo: () => void = (): void => {};
  public redo: () => void = (): void => {};
  public getUndoDepth: () => number = (): number => 0;
  public getRedoDepth: () => number = (): number => 0;
  public requestFocus: () => void = (): void => {};
  public applyTableEdit: (tableId: number, nextRawMd: string) => void =
    (_id: number, _md: string): void => {};
}

/**
 * 纯原生 ArkUI RichEditor 所见即所得编辑器组件：
 * - 顶部：可折叠/编辑的笔记属性卡片（对标 Obsidian Live Preview 属性条）
 * - 代码块辅助条：光标落入代码块时展示并支持切换语言标记
 * - 正文：单面连续 ArkUI RichEditor，零 WebView，原生 120Hz 滑动与中文 IME/原生选择菜单
 */
@ComponentV2
export struct WysiwygEditor {
  public static readonly EDITOR_ID: string = 'mysidian_wysiwyg_rich';

  @Param initialMarkdown: string = '';
  @Param docKey: string = '';
  @Param fontSize: number = 15;
  @Param initialCaret: number = 0;
  @Param focusAfterLoad: boolean = false;
  @Param bridge: WysiwygEditorBridge = new WysiwygEditorBridge();
  @Event onResolveAsset: (target: string) => string = (_target: string): string => '';
  @Event onMarkdownChange: (markdown: string) => void = (_md: string): void => {};
  @Event onKeyboardModeChange: (editing: boolean) => void = (_editing: boolean): void => {};
  @Event onCompletionQuery: (query: WysiwygCompletionQuery | null, popupX: number, popupY: number) => void =
    (_q: WysiwygCompletionQuery | null, _x: number, _y: number): void => {};
  @Event onTriggerImagePick: () => void = (): void => {};
  @Event onHistoryChange: (undoDepth: number, redoDepth: number) => void =
    (_u: number, _r: number): void => {};
  @Event onFormatStateChange: (state: WysiwygFormatState) => void =
    (_s: WysiwygFormatState): void => {};
  @Event onOpenTableEditor: (tableId: number, rawMd: string) => void =
    (_id: number, _rawMd: string): void => {};
  @Event onTouchEditor: (event: TouchEvent) => void = (_e: TouchEvent): void => {};

  private readonly engine: WysiwygEditorEngine = new WysiwygEditorEngine();
  private lastLoadedDocKey: string = '';
  @Local hasFrontmatter: boolean = false;
  @Local frontmatterRaw: string = '';
  @Local activeKind: WysiwygBlockKind = WysiwygBlockKind.PARAGRAPH;
  @Local activeCodeLang: string = '';
  @Local editingCodeLang: boolean = false;
  @Local codeLangInput: string = '';
  private richOriginX: number = 0;
  private richOriginY: number = 0;
  private wrapOriginX: number = 0;
  private wrapOriginY: number = 0;

  @Monitor('fontSize')
  onFontSizeChanged(): void {
    this.syncEnv();
  }

  @Monitor('docKey')
  onDocKeyChanged(): void {
    if (this.docKey !== this.lastLoadedDocKey) {
      this.lastLoadedDocKey = this.docKey;
      this.engine.loadMarkdown(this.initialMarkdown, this.initialCaret, this.focusAfterLoad);
      this.syncFmState();
    }
  }

  aboutToAppear(): void {
    this.lastLoadedDocKey = this.docKey;
    this.bindBridge();
    this.syncEnv();
    this.engine.bindCallbacks(
      (target: string): string => this.onResolveAsset(target),
      (md: string): void => {
        this.onMarkdownChange(md);
      },
      (kind: WysiwygBlockKind, lang: string): void => {
        this.activeKind = kind;
        this.activeCodeLang = lang;
        if (kind !== WysiwygBlockKind.CODE) {
          this.editingCodeLang = false;
        }
      },
      (): void => {
        this.onTriggerImagePick();
      },
      (u: number, r: number): void => {
        this.onHistoryChange(u, r);
      },
      (state: WysiwygFormatState): void => {
        this.onFormatStateChange(state);
      },
      (tableId: number, rawMd: string): void => {
        this.onOpenTableEditor(tableId, rawMd);
      }
    );
    this.engine.loadMarkdown(this.initialMarkdown, this.initialCaret, this.focusAfterLoad);
    this.syncFmState();
  }

  aboutToDisappear(): void {
    this.engine.onDisappear();
  }

  private bindBridge(): void {
    this.bridge.loadMarkdown = (md: string): void => {
      this.engine.loadMarkdown(md, 0);
      this.syncFmState();
    };
    this.bridge.exportMarkdown = (): string => this.engine.exportMarkdown();
    this.bridge.getPlainText = (): string => this.engine.getPlainText();
    this.bridge.getCaretOffset = (): number => this.engine.getCaretOffset();
    this.bridge.getSourceCaretOffset = (): number => this.engine.getSourceCaretOffset();
    this.bridge.applyToolbarAction = (action: string): void => {
      this.engine.applyToolbarAction(action);
    };
    this.bridge.insertImageTarget = (target: string): void => {
      this.engine.insertImageTarget(target);
    };
    this.bridge.applyCompletionCandidate = (replaceFrom: number, replaceTo: number,
      title: string, insertText: string, kind: 'wiki' | 'tag'): void => {
      this.engine.applyCompletionCandidate(replaceFrom, replaceTo, title, insertText, kind);
    };
    this.bridge.selectRange = (start: number, end: number): void => {
      this.engine.selectRange(start, end);
    };
    this.bridge.replaceRange = (start: number, end: number, replacement: string): void => {
      this.engine.replaceRange(start, end, replacement);
    };
    this.bridge.replaceAllKeyword = (keyword: string, replacement: string): void => {
      this.engine.replaceAllKeyword(keyword, replacement);
    };
    this.bridge.undo = (): void => {
      this.engine.undo();
      this.syncFmState();
    };
    this.bridge.redo = (): void => {
      this.engine.redo();
      this.syncFmState();
    };
    this.bridge.getUndoDepth = (): number => this.engine.getUndoDepth();
    this.bridge.getRedoDepth = (): number => this.engine.getRedoDepth();
    this.bridge.requestFocus = (): void => {
      this.engine.requestFocus();
    };
    this.bridge.applyTableEdit = (tableId: number, nextRawMd: string): void => {
      this.engine.applyTableEdit(tableId, nextRawMd);
    };
  }

  private syncEnv(): void {
    let mgr: resourceManager.ResourceManager | null = null;
    try {
      const hostCtx = this.getUIContext().getHostContext();
      if (hostCtx !== undefined && hostCtx !== null) {
        mgr = hostCtx.resourceManager;
      }
    } catch (error) {
    }
    this.engine.setEnvironment(mgr, this.getUIContext(), this.fontSize);
  }

  private syncFmState(): void {
    this.hasFrontmatter = this.engine.hasFrontmatter;
    this.frontmatterRaw = this.engine.frontmatterRaw;
  }

  private dispatchCompletion(query: WysiwygCompletionQuery | null): void {
    if (query === null) {
      this.onCompletionQuery(null, 0, 0);
      return;
    }
    let px: number = 16;
    let py: number = 24;
    const rect: RectResult | undefined = this.engine.richController.getCaretRect();
    if (rect !== undefined) {
      const ui = this.getUIContext();
      px = Math.max(8, this.wrapOriginX + this.richOriginX + ui.px2vp(rect.x));
      py = Math.max(8, this.wrapOriginY + this.richOriginY + ui.px2vp(rect.y));
    }
    this.onCompletionQuery(query, px, py);
  }

  build() {
    Column() {
      Column({ space: 8 }) {
        WysiwygPropertiesCard({
          hasFrontmatter: this.hasFrontmatter,
          frontmatterRaw: this.frontmatterRaw,
          fontSize: this.fontSize,
          onChange: (hasFm: boolean, nextRaw: string): void => {
            this.hasFrontmatter = hasFm;
            this.frontmatterRaw = nextRaw;
            this.engine.setFrontmatter(hasFm, nextRaw);
          }
        })

        if (this.activeKind === WysiwygBlockKind.CODE) {
          this.codeBlockMetaBar()
        }

        RichEditor({ controller: this.engine.richController })
          .id(WysiwygEditor.EDITOR_ID)
          .width('100%')
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .placeholder($r('app.string.design_editor_body_hint'), {
            font: { size: this.fontSize },
            fontColor: $r('app.color.design_text_secondary')
          })
          .caretColor($r('app.color.design_accent'))
          .selectedBackgroundColor($r('app.color.design_accent_weak'))
          .copyOptions(CopyOptions.LocalDevice)
          .barState(BarState.Auto)
          .enableKeyboardOnFocus(true)
          .onAreaChange((_oldArea: Area, newArea: Area): void => {
            this.richOriginX = Number(newArea.position.x);
            this.richOriginY = Number(newArea.position.y);
            const widthVp: number = Number(newArea.width);
            if (widthVp > 40) {
              // 扣减 RichEditor 内边距与滚动条占位，确保表格右边框与编辑角标完整显示不裁切
              this.engine.setContentWidthVp(Math.max(220, widthVp - 36));
            }
          })
          .onReady((): void => {
            this.syncEnv();
            this.engine.onEditorReady();
            this.syncFmState();
          })
          .aboutToIMEInput((value: RichEditorInsertValue): boolean => {
            return this.engine.handleAboutToIMEInput(value);
          })
          .aboutToDelete((value: RichEditorDeleteValue): boolean => {
            return this.engine.handleAboutToDelete(value);
          })
          .onDidChange((rangeBefore: TextRange, rangeAfter: TextRange): void => {
            const q: WysiwygCompletionQuery | null = this.engine.handleDidChange(rangeBefore, rangeAfter);
            this.dispatchCompletion(q);
          })
          .onSelectionChange((range: RichEditorRange): void => {
            const q: WysiwygCompletionQuery | null = this.engine.handleSelectionChange(range);
            this.dispatchCompletion(q);
          })
          .onEditingChange((editing: boolean): void => {
            this.engine.setEditorFocused(editing);
            if (!editing) {
              this.onCompletionQuery(null, 0, 0);
            }
            this.onKeyboardModeChange(editing);
          })
          .onTouch((event: TouchEvent): void => {
            this.onTouchEditor(event);
          })
          .onClick((event: ClickEvent): void => {
            this.engine.handleTap(event);
          })
          .onKeyPreIme((event: KeyEvent): boolean => {
            if (event.keyCode === 2049) {
              if (event.type === KeyType.Down && this.engine.handleTabKey()) {
                this.dispatchCompletion(null);
              }
              return true;
            }
            return false;
          })
          .onKeyEvent((event: KeyEvent): void => {
            if (event.type === KeyType.Down && event.keyCode === 2055 &&
              this.engine.getCaretOffset() === 0) {
              // 兜底：硬件键盘在文档最首位置按退格解除首行样式。
              const txt: string = this.engine.getPlainText();
              const line0: [number, number] = WysiwygTriggers.lineRange(txt, 0);
              if (line0[0] === 0 && this.activeKind !== WysiwygBlockKind.PARAGRAPH) {
                this.engine.handleAboutToDelete({
                  offset: 0,
                  direction: RichEditorDeleteDirection.BACKWARD,
                  length: 0,
                  richEditorDeleteSpans: []
                });
              }
            }
          })
      }
      .width('100%')
      .constraintSize({ maxWidth: DesignTokens.READING_MAX_WIDTH })
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        this.wrapOriginX = Number(newArea.position.x);
        this.wrapOriginY = Number(newArea.position.y);
      })
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.design_bg'))
  }

  @Builder
  codeBlockMetaBar() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(13)
        .fontColor([$r('app.color.design_accent')])
      Text($r('app.string.editor_code_block_badge'))
        .fontSize(12)
        .fontColor($r('app.color.design_text_secondary'))
      if (this.editingCodeLang) {
        TextInput({ placeholder: 'ts / dataview / mermaid', text: this.codeLangInput })
          .width(140)
          .height(26)
          .fontSize(12)
          .padding({ left: 8, right: 8 })
          .borderRadius(8)
          .backgroundColor($r('app.color.design_surface_solid'))
          .fontColor($r('app.color.design_text_primary'))
          .caretColor($r('app.color.design_accent'))
          .onChange((v: string): void => {
            this.codeLangInput = v;
          })
          .onSubmit(() => {
            this.engine.setActiveCodeLang(this.codeLangInput);
            this.editingCodeLang = false;
          })
        Text($r('app.string.props_save'))
          .fontSize(12)
          .fontColor($r('app.color.design_accent'))
          .onClick(() => {
            this.engine.setActiveCodeLang(this.codeLangInput);
            this.editingCodeLang = false;
          })
      } else {
        Text(this.activeCodeLang.length > 0 ? this.activeCodeLang : 'text')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_accent'))
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(8)
          .backgroundColor($r('app.color.design_accent_weak'))
          .onClick(() => {
            this.codeLangInput = this.activeCodeLang;
            this.editingCodeLang = true;
          })
      }
      Blank()
      Text($r('app.string.editor_code_exit_hint'))
        .fontSize(11)
        .fontColor($r('app.color.design_text_secondary'))
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
    .borderRadius(10)
    .backgroundColor($r('app.color.design_elevated'))
  }
}
