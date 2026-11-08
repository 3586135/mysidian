import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { EmptyState, FileTreeView, Logger } from '@ohos/common';
import { MdDocumentView } from '@ohos/markdown';
import { NoteInfoPanel } from '../view/NoteInfoPanel';
import { SearchOverlay } from '../view/SearchOverlay';
import { QuickSwitcher } from '../view/QuickSwitcher';
import { CommandPalette } from '../view/CommandPalette';
import { SettingsOverlay } from '../view/SettingsOverlay';
import { SyncSettings } from '../view/SyncSettings';
import { AppCommand } from '../viewmodel/AppCommand';
import { SearchViewModel } from '../viewmodel/SearchViewModel';
import { SyncViewModel } from '../viewmodel/SyncViewModel';
import { VaultViewModel } from '../viewmodel/VaultViewModel';

const LOG: Logger = new Logger('MySidianPage');

@Entry
@ComponentV2
struct Index {
  @Local vm: VaultViewModel = new VaultViewModel();
  @Local searchVm: SearchViewModel = new SearchViewModel();
  @Local syncVm: SyncViewModel = new SyncViewModel();
  @Local isWide: boolean = false;
  @Local showCreatePanel: boolean = false;
  @Local showInfo: boolean = false;
  @Local showSearch: boolean = false;
  @Local showQuick: boolean = false;
  @Local showCommands: boolean = false;
  @Local showSync: boolean = false;
  @Local showSettings: boolean = false;
  @Local commandKeyword: string = '';
  @Local newVaultName: string = '';
  private commands: AppCommand[] = [];

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      LOG.error('host context is unavailable');
      return;
    }
    this.searchVm.setContext(context);
    this.vm.init(context);
    this.syncVm.init(context);
    this.commands = this.buildCommands();
  }

  build() {
    Column() {
      this.headerBar()
      if (this.vm.vaults.length === 0) {
        EmptyState({
          title: $r('app.string.vault_empty_title'),
          description: $r('app.string.vault_empty_desc')
        })
      } else {
        this.workspace()
      }
      if (this.showCreatePanel) {
        this.createPanel()
      }
      if (this.showSearch) {
        SearchOverlay({
          hits: this.searchVm.hits,
          keyword: this.searchVm.keyword,
          busy: this.searchVm.busy,
          onKeywordChange: (value: string): void => {
            this.searchVm.search(this.vm.currentVault.id, value);
          },
          onOpenNote: (path: string): void => {
            this.showSearch = false;
            this.vm.openNote(path);
          },
          onClose: (): void => {
            this.showSearch = false;
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
            this.showQuick = false;
            this.vm.openNote(path);
          },
          onClose: (): void => {
            this.showQuick = false;
          }
        })
      }
      if (this.showCommands) {
        CommandPalette({          commands: this.filteredCommands(),
          keyword: this.commandKeyword,
          onKeywordChange: (value: string): void => {
            this.commandKeyword = value;
          },
          onRun: (command: AppCommand): void => {
            this.showCommands = false;
            command.action();
          },
          onClose: (): void => {
            this.showCommands = false;
          }
        })
      }
      if (this.showSync) {
        SyncSettings({
          serverUrl: this.syncVm.serverUrl,
          username: this.syncVm.username,
          password: this.syncVm.password,
          remoteRoot: this.syncVm.remoteRoot,
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
          onAutoSyncChange: (value: boolean): void => {
            this.syncVm.autoSync = value;
          },
          onSyncNow: (): void => {
            this.syncVm.runSync(this.vm.currentVault);
          },
          onClose: (): void => {
            this.showSync = false;
          }
        })
      }
      if (this.showSettings) {
        SettingsOverlay({
          fontSize: this.vm.fontSize,
          onFontSizeChange: (size: number): void => {
            this.vm.setFontSize(size);
          },
          onReindex: (): void => {
            this.vm.rescanVault();
          },
          onExport: (): void => {
            this.exportVault();
          },
          onClose: (): void => {
            this.showSettings = false;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.isWide = newArea.width >= 600;
    })
  }

  @Builder
  headerBar() {
    Row() {
      Text($r('app.string.app_title'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
      Blank()
      Button($r('app.string.action_search'))
        .type(ButtonType.Normal)
        .margin({ right: 8 })
        .onClick(() => {
          this.openSearch();
        })
      Button($r('app.string.action_quick'))
        .type(ButtonType.Normal)
        .margin({ right: 8 })
        .onClick(() => {
          this.openQuickSwitcher();
        })
      Button($r('app.string.action_commands'))
        .type(ButtonType.Normal)
        .margin({ right: 8 })
        .onClick(() => {
          this.commandKeyword = '';
          this.showCommands = true;
        })
      Button($r('app.string.action_sync'))
        .type(ButtonType.Normal)
        .margin({ right: 8 })
        .onClick(() => {
          this.showSync = true;
        })
      Button($r('app.string.action_settings'))
        .type(ButtonType.Normal)
        .margin({ right: 8 })
        .onClick(() => {
          this.showSettings = true;
        })
      Button($r('app.string.action_import_vault'))
        .type(ButtonType.Normal)
        .margin({ right: 8 })
        .onClick(() => {
          this.importVault();
        })
      Button($r('app.string.action_create_vault'))
        .type(ButtonType.Normal)
        .onClick(() => {
          this.showCreatePanel = true;
          this.newVaultName = '';
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('sys.color.ohos_id_color_background'))
  }

  @Builder
  workspace() {
    if (this.isWide) {
      Row() {
        Column() {
          this.treePanel()
        }
        .width('28%')
        .height('100%')
        Column() {
          this.notePanel()
        }
        .layoutWeight(1)
        .height('100%')
        Column() {
          this.infoPanel()
        }
        .width('26%')
        .height('100%')
      }
      .width('100%')
      .layoutWeight(1)
    } else {
      if (this.vm.selectedPath.length === 0) {
        this.treePanel()
      } else {
        this.notePanel()
      }
    }
  }

  @Builder
  treePanel() {
    Column() {
      Row() {
        Text($r('app.string.file_tree_title'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Blank()
        Text(this.vm.currentVault.name)
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      FileTreeView({
        items: this.vm.treeItems,
        selectedPath: this.vm.selectedPath,
        onSelect: (path: string, isDir: boolean): void => {
          this.vm.openNote(path);
        },
        onToggle: (path: string): void => {
          this.vm.toggleDir(path);
        }
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  notePanel() {
    Column() {
      Row() {
        Text(this.vm.noteTitle)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (!this.isWide) {
          Button($r('app.string.action_back'))
            .type(ButtonType.Normal)
            .margin({ right: 8 })
            .onClick(() => {
              this.vm.closeNote();
            })
        }
        if (this.vm.editMode) {
          Button($r('app.string.action_cancel'))
            .type(ButtonType.Normal)
            .margin({ right: 8 })
            .onClick(() => {
              this.vm.cancelEdit();
            })
          Button($r('app.string.action_save'))
            .type(ButtonType.Normal)
            .onClick(() => {
              this.vm.saveDraft();
            })
        } else {
          Button($r('app.string.action_edit'))
            .type(ButtonType.Normal)
            .margin({ right: 8 })
            .onClick(() => {
              this.vm.startEdit();
            })
          if (!this.isWide) {
            Button($r('app.string.action_info'))
              .type(ButtonType.Normal)
              .onClick(() => {
                this.showInfo = !this.showInfo;
              })
          }
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      if (this.vm.editMode) {
        TextArea({
          placeholder: $r('app.string.action_edit'),
          text: this.vm.draftBuffer
        })
          .fontSize(15)
          .fontFamily('monospace')
          .width('100%')
          .layoutWeight(1)
          .onChange((value: string) => {
            this.vm.updateDraft(value);
          })
          .padding({ left: 12, right: 12 })
      } else {
        MdDocumentView({
          document: this.vm.document,
          fontSize: this.vm.fontSize,
          onOpenLink: (target: string, kind: string): void => {
            this.vm.openLink(target, kind);
          },
          onOpenTag: (tag: string): void => {
            this.vm.onTagSelected(tag);
          }
        })
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
        if (!this.isWide && this.showInfo) {
          Column() {
            this.infoPanel()
          }
          .width('100%')
          .height('45%')
        }
      }
    }
    .width('100%')
    .height('100%')
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
        this.vm.openNote(path);
      },
      onOpenTag: (tag: string): void => {
        this.vm.onTagSelected(tag);
      }
    })
  }

  @Builder
  createPanel() {
    Stack() {
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      .opacity(0.4)
      .onClick(() => {
        this.showCreatePanel = false;
      })

      Column() {
        Text($r('app.string.dialog_vault_name'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: 12 })
        TextInput({
          placeholder: $r('app.string.dialog_vault_name'),
          text: this.newVaultName
        })
          .onChange((value: string) => {
            this.newVaultName = value;
          })
          .margin({ bottom: 16 })
        Row() {
          Button($r('app.string.dialog_cancel'))
            .type(ButtonType.Normal)
            .margin({ right: 8 })
            .onClick(() => {
              this.showCreatePanel = false;
            })
          Button($r('app.string.dialog_confirm'))
            .type(ButtonType.Normal)
            .onClick(() => {
              this.showCreatePanel = false;
              this.createVault();
            })
        }
      }
      .width('80%')
      .padding(20)
      .borderRadius(12)
      .backgroundColor($r('sys.color.ohos_id_color_background'))
    }
    .width('100%')
    .height('100%')
  }

  private openSearch(): void {
    this.showSearch = true;
    this.searchVm.search(this.vm.currentVault.id, '');
  }

  private openQuickSwitcher(): void {
    this.showQuick = true;
    this.searchVm.loadNotes(this.vm.currentVault.id);
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

    const exportCommand: AppCommand = new AppCommand();
    exportCommand.id = 'export';
    exportCommand.title = '导出仓库为 zip';
    exportCommand.action = (): void => {
      this.exportVault();
    };
    commands.push(exportCommand);

    const reindex: AppCommand = new AppCommand();
    reindex.id = 'reindex';
    reindex.title = '重建索引';
    reindex.action = (): void => {
      this.vm.rescanVault();
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
      LOG.error('import vault failed');
      promptAction.showToast({ message: $r('app.string.msg_import_failed') });
    }
  }

  private async exportVault(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      const documentPicker = new picker.DocumentViewPicker(context);
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [`${this.vm.currentVault.name}.zip`];
      const uris: string[] = await documentPicker.save(options);
      if (uris.length === 0) {
        return;
      }
      await this.vm.exportVault(uris[0]);
    } catch (error) {
      LOG.error('export vault failed');
      promptAction.showToast({ message: $r('app.string.msg_export_failed') });
    }
  }

  private async createVault(): Promise<void> {
    try {
      await this.vm.createVault(this.newVaultName);
    } catch (error) {
      LOG.error('create vault failed');
      promptAction.showToast({ message: $r('app.string.msg_create_failed') });
    }
  }
}
