import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { VaultInfo } from '@ohos/domain';
import { Logger } from '@ohos/common';
import { VaultViewModel } from '../../viewmodel/VaultViewModel';

const LOG: Logger = new Logger('VaultManagerSheet');

/**
 * Material 3 仓库管理浮层：仓库卡片列表（打开 / 导出 / 删除）+
 * 导入 zip 与新建仓库入口。替代旧 vaultsTab 的全部能力。
 */
@ComponentV2
export struct VaultManagerSheet {
  @Param vm: VaultViewModel = new VaultViewModel();
  @Event onCreateVault: () => void = (): void => {};
  @Event onClose: () => void = (): void => {};

  build() {
    Stack() {
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.design_dim'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.Friction }))
      .onClick(() => {
        this.onClose();
      })

      Column() {
        Row() {
          Text($r('app.string.tab_vaults'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_text_primary'))
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.design_text_secondary')])
            .width(32)
            .height(32)
            .borderRadius(16)
            .backgroundColor($r('app.color.design_elevated'))
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .margin({ bottom: 10 })

        Scroll() {
          Column() {
            ForEach(this.vm.vaults, (vault: VaultInfo) => {
              this.vaultCard(vault)
            }, (vault: VaultInfo): string => `vault_${vault.id}_${vault.name}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        Row({ space: 8 }) {
          Button($r('app.string.action_import_vault_short'))
            .type(ButtonType.Capsule)
            .height(40)
            .fontSize(14)
            .layoutWeight(1)
            .backgroundColor($r('app.color.design_elevated'))
            .fontColor($r('app.color.design_text_primary'))
            .onClick(() => {
              this.importVault();
            })
          Button($r('app.string.action_create_vault_short'))
            .type(ButtonType.Capsule)
            .height(40)
            .fontSize(14)
            .layoutWeight(1)
            .backgroundColor($r('app.color.design_accent'))
            .fontColor($r('app.color.design_on_accent'))
            .onClick(() => {
              this.onCreateVault();
            })
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('90%')
      .height('72%')
      .constraintSize({ maxWidth: 520 })
      .padding(18)
      .borderRadius(28)
      .backgroundColor($r('app.color.design_surface_solid'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .shadow({ radius: 32, color: $r('app.color.design_shadow'), offsetY: 10 })
      .alignItems(HorizontalAlign.Start)
      .transition(TransitionEffect.scale({ x: 0.94, y: 0.94 })
        .combine(TransitionEffect.opacity(0))
        .animation({ duration: 220, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
  }

  /** 单个仓库卡片：名称 + 路径 + 当前标记 + 操作按钮。 */
  @Builder
  vaultCard(vault: VaultInfo) {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(20)
          .fontColor([$r('app.color.design_accent')])
        Text(vault.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 8 })
        if (vault.id === this.vm.currentVault.id) {
          Text($r('app.string.vault_card_current'))
            .fontSize(12)
            .fontColor($r('app.color.design_accent'))
            .backgroundColor($r('app.color.design_accent_weak'))
            .borderRadius(10)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .margin({ left: 8 })
        }
      }
      .width('100%')

      Text(vault.rootPath)
        .fontSize(12)
        .fontColor($r('app.color.design_text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4, left: 28 })

      Row({ space: 8 }) {
        if (vault.id !== this.vm.currentVault.id) {
          Button($r('app.string.vault_card_open'))
            .type(ButtonType.Capsule)
            .height(32)
            .fontSize(13)
            .backgroundColor($r('app.color.design_accent'))
            .fontColor($r('app.color.design_on_accent'))
            .onClick(() => {
              this.openVault(vault);
            })
        }
        Button($r('app.string.vault_card_export'))
          .type(ButtonType.Capsule)
          .height(32)
          .fontSize(13)
          .backgroundColor($r('app.color.design_elevated'))
          .fontColor($r('app.color.design_text_primary'))
          .onClick(() => {
            this.exportVault(vault);
          })
        Button($r('app.string.vault_card_delete'))
          .type(ButtonType.Capsule)
          .height(32)
          .fontSize(13)
          .backgroundColor($r('app.color.design_elevated'))
          .fontColor($r('app.color.design_danger'))
          .onClick(() => {
            this.confirmDeleteVault(vault);
          })
      }
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(14)
    .borderRadius(18)
    .backgroundColor($r('app.color.design_elevated'))
    .border({ width: 1, color: $r('app.color.design_stroke') })
    .margin({ top: 6, bottom: 6 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 打开仓库（切换后关闭浮层）。 */
  private async openVault(vault: VaultInfo): Promise<void> {
    try {
      await this.vm.selectVault(vault);
      this.onClose();
    } catch (error) {
      const err = error as BusinessError;
      LOG.error(`open vault failed, code=${err.code}, message=${err.message}`);
    }
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

  /** 删除仓库二次确认。 */
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
        fontColor: $r('app.color.design_danger'),
        action: (): void => {
          this.deleteVault(vault);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }

  /** 删除仓库。 */
  private async deleteVault(vault: VaultInfo): Promise<void> {
    try {
      await this.vm.deleteVault(vault);
    } catch (error) {
      const err = error as BusinessError;
      LOG.error(`delete vault failed, code=${err.code}, message=${err.message}`);
      this.toast($r('app.string.msg_delete_failed'));
    }
  }

  /** 轻提示（使用 UIContext 的 PromptAction，避免全局 promptAction 的弃用告警）。 */
  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }
}
