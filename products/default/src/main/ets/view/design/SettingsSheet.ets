import { VaultViewModel } from '../../viewmodel/VaultViewModel';

/**
 * Material 3 设置浮层：字号 Slider、仓库管理入口、维护操作（重建索引 / 导出）、
 * WebDAV 同步入口与关于说明。替代旧 settingsTab 的全部能力。
 */
@ComponentV2
export struct SettingsSheet {
  @Param vm: VaultViewModel = new VaultViewModel();
  @Event onClose: () => void = (): void => {};
  @Event onOpenVaultManager: () => void = (): void => {};
  @Event onOpenSync: () => void = (): void => {};
  @Event onExport: () => void = (): void => {};

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
          Text($r('app.string.settings_title'))
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
        .margin({ bottom: 8 })

        Scroll() {
          Column() {
            this.sectionLabel($r('app.string.settings_appearance'))

            Column() {
              Row() {
                Text($r('app.string.settings_font_size'))
                  .fontSize(15)
                  .fontColor($r('app.color.design_text_primary'))
                Blank()
                Text(`${this.vm.fontSize} fp`)
                  .fontSize(13)
                  .fontColor($r('app.color.design_accent'))
                  .margin({ right: 4 })
              }
              .width('100%')

              Slider({
                value: this.vm.fontSize,
                min: 12,
                max: 28,
                step: 1
              })
                .selectedColor($r('app.color.design_accent'))
                .trackColor($r('app.color.design_elevated'))
                .blockColor($r('app.color.design_accent'))
                .width('100%')
                .margin({ top: 6 })
                .onChange((value: number) => {
                  this.vm.setFontSize(Math.round(value));
                })
            }
            .width('100%')
            .padding(14)
            .borderRadius(18)
            .backgroundColor($r('app.color.design_elevated'))
            .margin({ top: 2 })

            this.sectionLabel($r('app.string.tab_vaults'))

            this.actionRow($r('sys.symbol.folder'), $r('app.string.settings_vault_manage'),
              this.vm.currentVault.name, (): void => {
                this.onOpenVaultManager();
              })

            this.sectionLabel($r('app.string.settings_maintenance'))

            this.actionRow($r('sys.symbol.arrow_clockwise'), $r('app.string.settings_reindex'),
              '', (): void => {
                this.vm.rescanVault();
                this.toast($r('app.string.msg_reindex_done'));
              })

            this.actionRow($r('sys.symbol.doc_zipper'), $r('app.string.action_export_vault'),
              '', (): void => {
                this.onExport();
              })

            this.actionRow($r('sys.symbol.arrow_clockwise'), $r('app.string.sync_title'),
              '', (): void => {
                this.onOpenSync();
              })

            Text($r('app.string.settings_about'))
              .fontSize(12)
              .fontColor($r('app.color.design_text_secondary'))
              .lineHeight(19)
              .width('100%')
              .margin({ top: 16 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ bottom: 8 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('88%')
      .height('72%')
      .constraintSize({ maxWidth: 500 })
      .padding(20)
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

  /** 分组标题。 */
  @Builder
  sectionLabel(label: ResourceStr) {
    Text(label)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.design_text_secondary'))
      .width('100%')
      .margin({ top: 14, bottom: 6 })
  }

  /** 操作行：图标 + 标题 + 右侧值。 */
  @Builder
  actionRow(icon: Resource, label: ResourceStr, trailing: string, action: () => void) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([$r('app.color.design_accent')])
        .width(24)
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.design_text_primary'))
        .layoutWeight(1)
      if (trailing.length > 0) {
        Text(trailing)
          .fontSize(13)
          .fontColor($r('app.color.design_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 140 })
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('app.color.design_text_secondary')])
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 14, right: 14 })
    .borderRadius(16)
    .backgroundColor($r('app.color.design_elevated'))
    .margin({ top: 4, bottom: 4 })
    .onClick(() => {
      action();
    })
  }

  /** 轻提示（使用 UIContext 的 PromptAction，避免全局 promptAction 的弃用告警）。 */
  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }
}
