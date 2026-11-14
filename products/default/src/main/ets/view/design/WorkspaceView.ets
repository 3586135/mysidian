import { MdBlock, MdBlockType, OutlineEntry } from '@ohos/domain';
import { EmptyState, FileTreeView, Logger } from '@ohos/common';
import { MdDocumentView, MdDocumentViewController, MdInlineFlattener } from '@ohos/markdown';
import { VaultViewModel } from '../../viewmodel/VaultViewModel';
import { EditorPane } from './EditorPane';
import { NoteInfoSheet } from './NoteInfoSheet';

const LOG: Logger = new Logger('WorkspaceView');

/** 页面视图状态机：首页 / 工作台。 */
export class DesignViewMode {
  static readonly HOME: number = 0;
  static readonly WORKSPACE: number = 1;
}

/**
 * 工作台返回键信号。
 * @Entry 的 onBackPress 无法下探到子组件，通过该 @ObservedV2 信号对象
 * 把返回事件传入 WorkspaceView，由其按内部状态链消费。
 */
@ObservedV2
export class WorkspaceBackSignal {
  @Trace count: number = 0;

  request(): void {
    this.count = this.count + 1;
  }
}

/**
 * Material 3 工作台全屏子视图（单页架构，无 router 跳转）。
 *
 * 宽屏：Row(文件树 280vp + 编辑器卡片 + 分屏栏 + 固定信息面板 ≥900vp)；
 * 窄屏：SideBarContainer 抽屉 + 编辑器 + 右滑信息面板 + 新建 FAB。
 * 常驻全屏容器显式声明 hitTestBehavior（v0.3.0 触摸拦截教训）。
 */
@ComponentV2
export struct WorkspaceView {
  @Param vm: VaultViewModel = new VaultViewModel();
  @Param keyboardHeight: number = 0;    // 键盘高度（vp，NONE 避让下让位）
  @Param isWide: boolean = false;       // 宽屏形态
  @Param topInset: number = 0;          // 状态栏避让高度（vp）
  @Param bottomInset: number = 0;       // 导航条避让高度（vp）
  @Param backSignal: WorkspaceBackSignal = new WorkspaceBackSignal();
  @Event onRequestExit: () => void = (): void => {};
  @Event onEditorKeyboardMode: (active: boolean) => void = (active: boolean): void => {};
  @Event onOpenTag: (tag: string) => void = (tag: string): void => {};
  @Event onNoteMutated: () => void = (): void => {};

  /** 窄屏文件侧栏（抽屉）。 */
  @Local showSideBar: boolean = false;
  /** 窄屏信息面板覆盖层。 */
  @Local showInfo: boolean = false;
  /** 宽屏右侧信息面板开关。 */
  @Local showRightPanel: boolean = true;
  /** 编辑区键盘交互态镜像（EditorPane 上抛）。 */
  @Local editorKeyboardMode: boolean = false;
  /** 内容区实际宽度（边缘手势保留区 / 信息面板并排阈值判定）。 */
  @Local contentWidth: number = 0;

  private docController: MdDocumentViewController = new MdDocumentViewController();
  private secondaryDocController: MdDocumentViewController = new MdDocumentViewController();

  aboutToAppear(): void {
    this.vm.onScrollToHeading = (heading: string): void => {
      this.scrollToHeading(heading);
    };
    this.vm.onNoteCreated = (path: string): void => {
      this.toast($r('app.string.msg_wiki_created'));
    };
  }

  aboutToDisappear(): void {
    this.vm.onScrollToHeading = (heading: string): void => {};
    this.vm.onNoteCreated = (path: string): void => {};
  }

  /** @Entry onBackPress 经信号对象触发的返回链。 */
  @Monitor('backSignal.count')
  onBackSignalChanged(): void {
    this.handleBack();
  }

  build() {
    Column() {
      if (this.vm.vaults.length === 0) {
        this.emptyVaultView()
      } else if (this.isWide) {
        this.wideLayout()
      } else {
        this.narrowLayout()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.design_bg'))
    .padding({ top: this.topInset, bottom: this.bottomInset })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.contentWidth = Number(newArea.width);
    })
    .hitTestBehavior(HitTestMode.Default)
  }

  // ==================== 宽屏布局 ====================

  @Builder
  wideLayout() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Row() {
        Column() {
          this.notesHeader()
          FileTreeView({
            items: this.vm.treeItems,
            selectedPath: this.vm.selectedPath,
            selectedBgColor: $r('app.color.design_accent_weak'),
            selectedTextColor: $r('app.color.design_text_primary'),
            onSelect: (path: string, isDir: boolean): void => {
              this.openNoteFrom(path);
            },
            onToggle: (path: string): void => {
              this.vm.toggleDir(path);
            },
            onMoveNote: (path: string, destDir: string): void => {
              this.moveNoteTo(path, destDir);
            }
          })
        }
        .width(this.fixedPanelEnabled() ? 280 : 250)
        .height('100%')
        .backgroundColor($r('app.color.design_bg'))
        .border({ width: { right: 1 }, color: $r('app.color.design_divider') })

        Column() {
          EditorPane({
            vm: this.vm,
            isWide: true,
            keyboardHeight: this.keyboardHeight,
            contentWidth: this.contentWidth,
            docController: this.docController,
            onEditorKeyboardMode: (active: boolean): void => {
              this.editorKeyboardMode = active;
              this.onEditorKeyboardMode(active);
            },
            onRequestExit: (): void => {
              this.onRequestExit();
            },
            onToggleInfoPanel: (): void => {
              this.animAssign((): void => {
                this.showRightPanel = !this.showRightPanel;
              });
            },
            onDismissOverlays: (): void => {
            },
            onContentSwipe: (offsetX: number): void => {
              this.handleContentSwipe(offsetX);
            },
            onOpenTag: (tag: string): void => {
              this.onOpenTag(tag);
            },
            onNoteMutated: (): void => {
              this.onNoteMutated();
            }
          })
        }
        .layoutWeight(1)
        .height('100%')
        .backgroundColor($r('app.color.design_surface_solid'))
        .borderRadius(18)
        .border({ width: 1, color: $r('app.color.design_stroke') })
        .margin({ top: 12, bottom: 12, right: this.showFixedInfoPanel() ? 0 : 12 })
        .clip(true)

        if (this.vm.secondaryPath.length > 0) {
          Column() {
            this.secondaryArea()
          }
          .layoutWeight(1)
          .height('100%')
          .backgroundColor($r('app.color.design_surface_solid'))
          .borderRadius(18)
          .border({ width: 1, color: $r('app.color.design_stroke') })
          .margin({ top: 12, bottom: 12, right: this.showFixedInfoPanel() ? 0 : 12 })
          .clip(true)
        }

        if (this.showFixedInfoPanel()) {
          Column() {
            this.infoPanelContent()
          }
          .width(300)
          .height('100%')
          .backgroundColor($r('app.color.design_surface_solid'))
          .borderRadius(18)
          .border({ width: 1, color: $r('app.color.design_stroke') })
          .margin({ top: 12, bottom: 12, right: 12 })
          .clip(true)
        }
      }
      .width('100%')
      .height('100%')

      // 宽屏浮动信息面板（内容区 < 900vp 时的右缘滑入形态）
      if (this.showRightPanel && !this.fixedPanelEnabled()) {
        Column() {
          Row() {
            Blank()
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([$r('app.color.design_text_secondary')])
              .width(36)
              .height(36)
              .onClick(() => {
                this.animAssign((): void => {
                  this.showRightPanel = false;
                });
              })
          }
          .width('100%')
          .height(44)
          .padding({ left: 12, right: 4 })
          .alignItems(VerticalAlign.Center)

          Column() {
            this.infoPanelContent()
          }
          .layoutWeight(1)
        }
        .width(360)
        .height('100%')
        .backgroundColor($r('app.color.design_surface_solid'))
        .border({ width: { left: 1 }, color: $r('app.color.design_stroke') })
        .shadow({ radius: 20, color: $r('app.color.design_shadow'), offsetX: -4 })
        .position({ x: '100%' })
        .markAnchor({ x: '100%' })
        .transition(TransitionEffect.translate({ x: '100%' })
          .animation({ duration: 260, curve: Curve.Friction }))
      }

      if (!this.vm.editMode) {
        this.newNoteFab(20)
      }
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 窄屏布局 ====================

  @Builder
  narrowLayout() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      SideBarContainer(SideBarContainerType.Overlay) {
        Column() {
          this.notesHeader()
          FileTreeView({
            items: this.vm.treeItems,
            selectedPath: this.vm.selectedPath,
            selectedBgColor: $r('app.color.design_accent_weak'),
            selectedTextColor: $r('app.color.design_text_primary'),
            onSelect: (path: string, isDir: boolean): void => {
              this.openNoteFrom(path);
            },
            onToggle: (path: string): void => {
              this.vm.toggleDir(path);
            },
            onMoveNote: (path: string, destDir: string): void => {
              this.moveNoteTo(path, destDir);
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.design_bg'))

        Column() {
          EditorPane({
            vm: this.vm,
            isWide: false,
            keyboardHeight: this.keyboardHeight,
            contentWidth: this.contentWidth,
            docController: this.docController,
            onEditorKeyboardMode: (active: boolean): void => {
              this.editorKeyboardMode = active;
              this.onEditorKeyboardMode(active);
            },
            onRequestExit: (): void => {
              this.onRequestExit();
            },
            onToggleSidebar: (): void => {
              this.animAssign((): void => {
                this.showSideBar = !this.showSideBar;
              });
            },
            onToggleInfoPanel: (): void => {
              this.animAssign((): void => {
                this.showInfo = !this.showInfo;
              });
            },
            onDismissOverlays: (): void => {
              this.dismissOverlays();
            },
            onContentSwipe: (offsetX: number): void => {
              this.handleContentSwipe(offsetX);
            },
            onOpenTag: (tag: string): void => {
              this.onOpenTag(tag);
            },
            onNoteMutated: (): void => {
              this.onNoteMutated();
            }
          })
        }
        .width('100%')
        .height('100%')
        // NONE 避让下页面未被压缩：键盘弹出时编辑区与工具栏整体让出键盘高度。
        .padding({
          bottom: this.editorKeyboardMode && this.keyboardHeight > 0 ? this.keyboardHeight : 0
        })
      }
      .showSideBar(this.showSideBar)
      .sideBarWidth(300)
      .minSideBarWidth(220)
      .maxSideBarWidth(360)
      .autoHide(true)
      .showControlButton(false)
      .onChange((visible: boolean) => {
        this.showSideBar = visible;
      })
      .width('100%')
      .height('100%')

      // 窄屏信息面板：右缘滑入覆盖层
      if (this.showInfo) {
        Column() {
          Row() {
            Text(this.vm.noteTitle)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.design_text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([$r('app.color.design_text_secondary')])
              .width(36)
              .height(36)
              .onClick(() => {
                this.animAssign((): void => {
                  this.showInfo = false;
                });
              })
          }
          .width('100%')
          .height(44)
          .padding({ left: 16, right: 4 })
          .alignItems(VerticalAlign.Center)

          Column() {
            this.infoPanelContent()
          }
          .layoutWeight(1)
        }
        .width('88%')
        .height('100%')
        .backgroundColor($r('app.color.design_surface_solid'))
        .border({ width: { left: 1 }, color: $r('app.color.design_stroke') })
        .shadow({ radius: 20, color: $r('app.color.design_shadow'), offsetX: -4 })
        .position({ x: '100%' })
        .markAnchor({ x: '100%' })
        .transition(TransitionEffect.translate({ x: '100%' })
          .animation({ duration: 260, curve: Curve.Friction }))
      }

      if (!this.vm.editMode) {
        this.newNoteFab(this.editorKeyboardMode && this.keyboardHeight > 0 ?
          this.keyboardHeight + 20 : 20)
      }
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 公共部件 ====================

  /** 文件树头部：返回首页 + 仓库名 + 更多菜单。 */
  @Builder
  notesHeader() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(22)
        .fontColor([$r('app.color.design_text_primary')])
        .width(40)
        .height(40)
        .margin({ left: -4 })
        .onClick(() => {
          this.onRequestExit();
        })
      Text(this.vm.currentVault.name.length > 0 ? this.vm.currentVault.name : $r('app.string.app_title'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.design_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.more'))
        .fontSize(22)
        .fontColor([$r('app.color.design_text_primary')])
        .width(40)
        .height(40)
        .bindMenu(this.moreMenuBuilder)
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 4 })
    .alignItems(VerticalAlign.Center)
  }

  /** 更多菜单：高频操作入口（弹层类入口随阶段 4/5 接入）。 */
  @Builder
  moreMenuBuilder() {
    Menu() {
      MenuItem({ content: $r('app.string.action_new_note') })
        .onClick(() => {
          this.vm.createNote().then((): void => {
            this.onNoteMutated();
          });
        })
    }
  }

  /** 信息面板内容（宽屏固定栏 / 宽屏浮动栏 / 窄屏覆盖层共用）。 */
  @Builder
  infoPanelContent() {
    NoteInfoSheet({
      vm: this.vm,
      onOpenNote: (path: string): void => {
        this.openNoteFrom(path);
      },
      onOpenTag: (tag: string): void => {
        this.onOpenTag(tag);
      },
      onOutlineClick: (entry: OutlineEntry): void => {
        this.scrollToOutlineEntry(entry);
      }
    })
  }

  /** 分屏第二栏：只读预览参考笔记（平板 / 折叠屏宽态）。 */
  @Builder
  secondaryArea() {
    Column() {
      Row() {
        Text(this.vm.secondaryPath)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(16)
          .fontColor([$r('app.color.design_text_secondary')])
          .width(32)
          .height(32)
          .onClick(() => {
            this.vm.closeSecondary();
          })
      }
      .width('100%')
      .height(44)
      .padding({ left: 14, right: 6 })
      .alignItems(VerticalAlign.Center)

      MdDocumentView({
        document: this.vm.secondaryDocument,
        docKey: this.vm.secondaryPath,
        fontSize: this.vm.fontSize,
        controller: this.secondaryDocController,
        onOpenLink: (target: string, kind: string): void => {
          this.vm.openLink(target, kind);
        }
      })
      .layoutWeight(1)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
  }

  /** 新建笔记悬浮按钮。 */
  @Builder
  newNoteFab(bottomMargin: number) {
    Column() {
      SymbolGlyph($r('sys.symbol.square_and_pencil'))
        .fontSize(24)
        .fontColor([$r('app.color.design_text_primary')])
    }
    .width(56)
    .height(56)
    .borderRadius(28)
    .backgroundColor($r('app.color.design_elevated'))
    .border({ width: 1, color: $r('app.color.design_stroke') })
    .shadow({ radius: 20, color: $r('app.color.design_shadow'), offsetY: 6 })
    .justifyContent(FlexAlign.Center)
    .margin({ right: 20, bottom: bottomMargin })
    .transition(TransitionEffect.scale({ x: 0, y: 0 })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 250, curve: Curve.Friction }))
    .onClick(() => {
      this.vm.createNote().then((): void => {
        this.onNoteMutated();
      });
    })
  }

  /** 仓库为空时的占位视图（完整引导流随新建仓库弹层在阶段 4 接入）。 */
  @Builder
  emptyVaultView() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([$r('app.color.design_text_primary')])
          .width(40)
          .height(40)
          .onClick(() => {
            this.onRequestExit();
          })
        Text($r('app.string.app_title'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.design_text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      EmptyState({
        title: $r('app.string.welcome_title'),
        description: $r('app.string.welcome_desc'),
        icon: $r('sys.symbol.doc_plaintext'),
        iconColor: $r('app.color.design_text_secondary')
      })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 布局判定与交互 ====================

  /** 宽度是否足以让信息面板与编辑器并排显示。 */
  private fixedPanelEnabled(): boolean {
    return this.contentWidth >= 900;
  }

  /** 是否以固定侧栏形式显示信息面板。 */
  private showFixedInfoPanel(): boolean {
    return this.showRightPanel && this.fixedPanelEnabled();
  }

  /** 在过渡动画中修改状态。 */
  private animAssign(action: () => void): void {
    this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, action);
  }

  /** 系统返回链：退出编辑（自动保存）→ 收窄屏浮层 → 返回首页。 */
  private handleBack(): void {
    if (this.vm.editMode) {
      this.exitEditWithSave();
      return;
    }
    if (!this.isWide) {
      if (this.showInfo) {
        this.animAssign((): void => {
          this.showInfo = false;
        });
        return;
      }
      if (this.showSideBar) {
        this.animAssign((): void => {
          this.showSideBar = false;
        });
        return;
      }
    }
    this.onRequestExit();
  }

  /**
   * 返回键退出编辑：有改动则自动保存。
   * 侧滑返回极易误触，直接丢弃草稿会丢失整段输入（对标 Obsidian 的自动保存）。
   */
  private exitEditWithSave(): void {
    this.onEditorKeyboardMode(false);
    if (this.vm.draftBuffer === this.vm.noteContent) {
      this.vm.cancelEdit();
      return;
    }
    this.vm.saveDraft().then((): void => {
      this.toast($r('app.string.msg_edit_autosaved'));
      this.onNoteMutated();
    });
  }

  /** 打开笔记并收起窄屏浮层（信息面板 / 文件侧栏）。 */
  private openNoteFrom(path: string): void {
    this.vm.openNote(path);
    this.animAssign((): void => {
      this.showInfo = false;
      if (!this.isWide) {
        this.showSideBar = false;
      }
    });
  }

  /** 正文区横向滑动：向右滑呼出文件侧栏，向左滑查看双链。 */
  private handleContentSwipe(offsetX: number): void {
    if (offsetX > 60) {
      if (!this.isWide && this.showInfo) {
        this.animAssign((): void => {
          this.showInfo = false;
        });
        return;
      }
      if (this.isWide || this.showSideBar) {
        return;
      }
      this.animAssign((): void => {
        this.showSideBar = true;
      });
    } else if (offsetX < -60) {
      if (!this.isWide && this.showSideBar) {
        this.animAssign((): void => {
          this.showSideBar = false;
        });
        return;
      }
      this.openBacklinks();
    }
  }

  /** 收起窄屏浮层：信息面板与文件侧栏。 */
  private dismissOverlays(): void {
    if (this.isWide) {
      return;
    }
    if (this.showInfo) {
      this.animAssign((): void => {
        this.showInfo = false;
      });
    }
    if (this.showSideBar) {
      this.animAssign((): void => {
        this.showSideBar = false;
      });
    }
  }

  /** 打开双链信息（窄屏覆盖层 / 宽屏右侧面板）。 */
  private openBacklinks(): void {
    if (this.isWide) {
      this.animAssign((): void => {
        this.showRightPanel = true;
      });
      return;
    }
    this.vm.setInfoTab(1);
    this.animAssign((): void => {
      this.showInfo = true;
    });
  }

  /** 大纲点击定位：编辑模式下先保存草稿并切回预览，再滚动到目标标题块。 */
  private async scrollToOutlineEntry(entry: OutlineEntry): Promise<void> {
    if (this.vm.editMode) {
      await this.vm.saveDraft();
      setTimeout((): void => {
        this.docController.scrollToBlock(entry.ordinal);
      }, 360);
    } else {
      this.docController.scrollToBlock(entry.ordinal);
    }
  }

  /** 滚动到指定标题块：按标题文本匹配块序号。 */
  private scrollToHeading(heading: string): void {
    const target: string = heading.trim().toLowerCase();
    if (target.length === 0) {
      return;
    }
    const blocks: MdBlock[] = this.vm.document.blocks;
    for (let i = 0; i < blocks.length; i++) {
      const block: MdBlock = blocks[i];
      if (block.type !== MdBlockType.HEADING) {
        continue;
      }
      if (this.headingText(block).toLowerCase() === target) {
        setTimeout((): void => {
          this.docController.scrollToBlock(i);
        }, 360);
        return;
      }
    }
    LOG.info(`heading not found: ${heading}`);
  }

  /** 标题块的纯文本。 */
  private headingText(block: MdBlock): string {
    let text: string = '';
    const segments = MdInlineFlattener.flatten(block.inlines);
    for (const segment of segments) {
      text += segment.text;
    }
    return text.trim();
  }

  /** 文件树拖拽：把笔记移动到目标目录。 */
  private moveNoteTo(path: string, destDir: string): void {
    this.vm.moveNote(path, destDir).then((ok: boolean): void => {
      if (!ok) {
        this.toast($r('app.string.msg_move_failed'));
        return;
      }
      this.toast($r('app.string.msg_move_done'));
      this.onNoteMutated();
    });
  }

  /** 轻提示（使用 UIContext 的 PromptAction，避免全局 promptAction 的弃用告警）。 */
  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }
}
