import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { EmptyState, FileTreeView, Logger } from '@ohos/common';
import { MdDocumentView } from '@ohos/markdown';
import { VaultViewModel } from '../viewmodel/VaultViewModel';

const LOG: Logger = new Logger('MySidianPage');

@Entry
@ComponentV2
struct Index {
  @Local vm: VaultViewModel = new VaultViewModel();
  @Local isWide: boolean = false;
  @Local showCreatePanel: boolean = false;
  @Local newVaultName: string = '';

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      LOG.error('host context is unavailable');
      return;
    }
    this.vm.init(context);
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
        .width('34%')
        .height('100%')
        Column() {
          this.notePanel()
        }
        .layoutWeight(1)
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
      if (this.vm.selectedPath.length === 0) {
        EmptyState({
          title: $r('app.string.note_empty_title'),
          description: $r('app.string.note_empty_desc')
        })
      } else {
        Row() {
          Text(this.vm.noteTitle)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank()
          if (!this.isWide) {
            Button($r('app.string.action_back'))
              .type(ButtonType.Normal)
              .onClick(() => {
                this.vm.closeNote();
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        MdDocumentView({
          document: this.vm.document,
          fontSize: 16,
          onOpenLink: (target: string, kind: string): void => {
            this.vm.openLink(target, kind);
          },
          onOpenTag: (tag: string): void => {
            promptAction.showToast({ message: `#${tag}` });
          }
        })
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
    .height('100%')
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

  private async createVault(): Promise<void> {
    try {
      await this.vm.createVault(this.newVaultName);
    } catch (error) {
      LOG.error('create vault failed');
      promptAction.showToast({ message: $r('app.string.msg_create_failed') });
    }
  }
}
