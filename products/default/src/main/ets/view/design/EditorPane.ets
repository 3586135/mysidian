import { SymbolGlyphModifier } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DataViewResult, DataViewTask, SyncFileFilter } from '@ohos/domain';
import { EmptyState, Logger } from '@ohos/common';
import { VaultManager } from '@ohos/vault';
import { MdDocumentView, MdDocumentViewController, WysiwygCodec } from '@ohos/markdown';
import { CompletionCandidate, EditorTextUtils, ListContinuation } from '../../viewmodel/EditorTextUtils';
import { VaultViewModel } from '../../viewmodel/VaultViewModel';
import { CompletionPopup } from './CompletionPopup';
import { EditorToolbar } from './EditorToolbar';
import { FindReplaceBar } from './FindReplaceBar';
import { ThreeDotsIcon } from './NoteActionHelper';
import { FindReplaceUtils } from '../../viewmodel/FindReplaceUtils';
import { WysiwygCompletionQuery, WysiwygFormatState } from './WysiwygEditorEngine';
import { WysiwygEditor, WysiwygEditorBridge } from './WysiwygEditor';
import { WysiwygTableSheet } from './WysiwygTableSheet';

const LOG: Logger = new Logger('EditorPane');

/**
 * Material 3 编辑器面板：空态 / 编辑 / 预览三态。
 *
 * 编辑态：TextArea + 撤销重做（600ms 合并、上限 50）+ wiki/标签补全 +
 * 底部格式化工具栏 + 图片插入 + 光标定位（applyPendingCaret）。
 * 预览态：MdDocumentView 渲染，支持任务勾选 / 数据视图 / 嵌入引用。
 * 键盘避让策略、布局态（侧栏/信息面板）经 @Event 上抛 WorkspaceView。
 */
@ComponentV2
export struct EditorPane {
  @Param vm: VaultViewModel = new VaultViewModel();
  @Param isWide: boolean = false;
  @Param keyboardHeight: number = 0;
  @Param contentWidth: number = 0;
  @Param docController: MdDocumentViewController = new MdDocumentViewController();
  @Event onEditorKeyboardMode: (active: boolean) => void = (_active: boolean): void => {};
  @Event onRequestExit: () => void = (): void => {};
  @Event onToggleSidebar: () => void = (): void => {};
  @Event onToggleInfoPanel: () => void = (): void => {};
  @Event onDismissOverlays: () => void = (): void => {};
  @Event onContentSwipe: (offsetX: number) => void = (offsetX: number): void => {};
  @Event onOpenTag: (tag: string) => void = (tag: string): void => {};
  @Event onRequestRename: () => void = (): void => {};
  @Event onRequestMove: () => void = (): void => {};
  @Event onRequestTrash: () => void = (): void => {};
  @Event onRequestHistory: () => void = (): void => {};
  @Event onRequestSplit: () => void = (): void => {};
  @Event onNoteMutated: () => void = (): void => {};
  @Event onPreviewImage: (uri: string) => void = (_uri: string): void => {};
  /** 外部只读预览时请求导入当前仓库（editAfter 表示导入成功后立即进入编辑态）。 */
  @Event onRequestImportExternal: (editAfter: boolean) => void = (_editAfter: boolean): void => {};
  /** 外部只读预览时请求关闭预览。 */
  @Event onRequestCloseExternal: () => void = (): void => {};

  /** 编辑工具栏显示状态。 */
  @Local showToolbar: boolean = false;
  /** wiki 链接补全浮层。 */
  @Local showCompletion: boolean = false;
  @Local completionItems: CompletionCandidate[] = [];
  @Local completionX: number = 0;
  @Local completionY: number = 0;
  /** 撤销 / 重做栈深度（工具栏禁用态）。 */
  @Local undoDepth: number = 0;
  @Local redoDepth: number = 0;
  /** 页内查找 / 替换栏：显示开关、匹配起点集合、当前匹配序号。 */
  @Local showFind: boolean = false;
  @Local findMatches: number[] = [];
  @Local findIndex: number = -1;
  /** 阅读态当前是否有选中文本（有选区时屏蔽横向翻页手势，确保拖动手柄顺滑）。 */
  @Local readingSelecting: boolean = false;
  /** 编辑态是否使用纯源码模式（默认 false，即所见即所得富文本）。 */
  @Local sourceMode: boolean = false;
  /** 所见模式工具栏激活态。 */
  @Local fmtBold: boolean = false;
  @Local fmtItalic: boolean = false;
  @Local fmtStrike: boolean = false;
  @Local fmtHighlight: boolean = false;
  @Local fmtCode: boolean = false;
  @Local fmtHeading: number = 0;
  @Local fmtBlockKind: string = '';
  @Local showTableSheet: boolean = false;
  @Local editingTableId: number = 0;
  @Local editingTableRawMd: string = '';
  /** 所见 <-> 源码切换光标继承参数。 */
  @Local wysiwygInitialCaret: number = 0;
  @Local wysiwygFocusOnLoad: boolean = false;
  private pendingSourceCaret: number = -1;
  private lastSourceCaret: number = -1;
  private focusRestoreSourceCaret: number = -1;
  private editorStackHeight: number = 0;

  /** 所见即所得编辑器桥接控制器。 */
  private wysiwygBridge: WysiwygEditorBridge = new WysiwygEditorBridge();
  private wysiwygCompletion: WysiwygCompletionQuery | null = null;
  private wysiwygCompletionKind: 'wiki' | 'tag' = 'wiki';
  /** 编辑器控制器：用于源码模式工具栏在光标处插入语法。 */
  private textEditorController: TextAreaController = new TextAreaController();
  /** 程序化编辑的期望文本：用于识别控制器修改引起的 onChange 回调。 */
  private expectedText: string = '';
  /** 程序化写入进行中：屏蔽期间的 onChange（避免污染撤销栈）。 */
  private programmaticEdit: boolean = false;
  /** 撤销 / 重做栈。 */
  private undoStack: string[] = [];
  private redoStack: string[] = [];
  private lastUndoPushAt: number = 0;
  private swipeStartX: number = -1;
  /** 屏幕左右边缘系统返回手势保留区宽度（vp）。 */
  private static readonly EDGE_GESTURE_ZONE: number = 32;
  /** 编辑器 TextArea 的组件 id（查找定位时用于重新获取焦点）。 */
  private static readonly EDITOR_ID: string = 'editor_text_area';
  /** 当前查找关键词。 */
  private findKeyword: string = '';

  aboutToAppear(): void {
    // 注册 VM 注入钩子：光标处插入文本（手写图片等外部内容）。
    this.vm.onInsertTextAtCaret = (text: string, atEnd: boolean): void => {
      if (!this.vm.editMode) {
        return;
      }
      if (!this.sourceMode) {
        const imgMatch: RegExpExecArray | null = /^\s*!\[\[([^\[\]]+)\]\]\s*$/.exec(text);
        if (imgMatch !== null) {
          this.wysiwygBridge.insertImageTarget(imgMatch[1].trim());
          return;
        }
        const cur: string = this.wysiwygBridge.exportMarkdown();
        const combined: string = atEnd ? `${cur}\n${text}` : `${cur}${text}`;
        this.wysiwygBridge.loadMarkdown(combined);
        this.vm.updateDraft(combined);
        return;
      }
      if (atEnd) {
        // 预览态切编辑后插入：光标先落到文末再写。
        this.textEditorController.caretPosition(this.vm.draftBuffer.length);
      }
      this.insertFormat(text);
    };
  }

  aboutToDisappear(): void {
    this.vm.onInsertTextAtCaret = (text: string, atEnd: boolean): void => {};
  }

  /** 切换笔记 / 外部文档 / 进出编辑时清空与旧会话绑定的撤销栈与补全浮层。 */
  @Monitor('vm.selectedPath', 'vm.externalUri', 'vm.editMode')
  onNoteOrEditModeChanged(): void {
    this.undoStack = [];
    this.redoStack = [];
    this.lastUndoPushAt = 0;
    this.undoDepth = 0;
    this.redoDepth = 0;
    this.showCompletion = false;
    this.completionItems = [];
    this.wysiwygCompletion = null;
    this.readingSelecting = false;
    this.sourceMode = false;
    this.clearFormatState();
    this.wysiwygInitialCaret = 0;
    this.wysiwygFocusOnLoad = false;
    this.pendingSourceCaret = -1;
    this.lastSourceCaret = -1;
    this.focusRestoreSourceCaret = -1;
    this.showTableSheet = false;
    this.closeFind();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
      if (this.vm.selectedPath.length === 0 && !this.vm.isExternalMode) {
        EmptyState({
          title: $r('app.string.note_empty_title'),
          description: $r('app.string.note_empty_desc'),
          icon: $r('sys.symbol.doc_plaintext'),
          iconColor: $r('app.color.design_text_secondary'),
          titleColor: $r('app.color.design_text_primary'),
          descColor: $r('app.color.design_text_secondary')
        })
        .onTouch((event: TouchEvent) => {
          this.onContentTouch(event);
        })
        .transition(TransitionEffect.opacity(0)
          .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
          .animation({ duration: 240, curve: Curve.Friction }))
      } else {
        this.editorHeader()
        if (this.vm.isExternalMode) {
          this.externalPreviewBanner()
        }
        if (this.vm.editMode && this.showFind) {
          FindReplaceBar({
            matchCount: this.findMatches.length,
            currentIndex: this.findIndex,
            onQueryChange: (keyword: string): void => {
              this.findKeyword = keyword;
              this.refreshMatches();
              this.findIndex = -1;
            },
            onPrev: (): void => {
              this.stepMatch(-1);
            },
            onNext: (): void => {
              this.stepMatch(1);
            },
            onReplace: (replacement: string): void => {
              this.replaceCurrent(replacement);
            },
            onReplaceAll: (replacement: string): void => {
              this.replaceEveryMatch(replacement);
            },
            onClose: (): void => {
              this.closeFind();
            }
          })
        }
        if (this.vm.editMode) {
          Stack({ alignContent: Alignment.TopStart }) {
            if (this.sourceMode) {
              TextArea({
                placeholder: $r('app.string.editor_placeholder'),
                text: this.vm.draftBuffer,
                controller: this.textEditorController
              })
                .fontSize(16)
                .width('100%')
                .height('100%')
                .backgroundColor(Color.Transparent)
                .fontColor($r('app.color.design_text_primary'))
                .placeholderColor($r('app.color.design_text_secondary'))
                .caretColor($r('app.color.design_accent'))
                .id(EditorPane.EDITOR_ID)
                .padding({ left: 20, right: 20, top: 8, bottom: 8 })
                .gesture(this.contentPanGesture())
                .onTouch((event: TouchEvent) => {
                  this.onContentTouch(event);
                  // 触摸先于聚焦发生：提前切换避让策略，避免键盘弹出瞬间页面跳动。
                  this.onEditorKeyboardMode(true);
                })
                .onFocus(() => {
                  this.showToolbar = true;
                  this.onEditorKeyboardMode(true);
                  if (this.focusRestoreSourceCaret >= 0) {
                    const restorePos: number = this.focusRestoreSourceCaret;
                    this.focusRestoreSourceCaret = -1;
                    this.textEditorController.caretPosition(restorePos);
                    this.lastSourceCaret = restorePos;
                  }
                })
                .onBlur(() => {
                  if (!this.sourceMode || !this.vm.editMode) {
                    return;
                  }
                  this.showToolbar = false;
                  // 键盘已收起时退出键盘交互态，恢复默认避让策略。
                  if (this.keyboardHeight <= 0) {
                    this.onEditorKeyboardMode(false);
                  }
                })
                .onAppear(() => {
                  this.applyPendingCaret();
                })
                .onChange((value: string) => {
                  this.onEditorChange(value);
                })
                .onTextSelectionChange((start: number, _end: number) => {
                  if (this.focusRestoreSourceCaret < 0) {
                    this.lastSourceCaret = start;
                  }
                })
                .transition(TransitionEffect.opacity(0)
                  .animation({ duration: 200, curve: Curve.Friction }))
            } else {
              WysiwygEditor({
                initialMarkdown: this.vm.draftBuffer,
                docKey: this.vm.selectedPath.length > 0 ? this.vm.selectedPath : this.vm.externalUri,
                fontSize: this.vm.fontSize,
                initialCaret: this.wysiwygInitialCaret,
                focusAfterLoad: this.wysiwygFocusOnLoad,
                bridge: this.wysiwygBridge,
                onResolveAsset: (target: string): string => this.vm.resolveAsset(target),
                onMarkdownChange: (md: string): void => {
                  this.vm.updateDraft(md);
                  if (this.showFind) {
                    this.refreshMatches();
                  }
                },
                onKeyboardModeChange: (editing: boolean): void => {
                  if (this.sourceMode || !this.vm.editMode) {
                    return;
                  }
                  this.showToolbar = editing;
                  if (editing) {
                    this.onEditorKeyboardMode(true);
                  } else if (this.keyboardHeight <= 0) {
                    this.onEditorKeyboardMode(false);
                  }
                },
                onTouchEditor: (event: TouchEvent): void => {
                  this.onContentTouch(event);
                  this.onEditorKeyboardMode(true);
                },
                onCompletionQuery: (query: WysiwygCompletionQuery | null, popupX: number,
                  popupY: number): void => {
                  this.updateWysiwygCompletion(query, popupX, popupY);
                },
                onTriggerImagePick: (): void => {
                  this.pickAndInsertImage();
                },
                onHistoryChange: (u: number, r: number): void => {
                  this.undoDepth = u;
                  this.redoDepth = r;
                },
                onFormatStateChange: (state: WysiwygFormatState): void => {
                  this.applyFormatState(state);
                },
                onOpenTableEditor: (tableId: number, rawMd: string): void => {
                  this.editingTableId = tableId;
                  this.editingTableRawMd = rawMd;
                  this.showTableSheet = true;
                }
              })
                .width('100%')
                .height('100%')
                .gesture(this.contentPanGesture())
            }
            if (this.showCompletion && this.completionItems.length > 0) {
              CompletionPopup({
                items: this.completionItems,
                posX: this.completionX,
                posY: this.completionY,
                onApply: (item: CompletionCandidate): void => {
                  this.applyCompletion(item);
                }
              })
            }
          }
          .width('100%')
          .layoutWeight(1)
          .onAreaChange((_oldArea: Area, newArea: Area): void => {
            this.editorStackHeight = Number(newArea.height);
          })
          if (this.showToolbar && this.vm.editMode) {
            EditorToolbar({
              undoDepth: this.undoDepth,
              redoDepth: this.redoDepth,
              activeBold: !this.sourceMode && this.fmtBold,
              activeItalic: !this.sourceMode && this.fmtItalic,
              activeStrike: !this.sourceMode && this.fmtStrike,
              activeHighlight: !this.sourceMode && this.fmtHighlight,
              activeCode: !this.sourceMode && this.fmtCode,
              activeHeading: !this.sourceMode ? this.fmtHeading : 0,
              activeBlockKind: !this.sourceMode ? this.fmtBlockKind : '',
              onInsertFormat: (syntax: string): void => {
                this.insertFormat(syntax);
              },
              onUndo: (): void => {
                this.undoEdit();
              },
              onRedo: (): void => {
                this.redoEdit();
              },
              onPickImage: (): void => {
                this.pickAndInsertImage();
              },
              onPickAttachment: (): void => {
                this.pickAndInsertAttachment();
              }
            })
          }
        } else {
          MdDocumentView({
            document: this.vm.document,
            docKey: this.vm.selectedPath.length > 0 ? this.vm.selectedPath : this.vm.externalUri,
            fontSize: this.vm.fontSize,
            controller: this.docController,
            onOpenLink: (target: string, kind: string): void => {
              this.vm.openLink(target, kind);
            },
            onOpenTag: (tag: string): void => {
              this.onOpenTag(tag);
            },
            onToggleTask: (rawLine: string, lineNumber: number, checked: boolean): void => {
              this.vm.toggleTask(rawLine, lineNumber, checked).then((): void => {
                this.onNoteMutated();
              });
            },
            onLoadDataView: (query: string,
              onResult: (result: DataViewResult) => void): void => {
              this.vm.runDataViewQuery(query).then((result: DataViewResult): void => {
                onResult(result);
              });
            },
            onToggleDataViewTask: (task: DataViewTask, checked: boolean): void => {
              this.vm.toggleTaskInNote(task, checked).then((): void => {
                this.onNoteMutated();
              });
            },
            onLoadEmbed: (target: string, onResult: (text: string) => void): void => {
              this.vm.loadEmbed(target).then((text: string): void => {
                onResult(text);
              });
            },
            onResolveAsset: (target: string, onResult: (uri: string) => void): void => {
              onResult(this.vm.resolveAsset(target));
            },
            onPreviewImage: (uri: string): void => {
              this.onPreviewImage(uri);
            },
            onOpenAttachment: (target: string): void => {
              this.vm.openAttachmentByTarget(target);
            },
            onSelectionChange: (active: boolean): void => {
              this.readingSelecting = active;
            }
          })
          .layoutWeight(1)
          .padding({ left: 20, right: 20 })
          .gesture(this.contentPanGesture())
          .onGestureJudgeBegin((gestureInfo: GestureInfo, _event: BaseGestureEvent): GestureJudgeResult => {
            if (gestureInfo.tag === 'reading_pan' && this.readingSelecting) {
              return GestureJudgeResult.REJECT;
            }
            return GestureJudgeResult.CONTINUE;
          })
          .onTouch((event: TouchEvent) => {
            this.onContentTouch(event);
          })
          .transition(TransitionEffect.opacity(0)
            .animation({ duration: 200, curve: Curve.Friction }))
        }
      }
    }
    .width('100%')
    .height('100%')

      if (this.showTableSheet && this.vm.editMode && !this.sourceMode) {
        WysiwygTableSheet({
          tableId: this.editingTableId,
          rawMd: this.editingTableRawMd,
          onCancel: (): void => {
            this.showTableSheet = false;
          },
          onConfirm: (tableId: number, nextRawMd: string): void => {
            this.showTableSheet = false;
            this.wysiwygBridge.applyTableEdit(tableId, nextRawMd);
          },
          onDelete: (tableId: number): void => {
            this.showTableSheet = false;
            this.wysiwygBridge.applyTableEdit(tableId, '');
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 标题栏 ====================

  /** 编辑器标题栏：返回 / 笔记标题 + 编辑操作。 */
  @Builder
  editorHeader() {
    Row() {
      if (!this.isWide) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontColor([$r('app.color.design_text_primary')])
          .width(36)
          .height(36)
          .margin({ left: -8 })
          .accessibilityText($r('app.string.action_back'))
          .onClick(() => {
            this.onRequestExit();
          })
        if (this.vm.vaults.length > 0) {
          SymbolGlyph($r('sys.symbol.rectangle_lefthalf_inset_filled'))
            .fontSize(20)
            .fontColor([$r('app.color.design_text_secondary')])
            .width(36)
            .height(36)
            .accessibilityText($r('app.string.design_tab_files'))
            .onClick(() => {
              this.onToggleSidebar();
            })
        }
      }
      Text(this.vm.noteTitle)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.design_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .onClick(() => {
          // 点击标题即可重命名当前笔记。
          if (!this.vm.editMode && this.vm.selectedPath.length > 0) {
            this.onRequestRename();
          }
        })
      if (this.vm.editMode) {
        Text(this.sourceMode ? $r('app.string.editor_mode_source') : $r('app.string.editor_mode_wysiwyg'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.sourceMode ? $r('app.color.design_text_primary') : $r('app.color.design_accent'))
          .height(26)
          .padding({ left: 8, right: 8 })
          .borderRadius(13)
          .backgroundColor(this.sourceMode
            ? $r('app.color.design_elevated') : $r('app.color.design_accent_weak'))
          .margin({ right: 4 })
          .focusable(false)
          .accessibilityText($r('app.string.editor_mode_toggle_a11y'))
          .onClick(() => {
            this.toggleEditModeStyle();
          })
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(20)
          .fontColor([$r('app.color.design_text_primary')])
          .width(36)
          .height(36)
          .accessibilityText($r('app.string.find_open'))
          .keyboardShortcut('f', [ModifierKey.CTRL])
          .onClick(() => {
            if (this.showFind) {
              this.closeFind();
            } else {
              this.showFind = true;
            }
          })
        Text($r('app.string.action_cancel'))
          .fontSize(15)
          .fontColor($r('app.color.design_text_secondary'))
          .height(36)
          .padding({ left: 8, right: 8 })
          .margin({ left: 4 })
          .onClick(() => {
            this.sourceMode = false;
            this.wysiwygInitialCaret = 0;
            this.wysiwygFocusOnLoad = false;
            this.pendingSourceCaret = -1;
            this.lastSourceCaret = -1;
            this.focusRestoreSourceCaret = -1;
            this.clearFormatState();
            this.onEditorKeyboardMode(false);
            this.vm.cancelEdit();
          })
        Text($r('app.string.action_save'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_accent'))
          .height(36)
          .padding({ left: 8, right: 8 })
          .margin({ left: 4 })
          .keyboardShortcut('s', [ModifierKey.CTRL])
          .onClick(() => {
            if (!this.sourceMode) {
              this.vm.updateDraft(this.wysiwygBridge.exportMarkdown());
            }
            this.sourceMode = false;
            this.wysiwygInitialCaret = 0;
            this.wysiwygFocusOnLoad = false;
            this.pendingSourceCaret = -1;
            this.lastSourceCaret = -1;
            this.focusRestoreSourceCaret = -1;
            this.clearFormatState();
            this.onEditorKeyboardMode(false);
            this.vm.saveDraft().then((): void => {
              this.onNoteMutated();
            });
          })
      } else {
        if (this.vm.selectedPath.length > 0) {
          SymbolGlyph(this.vm.isBookmarked(this.vm.selectedPath) ?
            $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
            .fontSize(20)
            .fontColor([this.vm.isBookmarked(this.vm.selectedPath) ?
              $r('app.color.design_accent') : $r('app.color.design_text_primary')])
            .width(36)
            .height(36)
            .margin({ left: 4 })
            .accessibilityText(this.vm.isBookmarked(this.vm.selectedPath) ?
              $r('app.string.bookmark_remove') : $r('app.string.bookmark_add'))
            .onClick(() => {
              this.vm.toggleBookmark(this.vm.selectedPath).then((added: boolean): void => {
                this.getUIContext().getPromptAction().showToast({
                  message: added ? $r('app.string.msg_bookmark_added') : $r('app.string.msg_bookmark_removed')
                });
              });
            })
        }
        if (this.isWide) {
          SymbolGlyph($r('sys.symbol.rectangle_grid_1x2'))
            .fontSize(20)
            .fontColor([$r('app.color.design_text_primary')])
            .width(36)
            .height(36)
            .margin({ left: 4 })
            .accessibilityText($r('app.string.action_info'))
            .onClick(() => {
              this.onToggleInfoPanel();
            })
        } else {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(20)
            .fontColor([$r('app.color.design_text_primary')])
            .width(36)
            .height(36)
            .margin({ left: 4 })
            .accessibilityText($r('app.string.action_info'))
            .onClick(() => {
              this.onToggleInfoPanel();
            })
        }
        if (this.vm.selectedPath.length > 0) {
          Stack() {
            ThreeDotsIcon(3.5, 3, $r('app.color.design_text_primary'), 0.9)
          }
          .width(36)
          .height(36)
          .margin({ left: 2 })
          .accessibilityText($r('app.string.note_more_actions'))
          .bindMenu(this.noteActionsMenuBuilder)
        }
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  /** 外部 Markdown 只读预览提示条：明确提示未写入同步仓库，支持一键导入或关闭。 */
  @Builder
  externalPreviewBanner() {
    Column() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(16)
          .fontColor([$r('app.color.design_accent')])
        Column({ space: 2 }) {
          Text(this.vm.externalFileName)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text($r('app.string.external_preview_badge'))
            .fontSize(11)
            .fontColor($r('app.color.design_accent'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button(this.vm.vaults.length > 0 ?
          $r('app.string.external_import_to_vault') :
          $r('app.string.external_import_create_vault'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .height(30)
          .padding({ left: 12, right: 12 })
          .backgroundColor($r('app.color.design_accent'))
          .fontColor($r('app.color.design_on_accent'))
          .borderRadius(15)
          .onClick(() => {
            this.onRequestImportExternal(false);
          })

        Button($r('app.string.external_close_preview'))
          .fontSize(12)
          .height(30)
          .padding({ left: 10, right: 10 })
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.design_text_secondary'))
          .borderRadius(15)
          .border({ width: 1, color: $r('app.color.design_stroke') })
          .onClick(() => {
            this.onRequestCloseExternal();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 10, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.design_accent_weak'))
      .borderRadius(14)
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 6 })
  }

  /** 当前打开笔记的右上角操作菜单（重命名 / 移动 / 历史 / 分屏 / 移入回收站）。 */
  @Builder
  noteActionsMenuBuilder() {
    Menu() {
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.doc_plaintext_and_pencil')),
        content: $r('app.string.action_rename')
      })
        .onClick(() => {
          this.onRequestRename();
        })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.folder')),
        content: $r('app.string.action_move')
      })
        .onClick(() => {
          this.onRequestMove();
        })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.clock')),
        content: $r('app.string.action_history')
      })
        .onClick(() => {
          this.onRequestHistory();
        })
      if (this.isWide) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.rectangle_grid_1x2')),
          content: $r('app.string.action_split')
        })
          .onClick(() => {
            this.onRequestSplit();
          })
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')).fontColor([$r('app.color.design_danger')]),
        content: $r('app.string.action_trash')
      })
        .contentFontColor($r('app.color.design_danger'))
        .onClick(() => {
          this.onRequestTrash();
        })
    }
  }

  // ==================== 手势与浮层收起 ====================

  /**
   * 正文区横向滑动手势（向右呼出文件侧栏 / 向左查看双链）。
   *
   * 只挂在正文（编辑区与预览区）上，不挂整个编辑器容器，
   * 避免与编辑工具栏的横向滚动互相抢手势。
   */
  private contentPanGesture(): GestureType {
    return PanGesture({ fingers: 1, direction: PanDirection.Horizontal })
      .tag('reading_pan')
      .onActionStart((event: GestureEvent) => {
        this.swipeStartX = event.fingerList.length > 0 ? event.fingerList[0].globalX : -1;
      })
      .onActionEnd((event: GestureEvent) => {
        if (this.readingSelecting || this.isEdgeSwipe()) {
          return;
        }
        this.handleContentSwipe(event.offsetX);
      });
  }

  /** 起点位于屏幕左右边缘保留区内的滑动交给系统返回手势处理。 */
  private isEdgeSwipe(): boolean {
    if (this.swipeStartX < 0 || !(this.contentWidth > 0)) {
      return false;
    }
    return this.swipeStartX < EditorPane.EDGE_GESTURE_ZONE ||
      this.swipeStartX > this.contentWidth - EditorPane.EDGE_GESTURE_ZONE;
  }

  /** 正文触摸：按下即收起窄屏弹层（信息面板 / 文件侧栏）。 */
  private onContentTouch(event: TouchEvent): void {
    if (event.type !== TouchType.Down) {
      return;
    }
    this.onDismissOverlays();
  }

  /** 正文区横向滑动语义（呼出侧栏 / 查看双链）由 WorkspaceView 依据布局态判定。 */
  private handleContentSwipe(offsetX: number): void {
    this.onContentSwipe(offsetX);
  }

  // ==================== 编辑逻辑 ====================

  /** 同步工具栏格式化激活态。 */
  private applyFormatState(state: WysiwygFormatState): void {
    this.fmtBold = state.bold;
    this.fmtItalic = state.italic;
    this.fmtStrike = state.strike;
    this.fmtHighlight = state.highlight;
    this.fmtCode = state.code;
    this.fmtHeading = state.headingLevel;
    this.fmtBlockKind = state.blockKind;
  }

  /** 清空工具栏格式化激活态。 */
  private clearFormatState(): void {
    this.fmtBold = false;
    this.fmtItalic = false;
    this.fmtStrike = false;
    this.fmtHighlight = false;
    this.fmtCode = false;
    this.fmtHeading = 0;
    this.fmtBlockKind = '';
  }

  /** 在所见即所得与纯 Markdown 源码视图间无损切换，并保持光标同步。 */
  private toggleEditModeStyle(): void {
    this.showCompletion = false;
    this.completionItems = [];
    this.wysiwygCompletion = null;
    this.closeFind();
    if (!this.sourceMode) {
      const keepToolbar: boolean = this.showToolbar || this.keyboardHeight > 0;
      this.pendingSourceCaret = this.wysiwygBridge.getSourceCaretOffset();
      this.vm.updateDraft(this.wysiwygBridge.exportMarkdown());
      this.clearFormatState();
      this.lastSourceCaret = -1;
      this.sourceMode = true;
      this.showToolbar = keepToolbar;
      this.undoDepth = this.undoStack.length;
      this.redoDepth = this.redoStack.length;
    } else {
      const keepToolbar: boolean = this.showToolbar || this.keyboardHeight > 0;
      const ctrlCaret: number = Math.max(0, this.textEditorController.getCaretOffset().index);
      const srcCaret: number = ctrlCaret > 0 ? ctrlCaret : Math.max(0, this.lastSourceCaret);
      this.wysiwygInitialCaret = WysiwygCodec.wysiwygOffsetFromSource(this.vm.draftBuffer, srcCaret);
      this.wysiwygFocusOnLoad = true;
      this.sourceMode = false;
      this.showToolbar = keepToolbar;
      this.undoDepth = this.wysiwygBridge.getUndoDepth();
      this.redoDepth = this.wysiwygBridge.getRedoDepth();
    }
  }

  /** 在光标处插入 Markdown 语法（所见模式直接应用富文本格式）。 */
  private insertFormat(syntax: string): void {
    if (!this.sourceMode) {
      this.wysiwygBridge.applyToolbarAction(syntax);
      return;
    }
    const snippet: string = syntax === 'table'
      ? '| 列1 | 列2 |\n| --- | --- |\n|  |  |\n'
      : syntax;
    const caret: number = this.textEditorController.getCaretOffset().index;
    this.textEditorController.addText(snippet, { offset: caret });
    // addText 未触发 onChange 时的兜底：手动同步缓冲区。
    const text: string = this.vm.draftBuffer;
    const before: string = text.slice(0, caret);
    const after: string = text.slice(caret);
    this.vm.updateDraft(before + snippet + after);
  }

  /** 编辑器内容变化：处理列表续行、撤销栈与 wiki 补全。 */
  private onEditorChange(value: string): void {
    if (this.programmaticEdit) {
      // 程序化写入过程中的回调：只同步缓冲区，不参与续行与撤销。
      this.vm.updateDraft(value);
      return;
    }
    if (this.expectedText.length > 0 && value === this.expectedText) {
      // 控制器程序化修改引起的回调：只同步缓冲区，不参与续行与撤销。
      this.expectedText = '';
      this.vm.updateDraft(value);
      return;
    }
    this.expectedText = '';
    const prev: string = this.vm.draftBuffer;
    if (value === prev) {
      // 刚切入源码模式首次挂载回调，内容无变化，不弹出补全浮层。
      return;
    }
    const caret: number = this.textEditorController.getCaretOffset().index;
    const continuation: ListContinuation | null =
      EditorTextUtils.computeListContinuation(prev, value, caret - 1);
    if (continuation !== null) {
      const next: string = value.substring(0, continuation.deleteFrom) + continuation.insertText +
        value.substring(continuation.deleteTo);
      this.replaceEditorText(next, continuation.deleteFrom + continuation.insertText.length);
      this.recordUndo(prev);
      this.updateCompletion(value, caret);
      return;
    }
    this.recordUndo(prev);
    this.vm.updateDraft(value);
    this.updateCompletion(value, caret);
  }

  /** 用控制器整体替换编辑器内容，并同步草稿缓冲区。 */
  private replaceEditorText(text: string, caret: number): void {
    const current: string = this.vm.draftBuffer;
    this.expectedText = text;
    // 程序化写入期间屏蔽 onChange：delete + add 会产生中间空串回调，
    // 若不屏蔽会被当成用户输入压入撤销栈（首次撤销即清空正文）。
    this.programmaticEdit = true;
    if (current.length > 0) {
      this.textEditorController.deleteText({ start: 0, end: current.length });
    }
    if (text.length > 0) {
      this.textEditorController.addText(text, { offset: 0 });
    }
    this.textEditorController.setTextSelection(caret, caret);
    this.vm.updateDraft(text);
    this.programmaticEdit = false;
  }

  /** 记录撤销快照：600ms 内的连续输入合并为一次快照。 */
  private recordUndo(prevText: string): void {
    const now: number = Date.now();
    if (now - this.lastUndoPushAt < 600) {
      return;
    }
    this.lastUndoPushAt = now;
    this.undoStack.push(prevText);
    if (this.undoStack.length > 50) {
      this.undoStack.shift();
    }
    this.undoDepth = this.undoStack.length;
    this.redoStack = [];
    this.redoDepth = 0;
  }

  /** 撤销一步。 */
  private undoEdit(): void {
    if (!this.sourceMode) {
      this.wysiwygBridge.undo();
      return;
    }
    const popped: string | undefined = this.undoStack.pop();
    if (popped === undefined) {
      return;
    }
    this.redoStack.push(this.vm.draftBuffer);
    this.undoDepth = this.undoStack.length;
    this.redoDepth = this.redoStack.length;
    this.replaceEditorText(popped, popped.length);
  }

  /** 重做一步。 */
  private redoEdit(): void {
    if (!this.sourceMode) {
      this.wysiwygBridge.redo();
      return;
    }
    const popped: string | undefined = this.redoStack.pop();
    if (popped === undefined) {
      return;
    }
    this.undoStack.push(this.vm.draftBuffer);
    this.undoDepth = this.undoStack.length;
    this.redoDepth = this.redoStack.length;
    this.replaceEditorText(popped, popped.length);
  }

  // ==================== 页内查找 / 替换 ====================

  /** 按当前草稿重新计算匹配集合（当前匹配序号越界时回退为未定位）。 */
  private refreshMatches(): void {
    const haystack: string = this.sourceMode ? this.vm.draftBuffer : this.wysiwygBridge.getPlainText();
    this.findMatches = FindReplaceUtils.findAll(haystack, this.findKeyword);
    if (this.findIndex >= this.findMatches.length) {
      this.findIndex = -1;
    }
  }

  /** 关闭查找栏并清空状态。 */
  private closeFind(): void {
    this.showFind = false;
    this.findKeyword = '';
    this.findMatches = [];
    this.findIndex = -1;
  }

  /** 跳到上一个 / 下一个匹配（环形）。 */
  private stepMatch(step: number): void {
    this.refreshMatches();
    const next: number = FindReplaceUtils.cycle(this.findIndex, this.findMatches.length, step);
    this.selectMatch(next);
  }

  /** 选中第 index 个匹配：先让编辑器重新获得焦点，再设置选区并滚动到可见处。 */
  private selectMatch(index: number): void {
    this.findIndex = index;
    if (index < 0 || index >= this.findMatches.length) {
      return;
    }
    const start: number = this.findMatches[index];
    const end: number = start + this.findKeyword.length;
    if (!this.sourceMode) {
      this.wysiwygBridge.requestFocus();
      setTimeout((): void => {
        this.wysiwygBridge.selectRange(start, end);
      }, 60);
      return;
    }
    this.getUIContext().getFocusController().requestFocus(EditorPane.EDITOR_ID);
    setTimeout((): void => {
      this.textEditorController.setTextSelection(start, end, { menuPolicy: MenuPolicy.HIDE });
    }, 60);
  }

  /** 替换当前匹配（尚未定位时先定位到第一个）。 */
  private replaceCurrent(replacement: string): void {
    this.refreshMatches();
    if (this.findMatches.length === 0) {
      return;
    }
    if (this.findIndex < 0) {
      this.selectMatch(0);
      return;
    }
    const start: number = this.findMatches[this.findIndex];
    if (!this.sourceMode) {
      this.wysiwygBridge.replaceRange(start, start + this.findKeyword.length, replacement);
      this.refreshMatches();
      const caretAfter: number = start + replacement.length;
      let target: number = this.findMatches.findIndex((position: number): boolean => position >= caretAfter);
      if (target < 0 && this.findMatches.length > 0) {
        target = 0;
      }
      this.selectMatch(target);
      return;
    }
    const prev: string = this.vm.draftBuffer;
    const next: string = FindReplaceUtils.replaceAt(prev, start, this.findKeyword.length, replacement);
    // 替换是离散操作：强制压入撤销快照，不与前一次输入合并。
    this.lastUndoPushAt = 0;
    this.recordUndo(prev);
    const caret: number = start + replacement.length;
    this.replaceEditorText(next, caret);
    this.refreshMatches();
    // 定位到替换点之后的下一个匹配；没有则回到第一个。
    let target: number = this.findMatches.findIndex((position: number): boolean => position >= caret);
    if (target < 0 && this.findMatches.length > 0) {
      target = 0;
    }
    this.selectMatch(target);
  }

  /** 全部替换，并提示替换数量。 */
  private replaceEveryMatch(replacement: string): void {
    this.refreshMatches();
    const count: number = this.findMatches.length;
    if (count === 0) {
      return;
    }
    if (!this.sourceMode) {
      this.wysiwygBridge.replaceAllKeyword(this.findKeyword, replacement);
      this.refreshMatches();
      this.findIndex = -1;
      this.toast($r('app.string.msg_replace_done', count));
      return;
    }
    const prev: string = this.vm.draftBuffer;
    const next: string = FindReplaceUtils.replaceAll(prev, this.findKeyword, replacement);
    this.lastUndoPushAt = 0;
    this.recordUndo(prev);
    this.replaceEditorText(next, Math.min(next.length, this.findMatches[0] + replacement.length));
    this.refreshMatches();
    this.findIndex = -1;
    this.toast($r('app.string.msg_replace_done', count));
  }

  /** 所见模式更新 wiki / 标签补全浮层。 */
  private updateWysiwygCompletion(query: WysiwygCompletionQuery | null, popupX: number,
    popupY: number): void {
    if (query === null) {
      if (this.showCompletion || this.completionItems.length > 0 || this.wysiwygCompletion !== null) {
        this.showCompletion = false;
        this.completionItems = [];
        this.wysiwygCompletion = null;
      }
      return;
    }
    let kind: 'wiki' | 'tag' = 'wiki';
    let candidates: CompletionCandidate[] = EditorTextUtils.getWikiCompletionCandidates(
      query.paraTextUpToCaret, query.caretInPara, this.vm.noteTitles());
    if (candidates.length === 0) {
      candidates = EditorTextUtils.getTagCompletionCandidates(
        query.paraTextUpToCaret, query.caretInPara, this.vm.allTagNames);
      kind = 'tag';
    }
    if (candidates.length === 0) {
      if (this.showCompletion || this.completionItems.length > 0 || this.wysiwygCompletion !== null) {
        this.showCompletion = false;
        this.completionItems = [];
        this.wysiwygCompletion = null;
      }
      return;
    }
    this.wysiwygCompletion = query;
    this.wysiwygCompletionKind = kind;
    this.completionItems = candidates;
    const maxW: number = this.contentWidth > 240 ? this.contentWidth - 220 : 120;
    this.completionX = Math.max(8, Math.min(maxW, popupX));
    const popupEstH: number = Math.min(candidates.length, 8) * 32 + 12;
    let clampedY: number = Math.max(8, popupY);
    if (this.editorStackHeight > 0 && clampedY + 20 + popupEstH > this.editorStackHeight) {
      clampedY = Math.max(0, popupY - popupEstH - 22);
    }
    this.completionY = clampedY;
    this.showCompletion = true;
  }

  /** 更新 wiki 链接 / 标签补全浮层。 */
  private updateCompletion(text: string, caret: number): void {
    if (caret < 0 || !this.showToolbar) {
      this.showCompletion = false;
      return;
    }
    let candidates: CompletionCandidate[] =
      EditorTextUtils.getWikiCompletionCandidates(text, caret, this.vm.noteTitles());
    if (candidates.length === 0) {
      candidates = EditorTextUtils.getTagCompletionCandidates(text, caret, this.vm.allTagNames);
    }
    if (candidates.length === 0) {
      this.showCompletion = false;
      this.completionItems = [];
      return;
    }
    const offset: CaretOffset = this.textEditorController.getCaretOffset();
    this.completionItems = candidates;
    this.completionX = this.getUIContext().px2vp(offset.x);
    this.completionY = this.getUIContext().px2vp(offset.y);
    this.showCompletion = true;
  }

  /** 选中补全候选：在光标处补全标题并闭合链接。 */
  private applyCompletion(item: CompletionCandidate): void {
    if (!this.sourceMode) {
      const q: WysiwygCompletionQuery | null = this.wysiwygCompletion;
      if (q !== null) {
        const fromGlobal: number = item.replaceFrom >= 0 ? q.paraStart + item.replaceFrom : q.globalCaret;
        this.wysiwygBridge.applyCompletionCandidate(
          fromGlobal, q.globalCaret, item.title, item.insertText, this.wysiwygCompletionKind);
      }
      this.showCompletion = false;
      this.wysiwygCompletion = null;
      return;
    }
    const caret: number = this.textEditorController.getCaretOffset().index;
    if (caret < 0) {
      return;
    }
    const text: string = this.vm.draftBuffer;
    // replaceFrom >= 0 时替换已输入的查询串（支持前缀 / 包含命中与标签补全）。
    const from: number = item.replaceFrom >= 0 && item.replaceFrom < caret ? item.replaceFrom : caret;
    const next: string = text.substring(0, from) + item.insertText + text.substring(caret);
    this.replaceEditorText(next, from + item.insertText.length);
    this.showCompletion = false;
  }

  /** 应用待恢复光标位置：优先处理所见->源码切换继承，其次处理模板 {{cursor}}。 */
  private applyPendingCaret(): void {
    const srcCaret: number = this.pendingSourceCaret;
    if (srcCaret >= 0) {
      this.pendingSourceCaret = -1;
      const limit: number = this.vm.draftBuffer.length;
      const position: number = Math.max(0, Math.min(limit, srcCaret));
      this.focusRestoreSourceCaret = position;
      this.lastSourceCaret = position;
      setTimeout((): void => {
        this.getUIContext().getFocusController().requestFocus(EditorPane.EDITOR_ID);
        this.textEditorController.caretPosition(position);
        this.lastSourceCaret = position;
      }, 60);
      return;
    }
    const caret: number = this.vm.pendingCaret;
    if (caret < 0) {
      return;
    }
    this.vm.pendingCaret = -1;
    const limit: number = this.vm.draftBuffer.length;
    const position: number = caret > limit ? limit : caret;
    setTimeout((): void => {
      this.textEditorController.caretPosition(position);
    }, 80);
  }

  /** 选择图片并插入到当前光标处。 */
  private async pickAndInsertImage(): Promise<void> {
    try {
      const pickerInstance = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await pickerInstance.select(options);
      if (result.photoUris.length === 0) {
        return;
      }
      const uri: string = result.photoUris[0];
      const extension: string = this.extensionOfUri(uri);
      const relative: string = await this.vm.importAttachment(uri, extension);
      if (relative.length === 0) {
        this.toast($r('app.string.msg_image_failed'));
        return;
      }
      const name: string = relative.substring(relative.lastIndexOf('/') + 1);
      if (!this.sourceMode) {
        this.wysiwygBridge.insertImageTarget(name);
      } else {
        this.insertFormat(`![[${name}]]`);
      }
      this.toast($r('app.string.msg_image_done'));
    } catch (error) {
      const err = error as BusinessError;
      LOG.error(`pick image failed, code=${err.code}, message=${err.message}`);
    }
  }

  /** 选择文档/音视频等附件并导入当前仓库附件目录，在光标处插入链接。 */
  private async pickAndInsertAttachment(): Promise<void> {
    try {
      const hostContext = this.getUIContext().getHostContext();
      const documentPicker = hostContext !== undefined ?
        new picker.DocumentViewPicker(hostContext) : new picker.DocumentViewPicker();
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        return;
      }
      const uri: string = uris[0];
      const origName: string = VaultManager.extractUriFileName(uri);
      const extension: string = this.extensionOfUri(origName.length > 0 ? origName : uri, '');
      const relative: string = await this.vm.importAttachment(uri, extension, origName);
      if (relative.length === 0) {
        this.toast($r('app.string.msg_attachment_failed'));
        return;
      }
      const name: string = relative.substring(relative.lastIndexOf('/') + 1);
      const isImageFile: boolean = SyncFileFilter.isImage(name);
      if (!this.sourceMode) {
        if (isImageFile) {
          this.wysiwygBridge.insertImageTarget(name);
        } else {
          this.wysiwygBridge.insertWikiLinkTarget(name);
        }
      } else {
        this.insertFormat(isImageFile ? `![[${name}]]` : `[[${name}]]`);
      }
      this.toast($r('app.string.msg_attachment_done'));
    } catch (error) {
      const err = error as BusinessError;
      LOG.error(`pick attachment failed, code=${err.code}, message=${err.message}`);
    }
  }

  /** 从 URI 中提取扩展名（不含点）。 */
  private extensionOfUri(uri: string, fallback: string = 'png'): string {
    const clean: string = uri.split('?')[0];
    const index: number = clean.lastIndexOf('.');
    if (index < 0) {
      return fallback;
    }
    const ext: string = clean.substring(index + 1).toLowerCase();
    return ext.length > 0 ? ext : fallback;
  }

  /** 轻提示（使用 UIContext 的 PromptAction，避免全局 promptAction 的弃用告警）。 */
  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }
}
