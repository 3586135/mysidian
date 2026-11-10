import { promptAction, window } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { HdsBarStyle, HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { EmptyState, FileTreeView, Logger } from '@ohos/common';
import { MdDocumentView, MdDocumentViewController } from '@ohos/markdown';
import { DataViewTask, OutlineEntry, VaultInfo } from '@ohos/domain';
import { NoteInfoPanel } from '../view/NoteInfoPanel';
import { SearchOverlay } from '../view/SearchOverlay';
import { QuickSwitcher } from '../view/QuickSwitcher';
import { RecentNotesPanel } from '../view/RecentNotesPanel';
import { CommandPalette } from '../view/CommandPalette';
import { SyncSettings } from '../view/SyncSettings';
import { AppCommand } from '../viewmodel/AppCommand';
import { SearchViewModel } from '../viewmodel/SearchViewModel';
import { SyncViewModel } from '../viewmodel/SyncViewModel';
import { VaultViewModel } from '../viewmodel/VaultViewModel';

const LOG: Logger = new Logger('MySidianPage');

/**
 * Material You 风格主界面（参考 FlClash 布局）：
 * 沉浸式状态栏 + 底部导航（窄屏）/ 侧边导航栏（宽屏）+ 大标题内容区 + 卡片 + FAB。
 */
@Entry
@ComponentV2
struct Index {
  @Local vm: VaultViewModel = new VaultViewModel();
  @Local searchVm: SearchViewModel = new SearchViewModel();
  @Local syncVm: SyncViewModel = new SyncViewModel();
  @Local isWide: boolean = false;
  @Local currentTab: number = 0;
  @Local topInset: number = 0;
  @Local bottomInset: number = 0;
  @Local showSideBar: boolean = true;
  @Local showRightPanel: boolean = true;
  @Local showInfo: boolean = false;
  @Local showCreatePanel: boolean = false;
  @Local showSearch: boolean = false;
  @Local showQuick: boolean = false;
  @Local showCommands: boolean = false;
  @Local showSync: boolean = false;
  @Local showVaults: boolean = false;
  @Local showRecent: boolean = false;
  /** 编辑工具栏显示状态。 */
  @Local showToolbar: boolean = false;
  /** 光标位置。 */
  @Local cursorPos: number = 0;
  private docController: MdDocumentViewController = new MdDocumentViewController();
  private tabsController: HdsTabsController = new HdsTabsController();
  @Local commandKeyword: string = '';
  @Local newVaultName: string = '';
  /** 新建仓库对话框：是否同时配置 WebDAV 同步。 */
  @Local createWithSync: boolean = true;
  @Local createSyncUrl: string = '';
  @Local createSyncUser: string = '';
  @Local createSyncPass: string = '';
  @Local createSyncRoot: string = 'mysidian';
  private commands: AppCommand[] = [];
  private autoSyncTimer: number = -1;
  private static readonly AUTO_SYNC_INTERVAL_MS: number = 30 * 60 * 1000;
  private swipeStartSidebarOpen: boolean = false;
  private swipeStartX: number = -1;
  private contentWidth: number = 0;
  /** 屏幕左右边缘系统返回手势保留区宽度（vp）。 */
  private static readonly EDGE_GESTURE_ZONE: number = 32;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      LOG.error('host context is unavailable');
      return;
    }
    this.searchVm.setContext(context);
    this.vm.attachUi(this.getUIContext());
    this.vm.init(context);
    this.syncVm.init(context).then((): void => {
      this.restartAutoSyncTimer();
    });
    this.syncVm.onSyncComplete = (): void => {
      // 同步拉取了新文件后重建索引并刷新文件树，使新笔记可见。
      this.vm.rescanVault();
    };
    this.commands = this.buildCommands();
    this.loadWindowInsets();
  }

  aboutToDisappear(): void {
    this.stopAutoSyncTimer();
  }

  build() {
    Stack() {
      if (this.isWide) {
        Row() {
          this.navRail()
          Stack({ alignContent: Alignment.BottomEnd }) {
            this.tabBody()
            if (this.currentTab === 0 && this.vm.vaults.length > 0) {
              this.fab(20)
            }
          }
          .layoutWeight(1)
          .height('100%')
        }
        .width('100%')
        .height('100%')
      } else {
        Stack({ alignContent: Alignment.BottomEnd }) {
          HdsTabs({ controller: this.tabsController }) {
            TabContent() {
              Column() {
                this.notesTab()
              }
              .width('100%')
              .height('100%')
              .padding({ bottom: 84 })
            }
            .tabBar(this.floatingTabItem(0, $r('app.string.tab_notes'), $r('sys.symbol.doc_plaintext')))

            TabContent() {
              Column() {
                this.settingsTab()
              }
              .width('100%')
              .height('100%')
              .padding({ bottom: 84 })
            }
            .tabBar(this.floatingTabItem(1, $r('app.string.tab_settings'), $r('sys.symbol.gearshape')))
          }
          .barOverlap(true)
          .barPosition(BarPosition.End)
          .vertical(false)
          .scrollable(false)
          .barFloatingStyle({
            barWidth: { smallWidth: 200, mediumWidth: 260, largeWidth: 320 },
            barBottomMargin: 16,
            systemMaterialEffect: {
              materialType: hdsMaterial.MaterialType.IMMERSIVE,
              materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
            },
            miniBar: {
              miniBarBuilder: (): void => {
                this.commandAnchor()
              },
              miniBarStyle: HdsBarStyle.EXPAND
            }
          })
          .onChange((index: number): void => {
            this.currentTab = index;
          })
          .width('100%')
          .height('100%')

          if (this.currentTab === 0 && this.vm.vaults.length > 0 && this.showSideBar) {
            this.fab(84)
          }
        }
        .width('100%')
        .height('100%')
      }

      if (this.showCreatePanel) {
        this.createPanel()
      }
      if (this.showSearch) {
        SearchOverlay({
          hits: this.searchVm.hits,
          keyword: this.searchVm.keyword,
          busy: this.searchVm.busy,
          searchMode: this.searchVm.searchMode,
          tagChips: this.searchVm.tagChips,
          activeTag: this.searchVm.activeTag,
          onKeywordChange: (value: string): void => {
            this.searchVm.search(this.vm.currentVault.id, value);
          },
          onModeChange: (mode: number): void => {
            this.searchVm.setMode(this.vm.currentVault.id, mode);
          },
          onSelectTag: (tag: string): void => {
            this.searchVm.selectTag(this.vm.currentVault.id, tag);
          },
          onOpenNote: (path: string): void => {
            this.animAssign((): void => {
              this.showSearch = false;
            });
            this.openNoteFrom(path);
          },
          onClose: (): void => {
            this.animAssign((): void => {
              this.showSearch = false;
            });
          }
        })
      }
      if (this.showQuick) {
        QuickSwitcher({
          items: this.searchVm.quickItems,
          keyword: this.searchVm.quickKeyword,
          onKeywordChange: (value: string): void => {
            this.searchVm.updateQuickKeyword(value);
          },
          onOpenNote: (path: string): void => {
            this.animAssign((): void => {
              this.showQuick = false;
            });
            this.openNoteFrom(path);
          },
          onClose: (): void => {
            this.animAssign((): void => {
              this.showQuick = false;
            });
          }
        })
      }
      if (this.showRecent) {
        RecentNotesPanel({
          items: this.vm.recentNotes,
          onOpenNote: (path: string): void => {
            this.animAssign((): void => {
              this.showRecent = false;
            });
            this.openNoteFrom(path);
          },
          onClose: (): void => {
            this.animAssign((): void => {
              this.showRecent = false;
            });
          }
        })
      }
      if (this.showCommands) {
        CommandPalette({
          commands: this.filteredCommands(),
          keyword: this.commandKeyword,
          onKeywordChange: (value: string): void => {
            this.commandKeyword = value;
          },
          onRun: (command: AppCommand): void => {
            this.animAssign((): void => {
              this.showCommands = false;
            });
            command.action();
          },
          onClose: (): void => {
            this.animAssign((): void => {
              this.showCommands = false;
            });
          }
        })
      }
      if (this.showSync) {
        SyncSettings({
          serverUrl: this.syncVm.serverUrl,
          username: this.syncVm.username,
          password: this.syncVm.password,
          remoteRoot: this.syncVm.remoteRoot,
          caCertPath: this.syncVm.caCertPath,
          skipCertVerify: this.syncVm.skipCertVerify,
          autoSync: this.syncVm.autoSync,
          statusText: this.syncVm.statusText(),
          conflicts: this.syncVm.conflicts,
          onServerUrlChange: (value: string): void => {
            this.syncVm.serverUrl = value;
          },
          onUsernameChange: (value: string): void => {
            this.syncVm.username = value;
          },
          onPasswordChange: (value: string): void => {
            this.syncVm.password = value;
          },
          onRemoteRootChange: (value: string): void => {
            this.syncVm.remoteRoot = value;
          },
          onImportCert: (): void => {
            this.pickCertFile();
          },
          onClearCert: (): void => {
            this.syncVm.clearCert();
          },
          onSkipCertChange: (value: boolean): void => {
            this.syncVm.skipCertVerify = value;
          },
          onAutoSyncChange: (value: boolean): void => {
            this.syncVm.autoSync = value;
            this.restartAutoSyncTimer();
          },
          onSyncNow: (): void => {
            this.syncVm.runSync(this.vm.currentVault);
          },
          onClose: (): void => {
            this.animAssign((): void => {
              this.showSync = false;
            });
          }
        })
      }
      if (this.showVaults) {
        Column() {
          this.vaultsTab()
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.hm_bg'))
        .transition(this.tabTransition())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.hm_bg'))
    .padding({
      top: this.topInset,
      bottom: this.bottomInset
    })
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.contentWidth = Number(newArea.width);
      const wide: boolean = newArea.width >= 600;
      if (wide !== this.isWide) {
        this.isWide = wide;
        if (wide) {
          this.showSideBar = true;
          this.showRightPanel = newArea.width >= 900;
        }
      }
    })
  }

  /** 宽度是否足以让信息面板与编辑器并排显示（否则信息面板悬浮覆盖）。 */
  private fixedPanelEnabled(): boolean {
    return this.contentWidth >= 900;
  }

  /** 是否以固定侧栏形式显示信息面板。 */
  private showFixedInfoPanel(): boolean {
    return this.showRightPanel && this.fixedPanelEnabled();
  }

  /** 当前页签内容（宽屏侧边导航使用）。 */
  @Builder
  tabBody() {
    if (this.currentTab === 0) {
      this.notesTab()
    } else {
      this.settingsTab()
    }
  }

  /** 宽屏左侧导航栏。 */
  @Builder
  navRail() {
    Column() {
      Column() {
        this.navItemContent(0, $r('app.string.tab_notes'), $r('sys.symbol.doc_plaintext'))
      }
      .width('100%')
      .height(64)
      .justifyContent(FlexAlign.Center)

      Column() {
        this.navItemContent(1, $r('app.string.tab_settings'), $r('sys.symbol.gearshape'))
      }
      .width('100%')
      .height(64)
      .justifyContent(FlexAlign.Center)
    }
    .width(88)
    .height('100%')
    .padding({ top: 4 })
  }

  /** 悬浮页签栏页签：图标（选中胶囊高亮）+ 文字。 */
  @Builder
  floatingTabItem(index: number, label: Resource, symbol: Resource) {
    Column({ space: 2 }) {
      Stack() {
        if (this.currentTab === index) {
          Column()
            .width(44)
            .height(26)
            .borderRadius(13)
            .backgroundColor($r('app.color.hm_selected_bg'))
            .transition(TransitionEffect.scale({ x: 0.4, y: 0.4 })
              .combine(TransitionEffect.opacity(0))
              .animation({ duration: 240, curve: Curve.Friction }))
        }
        SymbolGlyph(symbol)
          .fontSize(20)
          .fontColor([this.currentTab === index ? $r('app.color.hm_accent')
            : $r('app.color.hm_text_secondary')])
      }
      .width(44)
      .height(26)

      Text(label)
        .fontSize(10)
        .fontColor(this.currentTab === index ? $r('app.color.hm_accent')
          : $r('app.color.hm_text_secondary'))
        .maxLines(1)
    }
    .justifyContent(FlexAlign.Center)
  }

  /** 迷你栏命令入口：点击弹出候选命令菜单。 */
  @Builder
  commandAnchor() {
    Column() {
      SymbolGlyph($r('sys.symbol.circle_grid_2x2'))
        .fontSize(22)
        .fontColor([$r('app.color.hm_text_primary')])
    }
    .width(40)
    .height(40)
    .borderRadius(20)
    .backgroundColor($r('app.color.hm_hover_bg'))
    .justifyContent(FlexAlign.Center)
    .margin({ left: 4 })
    .bindMenu(this.commandMenuItems())
  }

  /** 迷你栏候选命令。 */
  private commandMenuItems(): MenuElement[] {
    const items: MenuElement[] = [];
    const back: MenuElement = {
      value: $r('app.string.menu_back_note'),
      action: (): void => {
        this.goBackFromBar();
      }
    };
    items.push(back);
    const recent: MenuElement = {
      value: $r('app.string.menu_recent_notes'),
      action: (): void => {
        this.openRecentPicker();
      }
    };
    items.push(recent);
    const daily: MenuElement = {
      value: $r('app.string.menu_daily_note'),
      action: (): void => {
        this.openDailyFromBar();
      }
    };
    items.push(daily);
    const create: MenuElement = {
      value: $r('app.string.menu_new_note'),
      action: (): void => {
        this.createNote();
      }
    };
    items.push(create);
    return items;
  }

  /** 导航项：图标（选中带胶囊高亮）+ 文字。 */
  @Builder
  navItemContent(index: number, label: Resource, symbol: Resource) {
    Column({ space: 2 }) {
      Stack() {
        if (this.currentTab === index) {
          Column()
            .width(44)
            .height(26)
            .borderRadius(13)
            .backgroundColor($r('app.color.hm_selected_bg'))
            .transition(TransitionEffect.scale({ x: 0.4, y: 0.4 })
              .combine(TransitionEffect.opacity(0))
              .animation({ duration: 240, curve: Curve.Friction }))
        }
        SymbolGlyph(symbol)
          .fontSize(20)
          .fontColor([this.currentTab === index ? $r('app.color.hm_accent')
            : $r('app.color.hm_text_secondary')])
      }
      .width(44)
      .height(26)

      Text(label)
        .fontSize(10)
        .fontColor(this.currentTab === index ? $r('app.color.hm_accent')
          : $r('app.color.hm_text_secondary'))
        .maxLines(1)
    }
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.getUIContext().animateTo({ duration: 300, curve: Curve.Friction }, (): void => {
        this.currentTab = index;
      });
    })
  }

  /** 页签切换过渡：淡入 + 轻微上移。 */
  private tabTransition(): TransitionEffect {
    return TransitionEffect.opacity(0)
      .combine(TransitionEffect.translate({ y: 12 }))
      .animation({ duration: 300, curve: Curve.Friction });
  }

  /** 在过渡动画中修改状态。 */
  private animAssign(action: () => void): void {
    this.getUIContext().animateTo({ duration: 240, curve: Curve.Friction }, action);
  }

  /** 笔记页签：文件列表 + 编辑器。 */
  @Builder
  notesTab() {
    if (this.vm.vaults.length === 0) {
      Column() {
        this.emptyVaultView()
      }
      .width('100%')
      .height('100%')
      .transition(this.tabTransition())
    } else if (this.isWide) {
      Stack() {
        Row() {
          Column() {
            this.notesHeader()
            FileTreeView({
              items: this.vm.treeItems,
              selectedPath: this.vm.selectedPath,
              selectedBgColor: $r('app.color.hm_selected_bg'),
              selectedTextColor: $r('app.color.hm_selected_text'),
              onSelect: (path: string, isDir: boolean): void => {
                this.openNoteFrom(path);
              },
              onToggle: (path: string): void => {
                this.vm.toggleDir(path);
              }
            })
          }
          .width(this.fixedPanelEnabled() ? 280 : 250)
          .height('100%')
          .backgroundColor($r('app.color.hm_bg'))

          Column() {
            this.editorArea()
          }
          .layoutWeight(1)
          .height('100%')
          .backgroundColor($r('app.color.hm_card_bg'))
          .borderRadius(16)
          .margin({ top: 12, bottom: 12, right: this.showFixedInfoPanel() ? 0 : 12 })
          .clip(true)

          if (this.showFixedInfoPanel()) {
            Column() {
              this.infoPanel()
            }
            .width(300)
            .height('100%')
            .backgroundColor($r('app.color.hm_card_bg'))
            .borderRadius(16)
            .margin({ top: 12, bottom: 12, right: 12 })
            .clip(true)
          }
        }
        .width('100%')
        .height('100%')

        if (this.showRightPanel && !this.fixedPanelEnabled()) {
          Column() {
            Row() {
              Blank()
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(18)
                .fontColor([$r('app.color.hm_text_secondary')])
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
              this.infoPanel()
            }
            .layoutWeight(1)
          }
          .width(360)
          .height('100%')
          .backgroundColor($r('app.color.hm_card_bg'))
          .border({ width: { left: 1 }, color: $r('app.color.hm_divider') })
          .shadow({ radius: 16, color: '#26000000', offsetX: -4 })
          .position({ x: '100%' })
          .markAnchor({ x: '100%' })
          .transition(TransitionEffect.translate({ x: '100%' })
            .animation({ duration: 260, curve: Curve.Friction }))
        }
      }
      .width('100%')
      .height('100%')
      .transition(this.tabTransition())
    } else {
      Stack() {
        SideBarContainer(SideBarContainerType.Overlay) {
          Column() {
            this.notesHeader()
            FileTreeView({
              items: this.vm.treeItems,
              selectedPath: this.vm.selectedPath,
              selectedBgColor: $r('app.color.hm_selected_bg'),
              selectedTextColor: $r('app.color.hm_selected_text'),
              onSelect: (path: string, isDir: boolean): void => {
                this.openNoteFrom(path);
              },
              onToggle: (path: string): void => {
                this.vm.toggleDir(path);
              }
            })
          }
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.hm_bg'))

          Column() {
            this.editorArea()
          }
          .width('100%')
          .height('100%')
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

        if (this.showInfo) {
          Column() {
            this.infoPanel()
          }
          .width('88%')
          .height('100%')
          .backgroundColor($r('app.color.hm_card_bg'))
          .border({ width: { left: 1 }, color: $r('app.color.hm_divider') })
          .shadow({ radius: 16, color: '#26000000', offsetX: -4 })
          .position({ x: '100%' })
          .markAnchor({ x: '100%' })
          .transition(TransitionEffect.translate({ x: '100%' })
            .animation({ duration: 260, curve: Curve.Friction }))
        }
      }
      .width('100%')
      .height('100%')
      .transition(this.tabTransition())
    }
  }

  /** 仓库管理浮层：仓库卡片列表（从设置页进入）。 */
  @Builder
  vaultsTab() {
    Scroll() {
      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([$r('app.color.hm_text_primary')])
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor($r('app.color.hm_hover_bg'))
            .onClick(() => {
              this.animAssign((): void => {
                this.showVaults = false;
              });
            })
          Text($r('app.string.tab_vaults'))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.hm_text_primary'))
            .layoutWeight(1)
            .margin({ left: 8 })
          Button($r('app.string.action_import_vault_short'))
            .type(ButtonType.Capsule)
            .height(36)
            .fontSize(14)
            .backgroundColor($r('app.color.hm_hover_bg'))
            .fontColor($r('app.color.hm_text_primary'))
            .margin({ right: 8 })
            .onClick(() => {
              this.importVault();
            })
          Button($r('app.string.action_create_vault_short'))
            .type(ButtonType.Capsule)
            .height(36)
            .fontSize(14)
            .backgroundColor($r('app.color.hm_accent'))
            .fontColor(Color.White)
            .onClick(() => {
              this.openCreatePanel();
            })
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 12 })
        .margin({ bottom: 4 })

        ForEach(this.vm.vaults, (vault: VaultInfo) => {
          this.vaultCard(vault)
        }, (vault: VaultInfo) => vault.id.toString())
      }
      .width('100%')
      .constraintSize({ maxWidth: 560 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .transition(this.tabTransition())
  }

  /** 单个仓库卡片。 */
  @Builder
  vaultCard(vault: VaultInfo) {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(20)
          .fontColor([$r('app.color.hm_accent')])
        Text(vault.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hm_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 8 })
        if (vault.id === this.vm.currentVault.id) {
          Text($r('app.string.vault_card_current'))
            .fontSize(12)
            .fontColor($r('app.color.hm_selected_text'))
            .backgroundColor($r('app.color.hm_selected_bg'))
            .borderRadius(10)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .margin({ left: 8 })
        }
      }
      .width('100%')

      Text(vault.rootPath)
        .fontSize(12)
        .fontColor($r('app.color.hm_text_hint'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4, left: 28 })

      Row({ space: 8 }) {
        if (vault.id !== this.vm.currentVault.id) {
          Button($r('app.string.vault_card_open'))
            .type(ButtonType.Capsule)
            .height(32)
            .fontSize(13)
            .backgroundColor($r('app.color.hm_accent'))
            .fontColor(Color.White)
            .onClick(() => {
              this.openVault(vault);
            })
        }
        Button($r('app.string.vault_card_export'))
          .type(ButtonType.Capsule)
          .height(32)
          .fontSize(13)
          .backgroundColor($r('app.color.hm_hover_bg'))
          .fontColor($r('app.color.hm_text_primary'))
          .onClick(() => {
            this.exportVault(vault);
          })
        Button($r('app.string.vault_card_delete'))
          .type(ButtonType.Capsule)
          .height(32)
          .fontSize(13)
          .backgroundColor($r('app.color.hm_hover_bg'))
          .fontColor($r('app.color.hm_danger'))
          .onClick(() => {
            this.confirmDeleteVault(vault);
          })
      }
      .margin({ top: 12 })
    }
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.hm_card_bg'))
    .margin({ left: 16, right: 16, top: 8 })
    .transition(TransitionEffect.opacity(0)
      .combine(TransitionEffect.translate({ y: 16 }))
      .animation({ duration: 300, curve: Curve.Friction }))
  }

  /** 设置页签：字号、维护、关于。 */
  @Builder
  settingsTab() {
    Scroll() {
      Column() {
        Row() {
          Text($r('app.string.tab_settings'))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.hm_text_primary'))
        }
        .width('100%')
        .height(56)
        .padding({ left: 16 })
        .margin({ bottom: 4 })

        Text($r('app.string.settings_appearance'))
          .fontSize(13)
          .fontColor($r('app.color.hm_text_hint'))
          .width('100%')
          .padding({ left: 28 })
          .margin({ top: 4 })

        Column() {
          Row() {
            Text($r('app.string.settings_font_size'))
              .fontSize(15)
              .fontColor($r('app.color.hm_text_primary'))
            Blank()
            Text(`${this.vm.fontSize} fp`)
              .fontSize(13)
              .fontColor($r('app.color.hm_text_secondary'))
              .margin({ right: 8 })
          }
          .width('100%')

          Slider({ value: this.vm.fontSize, min: 12, max: 28, step: 1 })
            .selectedColor($r('app.color.hm_accent'))
            .trackColor($r('app.color.hm_hover_bg'))
            .blockColor($r('app.color.hm_accent'))
            .width('100%')
            .margin({ top: 8 })
            .onChange((value: number) => {
              this.vm.setFontSize(Math.round(value));
            })
        }
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.hm_card_bg'))
        .margin({ left: 16, right: 16, top: 8 })

        Text($r('app.string.tab_vaults'))
          .fontSize(13)
          .fontColor($r('app.color.hm_text_hint'))
          .width('100%')
          .padding({ left: 28 })
          .margin({ top: 16 })

        Column() {
          Row() {
            SymbolGlyph($r('sys.symbol.folder'))
              .fontSize(18)
              .fontColor([$r('app.color.hm_accent')])
            Text($r('app.string.settings_vault_manage'))
              .fontSize(15)
              .fontColor($r('app.color.hm_text_primary'))
              .margin({ left: 8 })
              .layoutWeight(1)
            Text(this.vm.currentVault.name)
              .fontSize(13)
              .fontColor($r('app.color.hm_text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 140 })
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.hm_text_hint')])
              .margin({ left: 4 })
          }
          .width('100%')
          .onClick(() => {
            this.animAssign((): void => {
              this.showVaults = true;
            });
          })
        }
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.hm_card_bg'))
        .margin({ left: 16, right: 16, top: 8 })

        Text($r('app.string.settings_maintenance'))
          .fontSize(13)
          .fontColor($r('app.color.hm_text_hint'))
          .width('100%')
          .padding({ left: 28 })
          .margin({ top: 16 })

        Column() {
          Row() {
            Text($r('app.string.settings_reindex'))
              .fontSize(15)
              .fontColor($r('app.color.hm_text_primary'))
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(18)
              .fontColor([$r('app.color.hm_accent')])
          }
          .width('100%')
          .onClick(() => {
            this.reindexVault();
          })

          Divider()
            .color($r('app.color.hm_divider'))
            .margin({ top: 12, bottom: 12 })

          Row() {
            Text($r('app.string.sync_title'))
              .fontSize(15)
              .fontColor($r('app.color.hm_text_primary'))
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.hm_text_hint')])
          }
          .width('100%')
          .onClick(() => {
            this.animAssign((): void => {
              this.showSync = true;
            });
          })
        }
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.hm_card_bg'))
        .margin({ left: 16, right: 16, top: 8 })

        Text($r('app.string.settings_about'))
          .fontSize(13)
          .fontColor($r('app.color.hm_text_hint'))
          .lineHeight(20)
          .padding({ left: 28, right: 28 })
          .margin({ top: 16, bottom: 16 })
      }
      .width('100%')
      .constraintSize({ maxWidth: 560 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .transition(this.tabTransition())
  }

  /** 笔记列表头部：大标题 + 搜索 + 更多菜单。 */
  @Builder
  notesHeader() {
    Row() {
      Text(this.vm.currentVault.name.length > 0 ? this.vm.currentVault.name : $r('app.string.app_title'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.hm_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(22)
        .fontColor([$r('app.color.hm_text_primary')])
        .width(40)
        .height(40)
        .margin({ left: 4 })
        .onClick(() => {
          this.openSearch();
        })
      SymbolGlyph($r('sys.symbol.more'))
        .fontSize(22)
        .fontColor([$r('app.color.hm_text_primary')])
        .width(40)
        .height(40)
        .bindMenu(this.moreMenuBuilder)
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 4 })
    .alignItems(VerticalAlign.Center)
  }

  /** 更多菜单：高频操作入口。 */
  @Builder
  moreMenuBuilder() {
    Menu() {
      MenuItem({ content: $r('app.string.menu_quick_switch') })
        .onClick(() => {
          this.openQuickSwitcher();
        })
      MenuItem({ content: $r('app.string.menu_command_palette') })
        .onClick(() => {
          this.commandKeyword = '';
          this.animAssign((): void => {
            this.showCommands = true;
          });
        })
      MenuItem({ content: $r('app.string.action_new_note') })
        .onClick(() => {
          this.createNote();
        })
      MenuItem({ content: $r('app.string.action_import_vault') })
        .onClick(() => {
          this.importVault();
        })
      MenuItem({ content: $r('app.string.action_export_vault') })
        .onClick(() => {
          this.exportVault(this.vm.currentVault);
        })
    }
  }

  /** 新建笔记悬浮按钮。 */
  @Builder
  fab(bottomMargin: number) {
    Column() {
      SymbolGlyph($r('sys.symbol.square_and_pencil'))
        .fontSize(24)
        .fontColor([Color.White])
    }
    .width(56)
    .height(56)
    .borderRadius(28)
    .backgroundColor($r('app.color.hm_accent'))
    .shadow({ radius: 16, color: '#33000000', offsetY: 4 })
    .justifyContent(FlexAlign.Center)
    .margin({ right: 20, bottom: bottomMargin })
    .transition(TransitionEffect.scale({ x: 0, y: 0 })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 250, curve: Curve.Friction }))
    .onClick(() => {
      this.createNote();
    })
  }

  /** 仓库为空时的引导视图：欢迎区（偏上）+ 操作卡片。 */
  @Builder
  emptyVaultView() {
    Column() {
      Blank()
        .layoutWeight(1)

      Column() {
        Column() {
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(48)
            .fontColor([$r('app.color.hm_accent')])
        }
        .width(96)
        .height(96)
        .borderRadius(28)
        .backgroundColor($r('app.color.hm_hover_bg'))
        .justifyContent(FlexAlign.Center)

        Text($r('app.string.welcome_title'))
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.hm_text_primary'))
          .margin({ top: 24 })
        Text($r('app.string.welcome_desc'))
          .fontSize(14)
          .fontColor($r('app.color.hm_text_secondary'))
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)

      Blank()
        .layoutWeight(1.4)

      Column() {
        this.onboardRow($r('sys.symbol.square_and_pencil'), $r('app.string.onboard_create_title'),
          $r('app.string.onboard_create_desc'), 0)
        Divider()
          .color($r('app.color.hm_divider'))
        this.onboardRow($r('sys.symbol.folder'), $r('app.string.onboard_import_title'),
          $r('app.string.onboard_import_desc'), 1)
        Divider()
          .color($r('app.color.hm_divider'))
        this.onboardRow($r('sys.symbol.arrow_clockwise'), $r('app.string.onboard_sync_title'),
          this.syncVm.configured ? $r('app.string.onboard_sync_done')
            : $r('app.string.onboard_sync_desc'), 2)
      }
      .width('100%')
      .constraintSize({ maxWidth: 420 })
      .padding(6)
      .borderRadius(20)
      .backgroundColor($r('app.color.hm_card_bg'))
    }
    .width('100%')
    .height('100%')
    .padding(24)
  }

  /** 引导页操作行。action：0 新建仓库 / 1 导入仓库 / 2 WebDAV 同步。 */
  @Builder
  onboardRow(icon: Resource, title: ResourceStr, desc: ResourceStr, action: number) {
    Row() {
      Column() {
        SymbolGlyph(icon)
          .fontSize(22)
          .fontColor([$r('app.color.hm_accent')])
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor($r('app.color.hm_hover_bg'))
      .justifyContent(FlexAlign.Center)

      Column() {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hm_text_primary'))
          .maxLines(1)
        Text(desc)
          .fontSize(12)
          .fontColor($r('app.color.hm_text_secondary'))
          .maxLines(2)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12, right: 8 })

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('app.color.hm_text_hint')])
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 10, right: 14 })
    .borderRadius(16)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (action === 0) {
        this.openCreatePanel();
      } else if (action === 1) {
        this.importVault();
      } else {
        this.animAssign((): void => {
          this.showSync = true;
        });
      }
    })
  }

  /** 编辑器区域：标题栏 + 正文。 */
  @Builder
  editorArea() {
    Column() {
      if (this.vm.selectedPath.length === 0) {
        EmptyState({
          title: $r('app.string.note_empty_title'),
          description: $r('app.string.note_empty_desc'),
          icon: $r('sys.symbol.doc_plaintext'),
          iconColor: $r('app.color.hm_text_secondary')
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
          TextArea({
            placeholder: $r('app.string.editor_placeholder'),
            text: this.vm.draftBuffer
          })
            .fontSize(16)
            .width('100%')
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.hm_text_primary'))
            .placeholderColor($r('app.color.hm_text_secondary'))
            .caretColor($r('app.color.hm_accent'))
            .padding({ left: 20, right: 20, top: 8, bottom: 8 })
            .onTouch((event: TouchEvent) => {
              this.onContentTouch(event);
            })
            .onFocus(() => {
              this.cursorPos = this.vm.draftBuffer.length;
              this.showToolbar = true;
            })
            .onBlur(() => {
              this.showToolbar = false;
            })
            .onChange((value: string) => {
              this.vm.updateDraft(value);
            })
            .transition(TransitionEffect.opacity(0)
              .animation({ duration: 200, curve: Curve.Friction }))
            if (this.showToolbar && this.vm.editMode) {
              this.editToolbar()
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
              this.openTagSearch(tag);
            },
            onToggleTask: (rawLine: string, checked: boolean): void => {
              this.vm.toggleTask(rawLine, checked).then((): void => {
                this.syncNowIfAuto();
              });
            },
            onLoadDataView: (query: string,
              onResult: (tasks: DataViewTask[]) => void): void => {
              this.vm.runDataViewQuery(query).then((tasks: DataViewTask[]): void => {
                onResult(tasks);
              });
            },
            onToggleDataViewTask: (task: DataViewTask, checked: boolean): void => {
              this.vm.toggleTaskInNote(task, checked).then((): void => {
                this.syncNowIfAuto();
              });
            }
          })
          .layoutWeight(1)
          .padding({ left: 20, right: 20 })
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
    .gesture(PanGesture({ fingers: 1, direction: PanDirection.Horizontal })
      .onActionStart((event: GestureEvent) => {
        this.swipeStartSidebarOpen = this.showSideBar;
        this.swipeStartX = event.fingerList.length > 0 ? event.fingerList[0].globalX : -1;
      })
      .onActionEnd((event: GestureEvent) => {
        if (this.isEdgeSwipe()) {
          return;
        }
        this.handleContentSwipe(event.offsetX);
      }))
  }

  /** 起点位于屏幕左右边缘保留区内的滑动交给系统返回手势处理。 */
  private isEdgeSwipe(): boolean {
    if (this.swipeStartX < 0 || !(this.contentWidth > 0)) {
      return false;
    }
    return this.swipeStartX < Index.EDGE_GESTURE_ZONE ||
      this.swipeStartX > this.contentWidth - Index.EDGE_GESTURE_ZONE;
  }

  /** 正文触摸：按下即收起窄屏弹层（信息面板 / 文件侧栏）。 */
  private onContentTouch(event: TouchEvent): void {
    if (event.type !== TouchType.Down) {
      return;
    }
    this.dismissOverlays();
  }

  /** 收起窄屏弹层：大纲反链面板与文档目录侧栏。 */
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

  /** 正文区横向滑动：向右滑呼出文件侧栏，向左滑查看双链。 */
  private handleContentSwipe(offsetX: number): void {
    if (offsetX > 60) {
      if (!this.isWide && this.showInfo) {
        this.animAssign((): void => {
          this.showInfo = false;
        });
        return;
      }
      if (this.isWide || this.swipeStartSidebarOpen) {
        return;
      }
      this.animAssign((): void => {
        this.showSideBar = true;
      });
    } else if (offsetX < -60) {
      if (!this.isWide && this.swipeStartSidebarOpen) {
        this.animAssign((): void => {
          this.showSideBar = false;
        });
        return;
      }
      this.openBacklinks();
    }
  }

  /** 打开双链信息（窄屏底部面板 / 宽屏右侧面板）。 */
  private openBacklinks(): void {
    if (this.isWide) {
      if (this.showRightPanel) {
        return;
      }
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

  /** 编辑器标题栏：返回 + 笔记标题 + 编辑操作。 */
  @Builder
  editorHeader() {
    Row() {
      if (!this.isWide) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([$r('app.color.hm_text_primary')])
          .width(36)
          .height(36)
          .margin({ left: -8 })
          .onClick(() => {
            this.animAssign((): void => {
              this.showSideBar = true;
            });
          })
      }
      Text(this.vm.noteTitle)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.hm_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.vm.editMode) {
        Text($r('app.string.action_cancel'))
          .fontSize(15)
          .fontColor($r('app.color.hm_text_secondary'))
          .height(36)
          .padding({ left: 8, right: 8 })
          .margin({ left: 4 })
          .onClick(() => {
            this.vm.cancelEdit();
          })
        Text($r('app.string.action_save'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hm_accent'))
          .height(36)
          .padding({ left: 8, right: 8 })
          .margin({ left: 4 })
          .onClick(() => {
            this.vm.saveDraft().then((): void => {
              this.syncNowIfAuto();
            });
          })
      } else {
        SymbolGlyph($r('sys.symbol.doc_plaintext_and_pencil'))
          .fontSize(20)
          .fontColor([$r('app.color.hm_text_primary')])
          .width(36)
          .height(36)
          .margin({ left: 4 })
          .onClick(() => {
            this.vm.startEdit();
          })
        if (this.isWide) {
          SymbolGlyph($r('sys.symbol.rectangle_grid_1x2'))
            .fontSize(20)
            .fontColor([$r('app.color.hm_text_primary')])
            .width(36)
            .height(36)
            .margin({ left: 4 })
            .onClick(() => {
              this.animAssign((): void => {
                this.showRightPanel = !this.showRightPanel;
              });
            })
        } else {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(20)
            .fontColor([$r('app.color.hm_text_primary')])
            .width(36)
            .height(36)
            .margin({ left: 4 })
            .onClick(() => {
              this.animAssign((): void => {
                this.showInfo = !this.showInfo;
              });
            })
        }
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  /** 在光标处插入 Markdown 语法。 */
  private insertFormat(syntax: string): void {
    const text: string = this.vm.draftBuffer;
    const pos: number = this.cursorPos;
    const before: string = text.slice(0, pos);
    const after: string = text.slice(pos);
    this.vm.updateDraft(before + syntax + after);
  }

  /** 编辑模式底部格式化工具栏。 */
  @Builder
  editToolbar() {
    Row() {
      Button('B')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .height(32)
        .padding({ left: 10, right: 10 })
        .backgroundColor($r('app.color.hm_hover_bg'))
        .borderRadius(6)
        .onClick(() => {
          this.insertFormat('**');
        })
      Button('I')
        .fontSize(14)
        .height(32)
        .padding({ left: 10, right: 10 })
        .backgroundColor($r('app.color.hm_hover_bg'))
        .borderRadius(6)
        .onClick(() => {
          this.insertFormat('*');
        })
      Button('~')
        .fontSize(14)
        .height(32)
        .padding({ left: 10, right: 10 })
        .backgroundColor($r('app.color.hm_hover_bg'))
        .borderRadius(6)
        .onClick(() => {
          this.insertFormat('~~');
        })
      Button('`')
        .fontSize(14)
        .height(32)
        .padding({ left: 10, right: 10 })
        .backgroundColor($r('app.color.hm_hover_bg'))
        .borderRadius(6)
        .onClick(() => {
          this.insertFormat('`');
        })
      Button('H1')
        .fontSize(13)
        .height(32)
        .padding({ left: 8, right: 8 })
        .backgroundColor($r('app.color.hm_hover_bg'))
        .borderRadius(6)
        .onClick(() => {
          this.insertFormat('# ');
        })
      Button('H2')
        .fontSize(13)
        .height(32)
        .padding({ left: 8, right: 8 })
        .backgroundColor($r('app.color.hm_hover_bg'))
        .borderRadius(6)
        .onClick(() => {
          this.insertFormat('## ');
        })
      Button('H3')
        .fontSize(13)
        .height(32)
        .padding({ left: 8, right: 8 })
        .backgroundColor($r('app.color.hm_hover_bg'))
        .borderRadius(6)
        .onClick(() => {
          this.insertFormat('### ');
        })
      Button('>')
        .fontSize(14)
        .height(32)
        .padding({ left: 10, right: 10 })
        .backgroundColor($r('app.color.hm_hover_bg'))
        .borderRadius(6)
        .onClick(() => {
          this.insertFormat('> ');
        })
      Button('-')
        .fontSize(14)
        .height(32)
        .padding({ left: 10, right: 10 })
        .backgroundColor($r('app.color.hm_hover_bg'))
        .borderRadius(6)
        .onClick(() => {
          this.insertFormat('- ');
        })
      Button('1.')
        .fontSize(13)
        .height(32)
        .padding({ left: 8, right: 8 })
        .backgroundColor($r('app.color.hm_hover_bg'))
        .borderRadius(6)
        .onClick(() => {
          this.insertFormat('1. ');
        })
      Button('-[]')
        .fontSize(12)
        .height(32)
        .padding({ left: 8, right: 8 })
        .backgroundColor($r('app.color.hm_hover_bg'))
        .borderRadius(6)
        .onClick(() => {
          this.insertFormat('- [ ] ');
        })
      Button('—')
        .fontSize(14)
        .height(32)
        .padding({ left: 10, right: 10 })
        .backgroundColor($r('app.color.hm_hover_bg'))
        .borderRadius(6)
        .onClick(() => {
          this.insertFormat('---\n');
        })
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .width('100%')
    .backgroundColor($r('app.color.hm_card_bg'))
    .border({ width: { top: 1 }, color: $r('app.color.hm_divider') })
  }

  @Builder
  infoPanel() {
    NoteInfoPanel({
      outlineEntries: this.vm.outline,
      backlinks: this.vm.backlinks,
      tags: this.vm.noteTags,
      properties: this.vm.noteProperties,
      currentTab: this.vm.infoTabIndex,
      onTabChange: (index: number): void => {
        this.vm.setInfoTab(index);
      },
      onOpenNote: (path: string): void => {
        this.openNoteFrom(path);
      },
      onOpenTag: (tag: string): void => {
        this.openTagSearch(tag);
      },
      onOutlineClick: (entry: OutlineEntry): void => {
        this.scrollToOutlineEntry(entry);
      }
    })
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

  /** 新建仓库对话框：命名 + 可选 WebDAV 同步配置。 */
  @Builder
  createPanel() {
    Stack() {
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.hm_mask'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .transition(TransitionEffect.opacity(0)
        .animation({ duration: 220, curve: Curve.Friction }))
      .onClick(() => {
        this.animAssign((): void => {
          this.showCreatePanel = false;
        });
      })

      Column() {
        Text($r('app.string.dialog_vault_name'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hm_text_primary'))
          .width('100%')
          .margin({ bottom: 12 })

        Scroll() {
          Column() {
            TextInput({
              placeholder: $r('app.string.dialog_vault_name'),
              text: this.newVaultName
            })
              .width('100%')
              .height(44)
              .fontSize(16)
              .padding({ left: 14, right: 14 })
              .borderRadius(12)
              .backgroundColor($r('app.color.hm_input_bg'))
              .placeholderColor($r('app.color.hm_text_secondary'))
              .fontColor($r('app.color.hm_text_primary'))
              .caretColor($r('app.color.hm_accent'))
              .onChange((value: string) => {
                this.newVaultName = value;
              })
              .margin({ bottom: 12 })

            Row() {
              Column() {
                Text($r('app.string.dialog_create_with_sync'))
                  .fontSize(14)
                  .fontColor($r('app.color.hm_text_primary'))
                Text($r('app.string.dialog_create_with_sync_desc'))
                  .fontSize(12)
                  .fontColor($r('app.color.hm_text_secondary'))
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Toggle({ type: ToggleType.Switch, isOn: this.createWithSync })
                .selectedColor($r('app.color.hm_accent'))
                .onChange((isOn: boolean) => {
                  this.createWithSync = isOn;
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ bottom: 4 })

            if (this.createWithSync) {
              this.createFieldLabel($r('app.string.sync_server'))
              this.createFieldInput($r('app.string.sync_server_placeholder'),
                this.createSyncUrl, InputType.Normal, (value: string): void => {
                  this.createSyncUrl = value;
                })
              this.createFieldLabel($r('app.string.sync_username'))
              this.createFieldInput($r('app.string.sync_username_placeholder'),
                this.createSyncUser, InputType.Normal, (value: string): void => {
                  this.createSyncUser = value;
                })
              this.createFieldLabel($r('app.string.sync_password'))
              this.createFieldInput($r('app.string.sync_password_placeholder'),
                this.createSyncPass, InputType.Password, (value: string): void => {
                  this.createSyncPass = value;
                })
              this.createFieldLabel($r('app.string.sync_root'))
              this.createFieldInput($r('app.string.sync_root_placeholder'),
                this.createSyncRoot, InputType.Normal, (value: string): void => {
                  this.createSyncRoot = value;
                })
            }
          }
          .width('100%')
        }
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .constraintSize({ maxHeight: 320 })

        Row() {
          Button($r('app.string.dialog_cancel'))
            .type(ButtonType.Capsule)
            .height(40)
            .fontSize(16)
            .backgroundColor($r('app.color.hm_hover_bg'))
            .fontColor($r('app.color.hm_text_primary'))
            .layoutWeight(1)
            .margin({ right: 12 })
            .onClick(() => {
              this.animAssign((): void => {
                this.showCreatePanel = false;
              });
            })
          Button($r('app.string.dialog_create'))
            .type(ButtonType.Capsule)
            .height(40)
            .fontSize(16)
            .backgroundColor($r('app.color.hm_accent'))
            .fontColor(Color.White)
            .layoutWeight(1)
            .onClick(() => {
              this.animAssign((): void => {
                this.showCreatePanel = false;
              });
              this.createVault();
            })
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('84%')
      .padding(24)
      .borderRadius(24)
      .backgroundColor($r('app.color.hm_card_bg'))
      .transition(TransitionEffect.scale({ x: 0.9, y: 0.9 })
        .combine(TransitionEffect.opacity(0))
        .animation({ duration: 220, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
  }

  /** 新建对话框字段标签。 */
  @Builder
  createFieldLabel(label: ResourceStr) {
    Text(label)
      .fontSize(12)
      .fontColor($r('app.color.hm_text_secondary'))
      .width('100%')
      .margin({ top: 8, bottom: 6 })
  }

  /** 新建对话框字段输入框。 */
  @Builder
  createFieldInput(placeholder: ResourceStr, text: string, inputType: InputType,
    onChange: (value: string) => void) {
    TextInput({
      placeholder: placeholder,
      text: text
    })
      .type(inputType)
      .width('100%')
      .height(42)
      .fontSize(15)
      .padding({ left: 12, right: 12 })
      .borderRadius(10)
      .backgroundColor($r('app.color.hm_input_bg'))
      .placeholderColor($r('app.color.hm_text_secondary'))
      .fontColor($r('app.color.hm_text_primary'))
      .caretColor($r('app.color.hm_accent'))
      .onChange((value: string) => {
        onChange(value);
      })
  }

  private loadWindowInsets(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    window.getLastWindow(context).then((win: window.Window) => {
      const system = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const nav = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.topInset = this.getUIContext().px2vp(system.topRect.height);
      this.bottomInset = this.getUIContext().px2vp(nav.bottomRect.height);
    }).catch((error: BusinessError) => {
      LOG.error(`get window insets failed, code=${error.code}, message=${error.message}`);
    });
  }

  private openNoteFrom(path: string): void {
    this.vm.openNote(path);
    this.animAssign((): void => {
      this.showInfo = false;
      if (!this.isWide) {
        this.showSideBar = false;
      }
    });
  }

  private openVault(vault: VaultInfo): void {
    this.vm.selectVault(vault);
    this.currentTab = 0;
    if (!this.isWide) {
      this.tabsController.changeIndex(0);
    }
    this.animAssign((): void => {
      this.showVaults = false;
    });
  }

  private createNote(): void {
    this.vm.createNote().then((): void => {
      this.syncNowIfAuto();
    });
  }

  /** 自动同步开启时立即触发一次同步（保存 / 新建后调用）。 */
  private syncNowIfAuto(): void {
    if (!this.syncVm.autoSync || this.syncVm.serverUrl.length === 0) {
      return;
    }
    this.syncVm.runSync(this.vm.currentVault);
  }

  /** 依据自动同步开关重建周期同步定时器。 */
  private restartAutoSyncTimer(): void {
    this.stopAutoSyncTimer();
    if (!this.syncVm.autoSync || this.syncVm.serverUrl.length === 0) {
      return;
    }
    this.autoSyncTimer = setInterval((): void => {
      this.syncNowIfAuto();
    }, Index.AUTO_SYNC_INTERVAL_MS);
  }

  private stopAutoSyncTimer(): void {
    if (this.autoSyncTimer >= 0) {
      clearInterval(this.autoSyncTimer);
      this.autoSyncTimer = -1;
    }
  }

  private openSearch(): void {
    this.animAssign((): void => {
      this.showSearch = true;
    });
    this.searchVm.search(this.vm.currentVault.id, '');
  }

  /** 点击标签：以标签模式打开搜索并直接展示该标签的笔记。 */
  private openTagSearch(tag: string): void {
    this.animAssign((): void => {
      this.showSearch = true;
    });
    this.searchVm.setMode(this.vm.currentVault.id, 1).then((): void => {
      this.searchVm.selectTag(this.vm.currentVault.id, tag);
    });
  }

  /** 系统返回：依次关闭浮层 → 返回上一笔记 → 窄屏唤出目录 → 默认退出。 */
  onBackPress(): boolean {
    if (this.showSearch) {
      this.animAssign((): void => {
        this.showSearch = false;
      });
      return true;
    }
    if (this.showQuick) {
      this.animAssign((): void => {
        this.showQuick = false;
      });
      return true;
    }
    if (this.showRecent) {
      this.animAssign((): void => {
        this.showRecent = false;
      });
      return true;
    }
    if (this.showCommands) {
      this.animAssign((): void => {
        this.showCommands = false;
      });
      return true;
    }
    if (this.showSync) {
      this.animAssign((): void => {
        this.showSync = false;
      });
      return true;
    }
    if (this.showVaults) {
      this.animAssign((): void => {
        this.showVaults = false;
      });
      return true;
    }
    if (this.showCreatePanel) {
      this.animAssign((): void => {
        this.showCreatePanel = false;
      });
      return true;
    }
    if (this.isWide && this.showRightPanel && !this.fixedPanelEnabled()) {
      this.animAssign((): void => {
        this.showRightPanel = false;
      });
      return true;
    }
    if (this.vm.editMode) {
      this.vm.cancelEdit();
      return true;
    }
    if (!this.isWide && this.showInfo) {
      this.animAssign((): void => {
        this.showInfo = false;
      });
      return true;
    }
    if (!this.isWide && this.showSideBar) {
      this.animAssign((): void => {
        this.showSideBar = false;
      });
      return true;
    }
    if (this.vm.canGoBackNote()) {
      this.vm.goBackNote();
      return true;
    }
    if (!this.isWide && this.vm.selectedPath.length > 0 && !this.showSideBar) {
      this.animAssign((): void => {
        this.showSideBar = true;
      });
      return true;
    }
    return false;
  }

  private openQuickSwitcher(): void {
    this.animAssign((): void => {
      this.showQuick = true;
    });
    this.searchVm.loadNotes(this.vm.currentVault.id);
  }

  /** 迷你栏：返回上一封笔记。 */
  private goBackFromBar(): void {
    if (!this.vm.canGoBack) {
      return;
    }
    this.vm.goBackNote();
  }

  /** 迷你栏：打开最近访问选择器。 */
  private openRecentPicker(): void {
    this.switchToNotesTab();
    this.vm.loadRecentNotes();
    this.animAssign((): void => {
      this.showRecent = true;
    });
  }

  /** 迷你栏：打开今天的日记（不存在则新建）。 */
  private openDailyFromBar(): void {
    this.switchToNotesTab();
    this.vm.openDailyNote().then((): void => {
      this.syncNowIfAuto();
    });
  }

  /** 切回笔记页签并联动 HdsTabs。 */
  private switchToNotesTab(): void {
    if (this.currentTab === 0) {
      return;
    }
    this.currentTab = 0;
    if (!this.isWide) {
      this.tabsController.changeIndex(0);
    }
  }

  private reindexVault(): void {
    this.vm.rescanVault();
    promptAction.showToast({ message: $r('app.string.msg_reindex_done') });
  }

  private confirmDeleteVault(vault: VaultInfo): void {
    AlertDialog.show({
      title: $r('app.string.dialog_delete_vault_title'),
      message: $r('app.string.dialog_delete_vault_msg'),
      primaryButton: {
        value: $r('app.string.dialog_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.vault_card_delete'),
        fontColor: $r('app.color.hm_danger'),
        action: (): void => {
          this.deleteVault(vault);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  private buildCommands(): AppCommand[] {
    const commands: AppCommand[] = [];
    const search: AppCommand = new AppCommand();
    search.id = 'search';
    search.title = '搜索全文';
    search.action = (): void => {
      this.openSearch();
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
      this.createNote();
    };
    commands.push(newNote);

    const recentNote: AppCommand = new AppCommand();
    recentNote.id = 'open_recent_note';
    recentNote.title = '最近访问的笔记';
    recentNote.action = (): void => {
      this.openRecentPicker();
    };
    commands.push(recentNote);

    const dailyNote: AppCommand = new AppCommand();
    dailyNote.id = 'open_daily_note';
    dailyNote.title = '打开今天的日记';
    dailyNote.action = (): void => {
      this.openDailyFromBar();
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
      this.reindexVault();
    };
    commands.push(reindex);

    return commands;
  }

  private filteredCommands(): AppCommand[] {
    const keyword: string = this.commandKeyword.trim().toLowerCase();
    if (keyword.length === 0) {
      return this.commands;
    }
    const result: AppCommand[] = [];
    for (const command of this.commands) {
      if (command.title.toLowerCase().includes(keyword)) {
        result.push(command);
      }
    }
    return result;
  }

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
    } catch (error) {
      const err = error as BusinessError;
      LOG.error(`import vault failed, code=${err.code}, message=${err.message}`);
      promptAction.showToast({ message: $r('app.string.msg_import_failed') });
    }
  }

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
      promptAction.showToast({ message: $r('app.string.msg_export_failed') });
    }
  }

  private async deleteVault(vault: VaultInfo): Promise<void> {
    try {
      await this.vm.deleteVault(vault);
    } catch (error) {
      const err = error as BusinessError;
      LOG.error(`delete vault failed, code=${err.code}, message=${err.message}`);
      promptAction.showToast({ message: $r('app.string.msg_delete_failed') });
    }
  }

  private async pickCertFile(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      const documentPicker = new picker.DocumentViewPicker(context);
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.pem', '.crt', '.cer'];
      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        return;
      }
      const ok: boolean = await this.syncVm.importCert(uris[0]);
      if (!ok) {
        promptAction.showToast({ message: $r('app.string.msg_cert_import_failed') });
      }
    } catch (error) {
      const err = error as BusinessError;
      LOG.error(`pick cert failed, code=${err.code}, message=${err.message}`);
    }
  }

  private async createVault(): Promise<void> {
    try {
      await this.vm.createVault(this.newVaultName);
      await this.applyCreateSyncConfig();
    } catch (error) {
      const err = error as BusinessError;
      LOG.error(`create vault failed, code=${err.code}, message=${err.message}`);
      promptAction.showToast({ message: $r('app.string.msg_create_failed') });
    }
  }

  /** 打开新建仓库对话框：首个仓库预填示例名与已有 WebDAV 配置，默认开启同步配置。 */
  private openCreatePanel(): void {
    this.newVaultName = this.vm.vaults.length === 0 ? '示例仓库' : '';
    this.createWithSync = true;
    this.createSyncUrl = this.syncVm.serverUrl;
    this.createSyncUser = this.syncVm.username;
    this.createSyncPass = this.syncVm.password;
    this.createSyncRoot = this.syncVm.remoteRoot.length > 0 ? this.syncVm.remoteRoot : 'mysidian';
    this.animAssign((): void => {
      this.showCreatePanel = true;
    });
  }

  /** 新建仓库时同时保存 WebDAV 配置，启用自动同步并触发首次同步。 */
  private async applyCreateSyncConfig(): Promise<void> {
    const url: string = this.createSyncUrl.trim();
    if (!this.createWithSync || url.length === 0) {
      return;
    }
    this.syncVm.serverUrl = url;
    this.syncVm.username = this.createSyncUser.trim();
    this.syncVm.password = this.createSyncPass;
    const root: string = this.createSyncRoot.trim();
    this.syncVm.remoteRoot = root.length > 0 ? root : 'mysidian';
    this.syncVm.autoSync = true;
    await this.syncVm.save();
    this.restartAutoSyncTimer();
    promptAction.showToast({ message: $r('app.string.msg_sync_config_saved') });
    await this.syncVm.runSync(this.vm.currentVault);
  }
}
