import { bundleManager, ConfigurationConstant } from '@kit.AbilityKit';
import { VaultBackupInfo } from '@ohos/vault';
import { VaultViewModel } from '../../viewmodel/VaultViewModel';

export enum SettingsSheetMode {
  NONE = -1,
  APPEARANCE = 0,
  MAINTENANCE = 1,
  ABOUT = 2
}

/**
 * Material 3 偏好与维护浮层（融合鸿蒙原生分组白底卡片 + 内缩分割线设计）：
 * 按 mode 单一职责呈现「外观与阅读」（字号 / 主题 / 关于）或「备份与维护」（重建索引 / 本地快照），
 * 不再重复堆叠仓库管理与同步设置，避免嵌套弹窗。
 */
@ComponentV2
export struct SettingsSheet {
  private static readonly GITHUB_URL: string = 'https://github.com/3586135/mysidian';
  private static readonly RELEASES_URL: string = 'https://github.com/3586135/mysidian/releases';
  private static readonly LICENSE_URL: string = 'https://github.com/3586135/mysidian/blob/main/LICENSE';

  @Param vm: VaultViewModel = new VaultViewModel();
  @Param mode: number = SettingsSheetMode.APPEARANCE;
  @Event onClose: () => void = (): void => {};
  @Local versionName: string = '';

  aboutToAppear(): void {
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.versionName = info.versionName;
    } catch (error) {
      this.versionName = '';
    }
  }

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
          Text(this.mode === SettingsSheetMode.MAINTENANCE ?
            $r('app.string.design_more_backup') : (this.mode === SettingsSheetMode.ABOUT ?
              $r('app.string.design_more_about') : $r('app.string.design_more_appearance')))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.design_text_primary'))
            .layoutWeight(1)
          Row() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(16)
              .fontColor([$r('app.color.design_text_primary')])
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor($r('app.color.design_glass_bg'))
          .backgroundBlurStyle(BlurStyle.Thin)
          .border({ width: 1, color: $r('app.color.design_glass_stroke') })
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.onClose();
          })
        }
        .width('100%')
        .margin({ bottom: 10 })

        Scroll() {
          Column() {
            if (this.mode === SettingsSheetMode.APPEARANCE) {
              this.sectionLabel($r('app.string.settings_appearance'))

              Column() {
                Row() {
                  Text($r('app.string.settings_font_size'))
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
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

                Divider()
                  .color($r('app.color.design_divider'))
                  .margin({ top: 10, bottom: 10 })

                Row() {
                  Text($r('app.string.settings_theme'))
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.design_text_primary'))
                  Blank()
                  Row({ space: 6 }) {
                    this.themeChip($r('app.string.settings_theme_system'),
                      ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
                    this.themeChip($r('app.string.settings_theme_light'),
                      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT)
                    this.themeChip($r('app.string.settings_theme_dark'),
                      ConfigurationConstant.ColorMode.COLOR_MODE_DARK)
                  }
                }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .padding(16)
            .borderRadius(20)
            .backgroundColor($r('app.color.design_surface_solid'))
            .border({ width: 1, color: $r('app.color.design_stroke') })
          } else if (this.mode === SettingsSheetMode.ABOUT) {
            this.aboutContent()
          } else {
              this.sectionLabel($r('app.string.settings_maintenance'))

              Column() {
                this.groupedRow($r('sys.symbol.arrow_clockwise'), $r('app.string.settings_reindex'),
                  '', (): void => {
                    this.vm.rescanVault();
                    this.toast($r('app.string.msg_reindex_done'));
                  })
              }
              .width('100%')
              .borderRadius(20)
              .backgroundColor($r('app.color.design_surface_solid'))
              .border({ width: 1, color: $r('app.color.design_stroke') })
              .clip(true)

              this.sectionLabel($r('app.string.backup_section'))

              Column() {
                this.groupedRow($r('sys.symbol.doc_zipper'), $r('app.string.backup_create'),
                  '', (): void => {
                    this.vm.createBackup().then((name: string): void => {
                      if (name.length > 0) {
                        this.toast($r('app.string.msg_backup_created'));
                      }
                    });
                  })

                if (this.vm.backups.length === 0) {
                  this.insetDivider()
                  Text($r('app.string.backup_empty'))
                    .fontSize(12)
                    .fontColor($r('app.color.design_text_secondary'))
                    .width('100%')
                    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                } else {
                  ForEach(this.vm.backups, (item: VaultBackupInfo) => {
                    Column() {
                      this.insetDivider()
                      this.backupRow(item)
                    }
                    .width('100%')
                  }, (item: VaultBackupInfo) => item.name)
                }
              }
              .width('100%')
              .borderRadius(20)
              .backgroundColor($r('app.color.design_surface_solid'))
              .border({ width: 1, color: $r('app.color.design_stroke') })
              .clip(true)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ bottom: 8 })
        }
        .width('100%')
        .flexShrink(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('90%')
      .constraintSize({ maxWidth: 520, maxHeight: '80%' })
      .padding(20)
      .borderRadius(28)
      .backgroundColor($r('app.color.design_bg'))
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

  /** 关于内容：应用标识 + 简介 + 开源入口 + 版权。 */
  @Builder
  aboutContent() {
    Column() {
      Row({ space: 14 }) {
        Image($r('app.media.startIcon'))
          .width(56)
          .height(56)
          .borderRadius(14)
          .border({ width: 1, color: $r('app.color.design_stroke') })
        Column({ space: 2 }) {
          Text('MySidian')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.design_text_primary'))
          Text(this.versionName.length > 0 ? `v${this.versionName}` : '')
            .fontSize(12)
            .fontColor($r('app.color.design_text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ top: 8, bottom: 4 })

      Column({ space: 8 }) {
        Text($r('app.string.about_desc'))
          .fontSize(13)
          .fontColor($r('app.color.design_text_primary'))
          .lineHeight(20)
        Text($r('app.string.about_data_note'))
          .fontSize(12)
          .fontColor($r('app.color.design_text_secondary'))
          .lineHeight(18)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(16)
      .borderRadius(20)
      .backgroundColor($r('app.color.design_surface_solid'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .margin({ top: 14 })

      this.sectionLabel($r('app.string.about_open_source'))

      Column() {
        this.groupedRow($r('sys.symbol.doc_text'), $r('app.string.about_github'), '', (): void => {
          this.vm.openExternalLink(SettingsSheet.GITHUB_URL);
        })
        this.insetDivider()
        this.groupedRow($r('sys.symbol.arrow_clockwise'), $r('app.string.about_check_update'), '', (): void => {
          this.vm.openExternalLink(SettingsSheet.RELEASES_URL);
        })
        this.insetDivider()
        this.groupedRow($r('sys.symbol.doc_plaintext'), $r('app.string.about_license'), '', (): void => {
          this.vm.openExternalLink(SettingsSheet.LICENSE_URL);
        })
      }
      .width('100%')
      .borderRadius(20)
      .backgroundColor($r('app.color.design_surface_solid'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .clip(true)

      Text($r('app.string.about_copyright'))
        .fontSize(11)
        .fontColor($r('app.color.design_text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 18 })
    }
    .width('100%')
  }

  /** 主题模式单选胶囊。 */
  @Builder
  themeChip(label: ResourceStr, mode: number) {
    Text(label)
      .fontSize(12)
      .fontWeight(this.vm.themeMode === mode ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.vm.themeMode === mode ? $r('app.color.design_surface_solid') :
        $r('app.color.design_text_secondary'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.vm.themeMode === mode ? $r('app.color.design_text_primary') :
        $r('app.color.design_elevated'))
      .onClick(() => {
        this.vm.setThemeMode(mode);
      })
  }

  /** 分组标题。 */
  @Builder
  sectionLabel(label: ResourceStr) {
    Text(label)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.design_text_secondary'))
      .width('100%')
      .padding({ left: 6 })
      .margin({ top: 14, bottom: 6 })
  }

  /** 分组卡片内缩分割线。 */
  @Builder
  insetDivider() {
    Divider()
      .color($r('app.color.design_divider'))
      .margin({ left: 48, right: 16 })
  }

  /** 分组卡片内操作行：图标 + 标题 + 右侧值 + 箭头。 */
  @Builder
  groupedRow(icon: Resource, label: ResourceStr, trailing: string, action: () => void) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([$r('app.color.design_accent')])
        .width(24)
      Text(label)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.design_text_primary'))
        .layoutWeight(1)
      if (trailing.length > 0) {
        Text(trailing)
          .fontSize(13)
          .fontColor($r('app.color.design_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 150 })
      }
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([$r('app.color.design_text_secondary')])
        .opacity(0.6)
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .onClick(() => {
      action();
    })
  }

  /** 轻提示（使用 UIContext 的 PromptAction，避免全局 promptAction 的弃用告警）。 */
  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  /** 本地快照行：时间与体积 + 恢复按钮。 */
  @Builder
  backupRow(item: VaultBackupInfo) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(this.formatBackupTime(item.createdAt))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_text_primary'))
        Text(`${Math.max(1, Math.round(item.sizeBytes / 1024))} KB`)
          .fontSize(11)
          .fontColor($r('app.color.design_text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text($r('app.string.backup_restore'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.design_accent'))
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .borderRadius(14)
        .backgroundColor($r('app.color.design_accent_weak'))
        .onClick(() => {
          this.vm.restoreBackup(item.name).then((ok: boolean): void => {
            if (ok) {
              this.toast($r('app.string.msg_backup_restored'));
            }
          });
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  private formatBackupTime(ts: number): string {
    const d: Date = new Date(ts);
    const pad = (v: number): string => v < 10 ? `0${v}` : `${v}`;
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  }
}
