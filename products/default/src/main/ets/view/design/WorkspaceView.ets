import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { MdBlock, MdBlockType, OutlineEntry, VaultInfo } from '@ohos/domain';
import { FileTreeView, Logger } from '@ohos/common';
import { MdDocumentView, MdDocumentViewController, MdInlineFlattener } from '@ohos/markdown';
import { AppCommand } from '../../viewmodel/AppCommand';
import { SearchViewModel } from '../../viewmodel/SearchViewModel';
import { VaultViewModel } from '../../viewmodel/VaultViewModel';
import { CalendarSheet } from './CalendarSheet';
import { CommandPalette } from './CommandPalette';
import { CreateVaultRequest, DesignDialogKind, DialogHost } from './DialogHost';
import { EditorPane } from './EditorPane';
import { HandwriteSheet } from './HandwriteSheet';
import { HistorySheet } from './HistorySheet';
import { NoteInfoSheet } from './NoteInfoSheet';
import { OnboardView } from './OnboardView';
import { QuickNoteSheet } from './QuickNoteSheet';
import { QuickSwitcher } from './QuickSwitcher';
import { RecentNotesPanel } from './RecentNotesPanel';
import { SearchOverlay } from './SearchOverlay';
import { TemplateSheet } from './TemplateSheet';
import { TrashSheet } from './TrashSheet';
import { ImagePreviewOverlay } from './ImagePreviewOverlay';
import { TreeItemMenuSheet } from './TreeItemMenuSheet';
import { confirmTrashFolderAction, confirmTrashNoteAction, ThreeDotsIcon } from './NoteActionHelper';

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
  @Param searchVm: SearchViewModel = new SearchViewModel();
  @Param keyboardHeight: number = 0;    // 键盘高度（vp，NONE 避让下让位）
  @Param isWide: boolean = false;       // 宽屏形态
  @Param topInset: number = 0;          // 状态栏避让高度（vp）
  @Param bottomInset: number = 0;       // 导航条避让高度（vp）
  @Param backSignal: WorkspaceBackSignal = new WorkspaceBackSignal();
  /** 启动动作（外部进入时携带，如 templates）。 */
  @Param launchAction: string = '';
  /** 无仓库引导：WebDAV 是否已配置（同步入口描述文案）。 */
  @Param syncConfigured: boolean = false;
  @Event onRequestExit: () => void = (): void => {};
  @Event onEditorKeyboardMode: (active: boolean) => void = (active: boolean): void => {};
  @Event onOpenTag: (tag: string) => void = (tag: string): void => {};
  @Event onNoteMutated: () => void = (): void => {};
  /** 无仓库引导：新建仓库（含 WebDAV 配置）上抛 @Entry 落库。 */
  @Event onRequestCreateVault: (request: CreateVaultRequest) => void =
    (_request: CreateVaultRequest): void => {};
  /** 无仓库引导：打开 WebDAV 同步设置。 */
  @Event onRequestSync: () => void = (): void => {};
  /** 外部 Markdown 只读预览：导入当前仓库（editAfter 表示导入后进入编辑态）。 */
  @Event onRequestImportExternal: (editAfter: boolean) => void = (_editAfter: boolean): void => {};
  /** 外部 Markdown 只读预览：关闭预览并恢复会话。 */
  @Event onRequestCloseExternal: () => void = (): void => {};

  /** 窄屏文件侧栏（抽屉）。 */
  @Local showSideBar: boolean = false;
  /** 窄屏与非三栏设备浮动信息面板（默认收起，仅手动开启）。 */
  @Local showInfo: boolean = false;
  /** 宽屏三栏固定信息面板开关（仅平板/桌面 >= 900vp 时生效）。 */
  @Local showFixedPanel: boolean = true;
  /** 编辑区键盘交互态镜像（EditorPane 上抛）。 */
  @Local editorKeyboardMode: boolean = false;
  /** 内容区实际宽高（边缘手势保留区 / 三栏并排阈值判定）。 */
  @Local contentWidth: number = 0;
  @Local contentHeight: number = 0;
  /** 当前对话框场景（DesignDialogKind.NONE 表示无）。 */
  @Local dialogKind: string = DesignDialogKind.NONE;
  /** 对话框显式目标路径（为空时沿用当前已选笔记）。 */
  @Local dialogTargetPath: string = '';
  /** 回收站浮层。 */
  @Local showTrashSheet: boolean = false;
  /** 历史版本浮层。 */
  @Local showHistorySheet: boolean = false;
  /** 模板选择浮层。 */
  @Local showTemplateSheet: boolean = false;
  /** 日历浮层。 */
  @Local showCalendarSheet: boolean = false;
  /** 手写速记浮层。 */
  @Local showHandwriteSheet: boolean = false;
  /** 快速闪念浮层。 */
  @Local showQuickNoteSheet: boolean = false;
  /** 命令面板浮层。 */
  @Local showCommandPalette: boolean = false;
  /** 快速切换器浮层。 */
  @Local showQuickSwitcher: boolean = false;
  /** 最近访问浮层。 */
  @Local showRecentPanel: boolean = false;
  /** 全文搜索浮层。 */
  @Local showSearchOverlay: boolean = false;
  /** 快速切换器当前处于分屏选择模式（选中笔记后进第二栏）。 */
  @Local splitPickMode: boolean = false;
  /** 图片全屏预览 URI（非空时展示预览浮层）。 */
  @Local previewImageUri: string = '';
  /** 文件树条目菜单目标路径与目录标志。 */
  @Local treeMenuPath: string = '';
  @Local treeMenuIsDir: boolean = false;

  private docController: MdDocumentViewController = new MdDocumentViewController();
  private secondaryDocController: MdDocumentViewController = new MdDocumentViewController();
  /** 命令面板命令集。 */
  private commands: AppCommand[] = [];

  aboutToAppear(): void {
    this.vm.onScrollToHeading = (heading: string): void => {
      this.scrollToHeading(heading);
    };
    this.vm.onNoteCreated = (path: string): void => {
      this.toast($r('app.string.msg_wiki_created'));
    };
    this.vm.onPreviewAttachment = (uri: string): void => {
      this.animAssign((): void => {
        this.previewImageUri = uri;
      });
    };
    this.commands = this.buildCommands();
    // 外部启动动作：templates → 直接打开模板选择浮层。
    if (this.launchAction === 'templates') {
      this.showTemplateSheet = true;
    }
  }

  aboutToDisappear(): void {
    this.vm.onScrollToHeading = (heading: string): void => {};
    this.vm.onNoteCreated = (path: string): void => {};
    this.vm.onPreviewAttachment = (_uri: string): void => {};
  }

  /** @Entry onBackPress 经信号对象触发的返回链。 */
  @Monitor('backSignal.count')
  onBackSignalChanged(): void {
    this.handleBack();
  }

  build() {
    Stack() {
      Column() {
        if (this.vm.vaults.length === 0 && !this.vm.isExternalMode) {
          this.emptyVaultView()
        } else if (this.vm.vaults.length === 0 && this.vm.isExternalMode) {
          this.externalOnlyLayout()
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
        this.contentHeight = Number(newArea.height);
      })
      .hitTestBehavior(HitTestMode.Default)

      // ===== 弹层（对话框 / 回收站 / 历史 / 模板 / 日历 / 手写 / 闪念 / 命令面板 / 快切 / 最近 / 搜索）=====

      if (this.dialogKind !== DesignDialogKind.NONE) {
        DialogHost({
          kind: this.dialogKind,
          targetPath: this.dialogTargetPath,
          vm: this.vm,
          onClose: (): void => {
            this.animAssign((): void => {
              this.dialogKind = DesignDialogKind.NONE;
              this.dialogTargetPath = '';
            });
          },
          onNoteMutated: (): void => {
            this.onNoteMutated();
          },
          onCreateVault: (request: CreateVaultRequest): void => {
            this.onRequestCreateVault(request);
          }
        })
      }

      if (this.showTrashSheet) {
        TrashSheet({
          vm: this.vm,
          onClose: (): void => {
            this.animAssign((): void => {
              this.showTrashSheet = false;
            });
          },
          onNoteMutated: (): void => {
            this.onNoteMutated();
          }
        })
      }

      if (this.showHistorySheet) {
        HistorySheet({
          vm: this.vm,
          onClose: (): void => {
            this.animAssign((): void => {
              this.showHistorySheet = false;
            });
          },
          onNoteMutated: (): void => {
            this.onNoteMutated();
          }
        })
      }

      if (this.showTemplateSheet) {
        TemplateSheet({
          vm: this.vm,
          onClose: (): void => {
            this.animAssign((): void => {
              this.showTemplateSheet = false;
            });
          },
          onNoteMutated: (): void => {
            this.onNoteMutated();
          }
        })
      }

      if (this.showCalendarSheet) {
        CalendarSheet({
          vm: this.vm,
          onClose: (): void => {
            this.animAssign((): void => {
              this.showCalendarSheet = false;
            });
          },
          onNoteMutated: (): void => {
            this.onNoteMutated();
          }
        })
      }

      if (this.showHandwriteSheet) {
        HandwriteSheet({
          onSave: (data: ArrayBuffer): void => {
            this.saveHandwrite(data);
          },
          onClose: (): void => {
            this.animAssign((): void => {
              this.showHandwriteSheet = false;
            });
          }
        })
      }

      if (this.showQuickNoteSheet) {
        QuickNoteSheet({
          vm: this.vm,
          onClose: (): void => {
            this.animAssign((): void => {
              this.showQuickNoteSheet = false;
            });
          },
          onNoteMutated: (): void => {
            this.onNoteMutated();
          }
        })
      }

      if (this.showCommandPalette) {
        CommandPalette({
          commands: this.commands,
          onRun: (command: AppCommand): void => {
            this.animAssign((): void => {
              this.showCommandPalette = false;
            });
            command.action();
          },
          onClose: (): void => {
            this.animAssign((): void => {
              this.showCommandPalette = false;
            });
          }
        })
      }

      if (this.showQuickSwitcher) {
        QuickSwitcher({
          searchVm: this.searchVm,
          onOpenNote: (path: string): void => {
            this.openNoteFromQuickSwitcher(path);
          },
          onClose: (): void => {
            this.animAssign((): void => {
              this.showQuickSwitcher = false;
              this.splitPickMode = false;
            });
          }
        })
      }

      if (this.showRecentPanel) {
        RecentNotesPanel({
          vm: this.vm,
          onOpenNote: (path: string): void => {
            this.animAssign((): void => {
              this.showRecentPanel = false;
            });
            this.openNoteFrom(path);
          },
          onClose: (): void => {
            this.animAssign((): void => {
              this.showRecentPanel = false;
            });
          }
        })
      }

      if (this.showSearchOverlay) {
        SearchOverlay({
          vm: this.vm,
          searchVm: this.searchVm,
          onOpenNote: (path: string): void => {
            this.animAssign((): void => {
              this.showSearchOverlay = false;
            });
            this.openNoteFrom(path);
          },
          onClose: (): void => {
            this.animAssign((): void => {
              this.showSearchOverlay = false;
            });
          }
        })
      }

      if (this.treeMenuPath.length > 0) {
        TreeItemMenuSheet({
          targetPath: this.treeMenuPath,
          isDir: this.treeMenuIsDir,
          bookmarked: this.vm.isBookmarked(this.treeMenuPath),
          onClose: (): void => {
            this.animAssign((): void => {
              this.treeMenuPath = '';
            });
          },
          onNewNoteInFolder: (folder: string): void => {
            this.vm.createNote(folder).then((): void => {
              this.onNoteMutated();
            }).catch((error: BusinessError): void => {
              LOG.error(`create note in ${folder} failed, code=${error.code}, message=${error.message}`);
            });
          },
          onNewSubfolder: (folder: string): void => {
            this.vm.pendingFolderPrefix = `${folder}/`;
            this.openDialog(DesignDialogKind.NEW_FOLDER);
          },
          onTrashFolder: (folder: string): void => {
            this.confirmTrashFolder(folder);
          },
          onOpenNote: (path: string): void => {
            this.openNoteFrom(path);
          },
          onSplitOpen: (path: string): void => {
            if (this.fixedPanelEnabled()) {
              this.showFixedPanel = false;
            }
            this.showInfo = false;
            this.vm.openSecondary(path).catch((error: BusinessError): void => {
              LOG.error(`open secondary note failed, code=${error.code}, message=${error.message}`);
            });
          },
          onToggleBookmark: (path: string): void => {
            this.vm.toggleBookmark(path).then((added: boolean): void => {
              this.toast(added ? $r('app.string.msg_bookmark_added') : $r('app.string.msg_bookmark_removed'));
            }).catch((error: BusinessError): void => {
              LOG.error(`toggle bookmark failed, code=${error.code}, message=${error.message}`);
            });
          },
          onRenameNote: (path: string): void => {
            this.openRenameDialog(path);
          },
          onMoveNote: (path: string): void => {
            this.openMoveDialog(path);
          },
          onTrashNote: (path: string): void => {
            this.confirmTrashNote(path);
          }
        })
      }

      if (this.previewImageUri.length > 0) {
        ImagePreviewOverlay({
          uri: this.previewImageUri,
          onClose: (): void => {
            this.animAssign((): void => {
              this.previewImageUri = '';
            });
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 宽屏布局 ====================

  @Builder
  wideLayout() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Row() {
        Column() {
          this.notesHeader()
          if (this.vm.bookmarks.length > 0) {
            this.bookmarkSection()
          }
          FileTreeView({
            items: this.vm.treeItems,
            selectedPath: this.vm.selectedPath,
            selectedBgColor: $r('app.color.design_accent_weak'),
            selectedTextColor: $r('app.color.design_text_primary'),
            textColor: $r('app.color.design_text_primary'),
            secondaryTextColor: $r('app.color.design_text_secondary'),
            onSelect: (path: string, isDir: boolean): void => {
              this.openNoteFrom(path);
            },
            onToggle: (path: string): void => {
              this.vm.toggleDir(path);
            },
            onMoveNote: (path: string, destDir: string): void => {
              this.moveNoteTo(path, destDir);
            },
            onItemAction: (path: string, isDir: boolean): void => {
              this.animAssign((): void => {
                this.treeMenuPath = path;
                this.treeMenuIsDir = isDir;
              });
            }
          })
        }
        .width(this.fixedPanelEnabled() ? 280 : (this.contentWidth < 760 ? 220 : 240))
        .height('100%')
        .backgroundColor($r('app.color.design_bg'))
        .border({ width: { right: 1 }, color: $r('app.color.design_divider') })

        Column() {
          this.workspaceEditorPane(true)
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

      if (!this.vm.editMode && this.vm.selectedPath.length > 0 && !this.vm.isExternalMode) {
        this.editFab(20)
      }

      // 非三栏设备浮动信息面板（内容区 < 900vp 或高度不足时右缘滑入覆盖层，默认收起）
      if (this.showInfo && !this.fixedPanelEnabled()) {
        this.floatingInfoOverlay()
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
          if (this.vm.bookmarks.length > 0) {
            this.bookmarkSection()
          }
          FileTreeView({
            items: this.vm.treeItems,
            selectedPath: this.vm.selectedPath,
            selectedBgColor: $r('app.color.design_accent_weak'),
            selectedTextColor: $r('app.color.design_text_primary'),
            textColor: $r('app.color.design_text_primary'),
            secondaryTextColor: $r('app.color.design_text_secondary'),
            onSelect: (path: string, isDir: boolean): void => {
              this.openNoteFrom(path);
            },
            onToggle: (path: string): void => {
              this.vm.toggleDir(path);
            },
            onMoveNote: (path: string, destDir: string): void => {
              this.moveNoteTo(path, destDir);
            },
            onItemAction: (path: string, isDir: boolean): void => {
              this.animAssign((): void => {
                this.treeMenuPath = path;
                this.treeMenuIsDir = isDir;
              });
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.design_bg'))

        Column() {
          this.workspaceEditorPane(false)
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

      if (!this.vm.editMode && this.vm.selectedPath.length > 0 && !this.vm.isExternalMode) {
        this.editFab(this.editorKeyboardMode && this.keyboardHeight > 0 ?
          this.keyboardHeight + 20 : 20)
      }

      // 窄屏信息面板：右缘滑入覆盖层（与非三栏宽屏共享同一浮层部件）
      if (this.showInfo) {
        this.floatingInfoOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 无任何仓库时打开外部 Markdown 的全屏只读预览布局（支持右侧信息面板）。 */
  @Builder
  externalOnlyLayout() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        this.workspaceEditorPane(false)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.design_surface_solid'))

      if (this.showInfo) {
        this.floatingInfoOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 共享编辑器面板实例（宽屏三栏 / 窄屏抽屉 / 无仓库外部预览统一复用）。 */
  @Builder
  workspaceEditorPane(wideMode: boolean) {
    EditorPane({
      vm: this.vm,
      isWide: wideMode,
      keyboardHeight: this.keyboardHeight,
      contentWidth: this.contentWidth,
      docController: this.docController,
      onEditorKeyboardMode: (active: boolean): void => {
        this.editorKeyboardMode = active;
        this.onEditorKeyboardMode(active);
      },
      onRequestExit: (): void => {
        if (this.vm.isExternalMode) {
          this.onRequestCloseExternal();
        } else {
          this.onRequestExit();
        }
      },
      onToggleSidebar: (): void => {
        if (!wideMode && this.vm.vaults.length > 0) {
          this.animAssign((): void => {
            this.showSideBar = !this.showSideBar;
          });
        }
      },
      onToggleInfoPanel: (): void => {
        this.animAssign((): void => {
          if (wideMode && this.fixedPanelEnabled()) {
            this.showFixedPanel = !this.showFixedPanel;
          } else {
            this.showInfo = !this.showInfo;
          }
        });
      },
      onRequestRename: (): void => {
        this.openRenameDialog();
      },
      onRequestMove: (): void => {
        this.openMoveDialog();
      },
      onRequestTrash: (): void => {
        this.confirmTrashNote();
      },
      onRequestHistory: (): void => {
        this.animAssign((): void => {
          this.showHistorySheet = true;
        });
      },
      onRequestSplit: (): void => {
        this.openSplitPicker();
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
      },
      onPreviewImage: (uri: string): void => {
        this.animAssign((): void => {
          this.previewImageUri = uri;
        });
      },
      onRequestImportExternal: (editAfter: boolean): void => {
        this.onRequestImportExternal(editAfter);
      },
      onRequestCloseExternal: (): void => {
        this.onRequestCloseExternal();
      }
    })
  }

  // ==================== 公共部件 ====================

  /** 手机与非三栏设备的右缘浮动信息抽屉（点击遮罩或右上角关闭按钮收起）。 */
  @Builder
  floatingInfoOverlay() {
    Stack({ alignContent: Alignment.End }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.design_dim'))
        .onClick(() => {
          this.animAssign((): void => {
            this.showInfo = false;
          });
        })

      Column() {
        Row() {
          Text(this.vm.noteTitle)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Stack() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(16)
              .fontColor([$r('app.color.design_text_secondary')])
          }
          .width(32)
          .height(32)
          .borderRadius(16)
          .backgroundColor($r('app.color.design_elevated'))
          .alignContent(Alignment.Center)
          .onClick(() => {
            this.animAssign((): void => {
              this.showInfo = false;
            });
          })
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 12 })
        .alignItems(VerticalAlign.Center)
        .border({ width: { bottom: 1 }, color: $r('app.color.design_divider') })

        Column() {
          this.infoPanelContent()
        }
        .layoutWeight(1)
      }
      .width(this.isWide ? 360 : '88%')
      .height('100%')
      .backgroundColor($r('app.color.design_surface_solid'))
      .border({ width: { left: 1 }, color: $r('app.color.design_stroke') })
      .shadow({ radius: 20, color: $r('app.color.design_shadow'), offsetX: -4 })
      .onClick(() => {
      })
      .transition(TransitionEffect.translate({ x: '100%' })
        .animation({ duration: 260, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.Friction }))
  }

  /** 文件树头部：返回首页 + 仓库名 + 更多菜单。 */
  @Builder
  notesHeader() {
    Row() {
      Blank().width(0).height(0)
        .keyboardShortcut('p', [ModifierKey.CTRL])
        .onClick(() => {
          this.animAssign((): void => {
            this.showCommandPalette = true;
          });
        })
      Blank().width(0).height(0)
        .keyboardShortcut('o', [ModifierKey.CTRL])
        .onClick(() => {
          this.openQuickSwitcher();
        })
      Blank().width(0).height(0)
        .keyboardShortcut('n', [ModifierKey.CTRL])
        .onClick(() => {
          this.vm.createNote().then((): void => {
            this.onNoteMutated();
          }).catch((error: BusinessError): void => {
            LOG.error(`create note failed, code=${error.code}, message=${error.message}`);
          });
        })
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(22)
        .fontColor([$r('app.color.design_text_primary')])
        .width(40)
        .height(40)
        .margin({ left: -4 })
        .accessibilityText($r('app.string.action_back'))
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
      Stack() {
        ThreeDotsIcon(3.5, 3, $r('app.color.design_text_primary'), 0.85)
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .alignContent(Alignment.Center)
      .accessibilityText($r('app.string.design_tab_more'))
      .bindMenu(this.moreMenuBuilder)
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 4 })
    .alignItems(VerticalAlign.Center)
  }

  /** 侧栏置顶书签列表。 */
  @Builder
  bookmarkSection() {
    Column({ space: 2 }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.star_fill'))
          .fontSize(12)
          .fontColor([$r('app.color.design_accent')])
        Text($r('app.string.bookmark_section'))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_text_secondary'))
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 4, bottom: 2 })

      ForEach(this.vm.bookmarks, (path: string) => {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(14)
            .fontColor([path === this.vm.selectedPath ?
              $r('app.color.design_accent') : $r('app.color.design_text_secondary')])
          Text(this.noteTitleOf(path))
            .fontSize(13)
            .fontColor(path === this.vm.selectedPath ?
              $r('app.color.design_text_primary') : $r('app.color.design_text_secondary'))
            .fontWeight(path === this.vm.selectedPath ? FontWeight.Medium : FontWeight.Normal)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.star_fill'))
            .fontSize(13)
            .fontColor([$r('app.color.design_accent')])
            .width(24)
            .height(24)
            .onClick(() => {
              this.vm.toggleBookmark(path).then((): void => {
                this.toast($r('app.string.msg_bookmark_removed'));
              }).catch((error: BusinessError): void => {
                LOG.error(`toggle bookmark failed, code=${error.code}, message=${error.message}`);
              });
            })
        }
        .width('100%')
        .height(32)
        .padding({ left: 10, right: 6 })
        .borderRadius(8)
        .backgroundColor(path === this.vm.selectedPath ?
          $r('app.color.design_accent_weak') : Color.Transparent)
        .onClick(() => {
          this.openNoteFrom(path);
        })
      }, (path: string) => path)
    }
    .width('100%')
    .padding({ left: 8, right: 8, bottom: 6 })
    .border({ width: { bottom: 1 }, color: $r('app.color.design_divider') })
  }

  /** 更多菜单：文件操作与弹层入口（对标旧工作台全量菜单）。 */
  @Builder
  moreMenuBuilder() {
    Menu() {
      MenuItem({ content: $r('app.string.menu_quick_switch') })
        .onClick(() => {
          this.openQuickSwitcher();
        })
      MenuItem({ content: $r('app.string.menu_command_palette') })
        .onClick(() => {
          this.animAssign((): void => {
            this.showCommandPalette = true;
          });
        })
      MenuItem({ content: $r('app.string.action_search') })
        .onClick(() => {
          this.openSearchOverlay();
        })
      MenuItem({ content: $r('app.string.action_new_note') })
        .onClick(() => {
          this.vm.createNote().then((): void => {
            this.onNoteMutated();
          }).catch((error: BusinessError): void => {
            LOG.error(`create note failed, code=${error.code}, message=${error.message}`);
          });
        })
      MenuItem({ content: $r('app.string.action_new_folder') })
        .onClick(() => {
          this.openDialog(DesignDialogKind.NEW_FOLDER);
        })
      MenuItem({ content: $r('app.string.action_rename') })
        .onClick(() => {
          this.openRenameDialog();
        })
      MenuItem({ content: $r('app.string.action_move') })
        .onClick(() => {
          this.openMoveDialog();
        })
      MenuItem({ content: $r('app.string.action_trash') })
        .onClick(() => {
          this.confirmTrashNote();
        })
      MenuItem({ content: $r('app.string.action_trash_list') })
        .onClick(() => {
          this.animAssign((): void => {
            this.showTrashSheet = true;
          });
        })
      MenuItem({ content: $r('app.string.action_calendar') })
        .onClick(() => {
          this.animAssign((): void => {
            this.showCalendarSheet = true;
          });
        })
      MenuItem({ content: $r('app.string.action_template') })
        .onClick(() => {
          this.animAssign((): void => {
            this.showTemplateSheet = true;
          });
        })
      MenuItem({ content: $r('app.string.action_history') })
        .onClick(() => {
          this.animAssign((): void => {
            this.showHistorySheet = true;
          });
        })
      MenuItem({ content: $r('app.string.action_split') })
        .onClick(() => {
          this.openSplitPicker();
        })
      MenuItem({ content: $r('app.string.action_share') })
        .onClick(() => {
          this.animAssign((): void => {
            this.showQuickNoteSheet = true;
          });
        })
      MenuItem({ content: $r('app.string.action_handwrite') })
        .onClick(() => {
          this.animAssign((): void => {
            this.showHandwriteSheet = true;
          });
        })
      MenuItem({ content: $r('app.string.action_import_vault') })
        .onClick(() => {
          this.importVault();
        })
      MenuItem({ content: $r('app.string.action_export_vault') })
        .onClick(() => {
          this.exportVault(this.vm.currentVault);
        })
      MenuItem({ content: $r('app.string.recent_notes_title') })
        .onClick(() => {
          this.openRecentPanel();
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
        Stack() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(15)
            .fontColor([$r('app.color.design_text_secondary')])
        }
        .width(30)
        .height(30)
        .borderRadius(15)
        .backgroundColor($r('app.color.design_elevated'))
        .alignContent(Alignment.Center)
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
        },
        onPreviewImage: (uri: string): void => {
          this.animAssign((): void => {
            this.previewImageUri = uri;
          });
        }
      })
      .layoutWeight(1)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
  }

  /** 编辑当前笔记悬浮按钮（原「新建笔记」FAB 改为进入编辑模式）。 */
  @Builder
  editFab(bottomMargin: number) {
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
    .accessibilityText($r('app.string.action_edit'))
    .keyboardShortcut('e', [ModifierKey.CTRL])
    .transition(TransitionEffect.scale({ x: 0, y: 0 })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 250, curve: Curve.Friction }))
    .onClick(() => {
      this.vm.startEdit();
    })
  }

  /** 从相对路径提取无扩展名标题。 */
  private noteTitleOf(path: string): string {
    const slash: number = path.lastIndexOf('/');
    const file: string = slash >= 0 ? path.substring(slash + 1) : path;
    return file.endsWith('.md') ? file.substring(0, file.length - 3) : file;
  }

  /** 仓库为空时的引导视图：新建 / 导入 / WebDAV 同步三入口。 */
  @Builder
  emptyVaultView() {
    OnboardView({
      syncConfigured: this.syncConfigured,
      onRequestExit: (): void => {
        this.onRequestExit();
      },
      onCreateVault: (): void => {
        this.openDialog(DesignDialogKind.CREATE_VAULT);
      },
      onImportVault: (): void => {
        this.importVault();
      },
      onOpenSync: (): void => {
        this.onRequestSync();
      }
    })
  }

  // ==================== 布局判定与交互 ====================

  /** 宽高是否足以让信息面板与文件树、编辑器三栏并排显示（平板横屏 / 桌面 >= 900x500vp）。 */
  private fixedPanelEnabled(): boolean {
    return this.contentWidth >= 900 && this.contentHeight >= 500;
  }

  /** 是否以固定三栏侧栏形式显示信息面板。 */
  private showFixedInfoPanel(): boolean {
    return this.showFixedPanel && this.fixedPanelEnabled();
  }

  /** 在过渡动画中修改状态。 */
  private animAssign(action: () => void): void {
    this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, action);
  }

  /** 系统返回链：关闭弹层 → 退出编辑（自动保存）→ 收窄屏浮层 → 返回首页。 */
  private handleBack(): void {
    if (this.previewImageUri.length > 0) {
      this.animAssign((): void => {
        this.previewImageUri = '';
      });
      return;
    }
    if (this.treeMenuPath.length > 0) {
      this.animAssign((): void => {
        this.treeMenuPath = '';
      });
      return;
    }
    if (this.dialogKind !== DesignDialogKind.NONE) {
      this.animAssign((): void => {
        this.dialogKind = DesignDialogKind.NONE;
        this.dialogTargetPath = '';
      });
      return;
    }
    if (this.showTrashSheet) {
      this.animAssign((): void => {
        this.showTrashSheet = false;
      });
      return;
    }
    if (this.showHistorySheet) {
      this.animAssign((): void => {
        this.showHistorySheet = false;
      });
      return;
    }
    if (this.showTemplateSheet) {
      this.animAssign((): void => {
        this.showTemplateSheet = false;
      });
      return;
    }
    if (this.showCalendarSheet) {
      this.animAssign((): void => {
        this.showCalendarSheet = false;
      });
      return;
    }
    if (this.showQuickNoteSheet) {
      this.animAssign((): void => {
        this.showQuickNoteSheet = false;
      });
      return;
    }
    if (this.showHandwriteSheet) {
      this.animAssign((): void => {
        this.showHandwriteSheet = false;
      });
      return;
    }
    if (this.showSearchOverlay) {
      this.animAssign((): void => {
        this.showSearchOverlay = false;
      });
      return;
    }
    if (this.showQuickSwitcher) {
      this.animAssign((): void => {
        this.showQuickSwitcher = false;
        this.splitPickMode = false;
      });
      return;
    }
    if (this.showRecentPanel) {
      this.animAssign((): void => {
        this.showRecentPanel = false;
      });
      return;
    }
    if (this.showCommandPalette) {
      this.animAssign((): void => {
        this.showCommandPalette = false;
      });
      return;
    }
    if (this.vm.editMode) {
      this.exitEditWithSave();
      return;
    }
    if (!this.fixedPanelEnabled() && this.showInfo) {
      this.animAssign((): void => {
        this.showInfo = false;
      });
      return;
    }
    if (!this.isWide && this.showSideBar) {
      this.animAssign((): void => {
        this.showSideBar = false;
      });
      return;
    }
    if (this.vm.isExternalMode) {
      this.onRequestCloseExternal();
      return;
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
    }).catch((error: BusinessError): void => {
      LOG.error(`save draft failed, code=${error.code}, message=${error.message}`);
    });
  }

  /** 打开笔记并收起非三栏设备的浮动层（信息抽屉 / 窄屏文件侧栏）。 */
  private openNoteFrom(path: string): void {
    this.vm.openNote(path).catch((error: BusinessError): void => {
      LOG.error(`open note failed, code=${error.code}, message=${error.message}`);
    });
    this.animAssign((): void => {
      this.showInfo = false;
      if (!this.isWide) {
        this.showSideBar = false;
      }
    });
  }

  /** 正文区横向滑动：收起浮层或呼出文件侧栏 / 双链信息。 */
  private handleContentSwipe(offsetX: number): void {
    if (offsetX > 60) {
      if (!this.fixedPanelEnabled() && this.showInfo) {
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

  /** 收起非固定三栏模式下的浮层：信息抽屉与窄屏文件侧栏。 */
  private dismissOverlays(): void {
    if (!this.fixedPanelEnabled() && this.showInfo) {
      this.animAssign((): void => {
        this.showInfo = false;
      });
    }
    if (!this.isWide && this.showSideBar) {
      this.animAssign((): void => {
        this.showSideBar = false;
      });
    }
  }

  /** 打开双链信息（平板三栏固定面板 / 手机与折叠屏浮动抽屉）。 */
  private openBacklinks(): void {
    this.vm.setInfoTab(1);
    this.animAssign((): void => {
      if (this.fixedPanelEnabled()) {
        this.showFixedPanel = true;
      } else {
        this.showInfo = true;
      }
    });
  }

  /** 大纲点击定位：编辑模式下先保存草稿并切回预览，再滚动到目标标题块。 */
  private async scrollToOutlineEntry(entry: OutlineEntry): Promise<void> {
    if (this.vm.editMode) {
      await this.vm.saveDraft();
      this.onNoteMutated();
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

  /** 打开指定场景对话框。 */
  private openDialog(kind: string, targetPath: string = ''): void {
    this.animAssign((): void => {
      this.dialogTargetPath = targetPath;
      this.dialogKind = kind;
    });
  }

  /** 打开重命名对话框（无选中笔记时提示）。 */
  private openRenameDialog(targetPath: string = ''): void {
    const resolved: string = targetPath.length > 0 ? targetPath : this.vm.selectedPath;
    if (resolved.length === 0) {
      this.toast($r('app.string.msg_no_note_selected'));
      return;
    }
    this.openDialog(DesignDialogKind.RENAME, resolved);
  }

  /** 打开移动目标目录选择对话框（无选中笔记时提示）。 */
  private openMoveDialog(targetPath: string = ''): void {
    const resolved: string = targetPath.length > 0 ? targetPath : this.vm.selectedPath;
    if (resolved.length === 0) {
      this.toast($r('app.string.msg_no_note_selected'));
      return;
    }
    this.openDialog(DesignDialogKind.MOVE, resolved);
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
    }).catch((error: BusinessError): void => {
      LOG.error(`move note failed, code=${error.code}, message=${error.message}`);
    });
  }

  // ==================== 快切 / 搜索 / 最近 / 命令面板 ====================

  /** 打开快速切换器（笔记跳转）。 */
  private openQuickSwitcher(): void {
    this.searchVm.loadNotes(this.vm.currentVault.id);
    this.animAssign((): void => {
      this.showQuickSwitcher = true;
    });
  }

  /** 打开分屏选择：复用快速切换器选择第二栏笔记。 */
  private openSplitPicker(): void {
    this.splitPickMode = true;
    this.searchVm.loadNotes(this.vm.currentVault.id);
    this.animAssign((): void => {
      this.showQuickSwitcher = true;
    });
  }

  /** 快速切换器选中笔记：分屏模式下进第二栏，否则直接打开。 */
  private openNoteFromQuickSwitcher(path: string): void {
    const splitPick: boolean = this.splitPickMode;
    this.animAssign((): void => {
      this.showQuickSwitcher = false;
      this.splitPickMode = false;
    });
    if (splitPick) {
      this.vm.openSecondary(path).catch((error: BusinessError): void => {
        LOG.error(`open secondary note failed, code=${error.code}, message=${error.message}`);
      });
      return;
    }
    this.openNoteFrom(path);
  }

  /** 打开全文搜索浮层并展示初始结果。 */
  private openSearchOverlay(): void {
    this.animAssign((): void => {
      this.showSearchOverlay = true;
    });
    this.searchVm.search(this.vm.currentVault.id, '').catch((error: BusinessError): void => {
      LOG.error(`search failed, code=${error.code}, message=${error.message}`);
    });
  }

  /** 打开最近访问浮层。 */
  private openRecentPanel(): void {
    this.vm.loadRecentNotes().catch((error: BusinessError): void => {
      LOG.error(`load recent notes failed, code=${error.code}, message=${error.message}`);
    });
    this.animAssign((): void => {
      this.showRecentPanel = true;
    });
  }

  /** 命令面板命令集（对标旧 buildCommands）。 */
  private buildCommands(): AppCommand[] {
    const commands: AppCommand[] = [];
    const search: AppCommand = new AppCommand();
    search.id = 'search';
    search.title = '搜索全文';
    search.action = (): void => {
      this.openSearchOverlay();
    };
    commands.push(search);

    const quick: AppCommand = new AppCommand();
    quick.id = 'quick';
    quick.title = '快速跳转到笔记';
    quick.action = (): void => {
      this.openQuickSwitcher();
    };
    commands.push(quick);

    const newNote: AppCommand = new AppCommand();
    newNote.id = 'new_note';
    newNote.title = '新建笔记';
    newNote.action = (): void => {
      this.vm.createNote().then((): void => {
        this.onNoteMutated();
      }).catch((error: BusinessError): void => {
        LOG.error(`create note failed, code=${error.code}, message=${error.message}`);
      });
    };
    commands.push(newNote);

    const recentNote: AppCommand = new AppCommand();
    recentNote.id = 'open_recent_note';
    recentNote.title = '最近访问的笔记';
    recentNote.action = (): void => {
      this.openRecentPanel();
    };
    commands.push(recentNote);

    const dailyNote: AppCommand = new AppCommand();
    dailyNote.id = 'open_daily_note';
    dailyNote.title = '打开今天的日记';
    dailyNote.action = (): void => {
      this.vm.openDailyNote().then((): void => {
        this.onNoteMutated();
      }).catch((error: BusinessError): void => {
        LOG.error(`open daily note failed, code=${error.code}, message=${error.message}`);
      });
    };
    commands.push(dailyNote);

    const exportCommand: AppCommand = new AppCommand();
    exportCommand.id = 'export';
    exportCommand.title = '导出仓库为 zip';
    exportCommand.action = (): void => {
      this.exportVault(this.vm.currentVault);
    };
    commands.push(exportCommand);

    const reindex: AppCommand = new AppCommand();
    reindex.id = 'reindex';
    reindex.title = '重建索引';
    reindex.action = (): void => {
      this.vm.rescanVault().then((): void => {
        this.toast($r('app.string.msg_reindex_done'));
      }).catch((error: BusinessError): void => {
        LOG.error(`rescan vault failed, code=${error.code}, message=${error.message}`);
      });
    };
    commands.push(reindex);

    return commands;
  }

  // ==================== 手写 / 回收站 / 仓库导入导出 ====================

  /** 保存手写内容为附件并插入编辑器（非编辑态先进入编辑，避免插入丢失）。 */
  private saveHandwrite(data: ArrayBuffer): void {
    this.vm.saveImageAttachment(data, 'png').then((relative: string): void => {
      this.animAssign((): void => {
        this.showHandwriteSheet = false;
      });
      if (relative.length === 0) {
        return;
      }
      const name: string = relative.substring(relative.lastIndexOf('/') + 1);
      const insert: string = `![[${name}]]`;
      if (this.vm.editMode) {
        this.vm.onInsertTextAtCaret(insert, false);
      } else {
        // 预览态下无编辑器：先进入编辑，待挂载完成后把图片追加到文末。
        this.vm.startEdit();
        setTimeout((): void => {
          this.vm.onInsertTextAtCaret(insert, true);
        }, 150);
      }
      this.toast($r('app.string.msg_handwrite_saved'));
    }).catch((error: BusinessError): void => {
      LOG.error(`save handwrite image failed, code=${error.code}, message=${error.message}`);
    });
  }

  /** 确认把指定（或当前）笔记移入回收站。 */
  private confirmTrashNote(targetPath: string = ''): void {
    const path: string = targetPath.length > 0 ? targetPath : this.vm.selectedPath;
    confirmTrashNoteAction(this.vm, path, (): void => {
      this.toast($r('app.string.msg_trash_done'));
      this.onNoteMutated();
      if (!this.isWide && this.vm.selectedPath.length === 0) {
        this.onRequestExit();
      }
    }, (msg: ResourceStr): void => {
      this.toast(msg);
    });
  }

  /** 确认删除文件夹并把其内容移入回收站。 */
  private confirmTrashFolder(dirPath: string): void {
    confirmTrashFolderAction(this.vm, dirPath, (): void => {
      this.toast($r('app.string.msg_trash_folder_done'));
      this.onNoteMutated();
      if (!this.isWide && this.vm.selectedPath.length === 0) {
        this.onRequestExit();
      }
    }, (msg: ResourceStr): void => {
      this.toast(msg);
    });
  }

  /** 导入 zip 仓库。 */
  private async importVault(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      const documentPicker = new picker.DocumentViewPicker(context);
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        return;
      }
      await this.vm.importVault(uris[0], 'imported');
      this.onNoteMutated();
    } catch (error) {
      const err = error as BusinessError;
      LOG.error(`import vault failed, code=${err.code}, message=${err.message}`);
      this.toast($r('app.string.msg_import_failed'));
    }
  }

  /** 导出仓库为 zip。 */
  private async exportVault(vault: VaultInfo): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      const documentPicker = new picker.DocumentViewPicker(context);
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [`${vault.name}.zip`];
      const uris: string[] = await documentPicker.save(options);
      if (uris.length === 0) {
        return;
      }
      await this.vm.exportVault(vault, uris[0]);
    } catch (error) {
      const err = error as BusinessError;
      LOG.error(`export vault failed, code=${err.code}, message=${err.message}`);
      this.toast($r('app.string.msg_export_failed'));
    }
  }

  /** 轻提示（使用 UIContext 的 PromptAction，避免全局 promptAction 的弃用告警）。 */
  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }
}
