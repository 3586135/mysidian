import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DataViewResult, DataViewTask } from '@ohos/domain';
import { EmptyState, Logger } from '@ohos/common';
import { MdDocumentView, MdDocumentViewController, MdInlineFlattener } from '@ohos/markdown';
import { CompletionCandidate, EditorTextUtils, ListContinuation } from '../../viewmodel/EditorTextUtils';
import { VaultViewModel } from '../../viewmodel/VaultViewModel';
import { CompletionPopup } from './CompletionPopup';
import { EditorToolbar } from './EditorToolbar';

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
  @Event onNoteMutated: () => void = (): void => {};

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

  /** 编辑器控制器：用于工具栏在光标处插入语法。 */
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

  /** 切换笔记 / 进出编辑时清空与旧会话绑定的撤销栈与补全浮层。 */
  @Monitor('vm.selectedPath', 'vm.editMode')
  onNoteOrEditModeChanged(): void {
    this.undoStack = [];
    this.redoStack = [];
    this.lastUndoPushAt = 0;
    this.undoDepth = 0;
    this.redoDepth = 0;
    this.showCompletion = false;
    this.completionItems = [];
  }

  build() {
    Column() {
      if (this.vm.selectedPath.length === 0) {
        EmptyState({
          title: $r('app.string.note_empty_title'),
          description: $r('app.string.note_empty_desc'),
          icon: $r('sys.symbol.doc_plaintext'),
          iconColor: $r('app.color.design_text_secondary')
        })
        .onTouch((event: TouchEvent) => {
          this.onContentTouch(event);
        })
        .transition(TransitionEffect.opacity(0)
          .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
          .animation({ duration: 240, curve: Curve.Friction }))
      } else {
        this.editorHeader()
        if (this.vm.editMode) {
          Stack({ alignContent: Alignment.TopStart }) {
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
              })
              .onBlur(() => {
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
              .transition(TransitionEffect.opacity(0)
                .animation({ duration: 200, curve: Curve.Friction }))
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
          if (this.showToolbar && this.vm.editMode) {
            EditorToolbar({
              undoDepth: this.undoDepth,
              redoDepth: this.redoDepth,
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
              }
            })
          }
        } else {
          MdDocumentView({
            document: this.vm.document,
            docKey: this.vm.selectedPath,
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
            }
          })
          .layoutWeight(1)
          .padding({ left: 20, right: 20 })
          .gesture(this.contentPanGesture())
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
          .onClick(() => {
            this.onRequestExit();
          })
        SymbolGlyph($r('sys.symbol.rectangle_lefthalf_inset_filled'))
          .fontSize(20)
          .fontColor([$r('app.color.design_text_secondary')])
          .width(36)
          .height(36)
          .onClick(() => {
            this.onToggleSidebar();
          })
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
        Text($r('app.string.action_cancel'))
          .fontSize(15)
          .fontColor($r('app.color.design_text_secondary'))
          .height(36)
          .padding({ left: 8, right: 8 })
          .margin({ left: 4 })
          .onClick(() => {
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
          .onClick(() => {
            this.onEditorKeyboardMode(false);
            this.vm.saveDraft().then((): void => {
              this.onNoteMutated();
            });
          })
      } else {
        SymbolGlyph($r('sys.symbol.doc_plaintext_and_pencil'))
          .fontSize(20)
          .fontColor([$r('app.color.design_text_primary')])
          .width(36)
          .height(36)
          .margin({ left: 4 })
          .onClick(() => {
            this.vm.startEdit();
          })
        if (this.isWide) {
          SymbolGlyph($r('sys.symbol.rectangle_grid_1x2'))
            .fontSize(20)
            .fontColor([$r('app.color.design_text_primary')])
            .width(36)
            .height(36)
            .margin({ left: 4 })
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
            .onClick(() => {
              this.onToggleInfoPanel();
            })
        }
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 8 })
    .alignItems(VerticalAlign.Center)
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
      .onActionStart((event: GestureEvent) => {
        this.swipeStartX = event.fingerList.length > 0 ? event.fingerList[0].globalX : -1;
      })
      .onActionEnd((event: GestureEvent) => {
        if (this.isEdgeSwipe()) {
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

  /** 在光标处插入 Markdown 语法。 */
  private insertFormat(syntax: string): void {
    const caret: number = this.textEditorController.getCaretOffset().index;
    this.textEditorController.addText(syntax, { offset: caret });
    // addText 未触发 onChange 时的兜底：手动同步缓冲区。
    const text: string = this.vm.draftBuffer;
    const before: string = text.slice(0, caret);
    const after: string = text.slice(caret);
    this.vm.updateDraft(before + syntax + after);
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
    const popped: string | undefined = this.redoStack.pop();
    if (popped === undefined) {
      return;
    }
    this.undoStack.push(this.vm.draftBuffer);
    this.undoDepth = this.undoStack.length;
    this.redoDepth = this.redoStack.length;
    this.replaceEditorText(popped, popped.length);
  }

  /** 更新 wiki 链接 / 标签补全浮层。 */
  private updateCompletion(text: string, caret: number): void {
    if (caret < 0) {
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

  /** 应用模板光标位置：套用模板后把光标放到 {{cursor}} 所在处。 */
  private applyPendingCaret(): void {
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
      this.insertFormat(`![[${name}]]`);
      this.toast($r('app.string.msg_image_done'));
    } catch (error) {
      const err = error as BusinessError;
      LOG.error(`pick image failed, code=${err.code}, message=${err.message}`);
    }
  }

  /** 从 URI 中提取扩展名（不含点）。 */
  private extensionOfUri(uri: string): string {
    const clean: string = uri.split('?')[0];
    const index: number = clean.lastIndexOf('.');
    if (index < 0) {
      return 'png';
    }
    const ext: string = clean.substring(index + 1).toLowerCase();
    return ext.length > 0 ? ext : 'png';
  }

  /** 轻提示（使用 UIContext 的 PromptAction，避免全局 promptAction 的弃用告警）。 */
  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }
}
