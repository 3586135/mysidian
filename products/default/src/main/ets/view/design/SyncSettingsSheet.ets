import { SyncConflict, VaultInfo } from '@ohos/domain';
import { DiffLine } from '@ohos/vault';
import { SyncViewModel } from '../../viewmodel/SyncViewModel';

/**
 * Material 3 WebDAV 同步设置浮层：服务器 / 账号 / 远程目录、
 * 自定义证书导入、跳过校验、自动同步开关、立即同步与冲突列表。
 * 配置直接写 SyncViewModel；证书选择与定时器重建经 @Event 上抛宿主。
 */
@ComponentV2
export struct SyncSettingsSheet {
  @Param syncVm: SyncViewModel = new SyncViewModel();
  @Param vault: VaultInfo = new VaultInfo();
  @Event onImportCert: () => void = (): void => {};
  @Event onAutoSyncChange: (value: boolean) => void = (value: boolean): void => {};
  @Event onSyncNow: () => void = (): void => {};
  @Event onClose: () => void = (): void => {};
  @Local activeConflictPath: string = '';
  @Local conflictDiffLines: DiffLine[] = [];

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
          Text($r('app.string.sync_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_text_primary'))
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
            this.onClose();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 4 })

        Scroll() {
          Column() {
            this.fieldLabel($r('app.string.sync_server'))
            this.fieldInput($r('app.string.sync_server_placeholder'), this.syncVm.serverUrl,
              InputType.Normal, (value: string): void => {
                this.syncVm.serverUrl = value;
              })

            this.fieldLabel($r('app.string.sync_username'))
            this.fieldInput($r('app.string.sync_username_placeholder'), this.syncVm.username,
              InputType.Normal, (value: string): void => {
                this.syncVm.username = value;
              })

            this.fieldLabel($r('app.string.sync_password'))
            this.fieldInput($r('app.string.sync_password_placeholder'), this.syncVm.password,
              InputType.Password, (value: string): void => {
                this.syncVm.password = value;
              })

            this.fieldLabel($r('app.string.sync_root'))
            this.fieldInput($r('app.string.sync_root_placeholder'), this.syncVm.remoteRoot,
              InputType.Normal, (value: string): void => {
                this.syncVm.remoteRoot = value;
              })

            this.fieldLabel($r('app.string.sync_cert'))
            Row() {
              Text(this.syncVm.caCertPath.length > 0 ? $r('app.string.sync_cert_imported')
                : $r('app.string.sync_cert_system'))
                .fontSize(13)
                .fontColor($r('app.color.design_text_secondary'))
                .layoutWeight(1)
                .maxLines(2)
              Text(this.syncVm.caCertPath.length > 0 ? $r('app.string.sync_cert_remove')
                : $r('app.string.sync_cert_import'))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.syncVm.caCertPath.length > 0 ?
                  $r('app.color.design_danger') : $r('app.color.design_accent'))
                .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                .borderRadius(16)
                .backgroundColor($r('app.color.design_elevated'))
                .onClick(() => {
                  if (this.syncVm.caCertPath.length > 0) {
                    this.syncVm.clearCert();
                  } else {
                    this.onImportCert();
                  }
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 2, bottom: 4 })

            Row() {
              Column() {
                Text($r('app.string.sync_skip_cert'))
                  .fontSize(14)
                  .fontColor($r('app.color.design_text_primary'))
                Text(this.syncVm.skipCertVerify ? $r('app.string.sync_skip_cert_warning') :
                  $r('app.string.sync_skip_cert_desc'))
                  .fontSize(12)
                  .fontColor(this.syncVm.skipCertVerify ? $r('app.color.design_danger') :
                    $r('app.color.design_text_secondary'))
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.syncVm.skipCertVerify })
                .selectedColor($r('app.color.design_danger'))
                .onChange((isOn: boolean) => {
                  this.syncVm.skipCertVerify = isOn;
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 8, bottom: 4 })

            Row() {
              Column() {
                Text($r('app.string.sync_auto'))
                  .fontSize(14)
                  .fontColor($r('app.color.design_text_primary'))
                Text($r('app.string.sync_auto_desc'))
                  .fontSize(12)
                  .fontColor($r('app.color.design_text_secondary'))
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Toggle({ type: ToggleType.Switch, isOn: this.syncVm.autoSync })
                .selectedColor($r('app.color.design_accent'))
                .onChange((isOn: boolean) => {
                  this.syncVm.autoSync = isOn;
                  this.onAutoSyncChange(isOn);
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 10, bottom: 4 })

            Button(this.syncVm.syncing ? $r('app.string.sync_status_syncing')
              : $r('app.string.sync_now'))
              .type(ButtonType.Capsule)
              .width('100%')
              .height(42)
              .fontSize(15)
              .enabled(!this.syncVm.syncing)
              .opacity(this.syncVm.syncing ? 0.65 : 1)
              .backgroundColor($r('app.color.design_accent'))
              .fontColor($r('app.color.design_on_accent'))
              .margin({ top: 10, bottom: 8 })
              .onClick(() => {
                this.onSyncNow();
              })

            Column() {
              Text($r('app.string.sync_obsidian_guard_title'))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.design_accent'))
                .width('100%')
              Text($r('app.string.sync_obsidian_guard_desc'))
                .fontSize(11)
                .fontColor($r('app.color.design_text_secondary'))
                .lineHeight(16)
                .width('100%')
                .margin({ top: 3 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .borderRadius(10)
            .backgroundColor($r('app.color.design_elevated'))
            .margin({ top: 4, bottom: 6 })

            if (this.syncVm.awaitingConfirmation) {
              Column() {
                Text($r('app.string.sync_confirm_title'))
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.design_danger'))
                  .width('100%')
                Text(this.syncVm.safetyAlertMessage())
                  .fontSize(12)
                  .fontColor($r('app.color.design_text_primary'))
                  .lineHeight(17)
                  .width('100%')
                  .margin({ top: 4 })
                Row() {
                  Text($r('app.string.dialog_cancel'))
                    .fontSize(12)
                    .fontColor($r('app.color.design_text_secondary'))
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .borderRadius(14)
                    .backgroundColor($r('app.color.design_surface_solid'))
                    .onClick(() => {
                      this.syncVm.cancelPendingSync();
                    })
                  Text($r('app.string.sync_confirm_proceed'))
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.design_on_accent'))
                    .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                    .borderRadius(14)
                    .backgroundColor($r('app.color.design_accent'))
                    .margin({ left: 8 })
                    .onClick(() => {
                      this.syncVm.confirmPendingSync(this.vault);
                    })
                }
                .width('100%')
                .margin({ top: 8 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .borderRadius(10)
              .border({ width: 1, color: $r('app.color.design_danger') })
              .backgroundColor($r('app.color.design_elevated'))
              .margin({ top: 4, bottom: 6 })
            }

            Text(this.syncVm.statusText())
              .fontSize(13)
              .fontColor($r('app.color.design_text_secondary'))
              .width('100%')
              .margin({ top: 8, bottom: 8 })

            if (this.syncVm.conflicts.length > 0) {
              Column() {
                Text($r('app.string.sync_conflicts'))
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.design_text_primary'))
                  .width('100%')
                  .margin({ bottom: 6 })
                ForEach(this.syncVm.conflicts, (conflict: SyncConflict) => {
                  Column() {
                    Text(conflict.path)
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.design_text_primary'))
                      .width('100%')
                    Text(conflict.conflictPath)
                      .fontSize(12)
                      .fontColor($r('app.color.design_text_secondary'))
                      .width('100%')
                      .margin({ top: 2 })
                    if (conflict.isBinary) {
                      Text($r('app.string.sync_conflict_binary_hint'))
                        .fontSize(11)
                        .fontColor($r('app.color.design_text_secondary'))
                        .width('100%')
                        .margin({ top: 4 })
                    }
                    Flex({ wrap: FlexWrap.Wrap }) {
                      if (!conflict.isBinary) {
                        this.conflictActionChip($r('app.string.sync_conflict_diff'), false, (): void => {
                          this.toggleConflictDiff(conflict);
                        })
                      }
                      this.conflictActionChip($r('app.string.sync_conflict_keep_local'), false, (): void => {
                        this.syncVm.resolveConflictKeepLocal(this.vault, conflict).then((ok: boolean): void => {
                          if (ok) {
                            this.activeConflictPath = '';
                            this.toast($r('app.string.msg_conflict_resolved'));
                          } else {
                            this.toast($r('app.string.msg_conflict_push_failed'));
                          }
                        });
                      })
                      this.conflictActionChip($r('app.string.sync_conflict_use_remote'), true, (): void => {
                        this.syncVm.resolveConflictUseRemote(this.vault, conflict).then((ok: boolean): void => {
                          if (ok) {
                            this.activeConflictPath = '';
                            this.toast($r('app.string.msg_conflict_resolved'));
                          }
                        });
                      })
                    }
                    .width('100%')
                    .margin({ top: 8 })
                    if (this.activeConflictPath === conflict.conflictPath) {
                      Column() {
                        ForEach(this.conflictDiffLines, (line: DiffLine, lineIndex: number) => {
                          Text(`${line.marker}${line.text}`)
                            .fontSize(11)
                            .fontFamily('monospace')
                            .fontColor(this.diffColor(line))
                            .width('100%')
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                        }, (line: DiffLine, lineIndex: number): string => `cd_${lineIndex}_${line.marker}`)
                      }
                      .width('100%')
                      .alignItems(HorizontalAlign.Start)
                      .margin({ top: 6 })
                    }
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                  .padding({ top: 8, bottom: 8, left: 10, right: 10 })
                  .borderRadius(10)
                  .backgroundColor($r('app.color.design_elevated'))
                  .margin({ bottom: 6 })
                }, (conflict: SyncConflict): string =>
                `conflict_${conflict.path}_${conflict.conflictPath}`)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
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
      .width('90%')
      .constraintSize({ maxWidth: 520, maxHeight: '84%' })
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

  /** 冲突操作胶囊按钮。 */
  @Builder
  conflictActionChip(label: ResourceStr, primary: boolean, action: () => void) {
    Text(label)
      .fontSize(12)
      .fontWeight(primary ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(primary ? $r('app.color.design_accent') : $r('app.color.design_text_primary'))
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .borderRadius(12)
      .backgroundColor(primary ? $r('app.color.design_accent_weak') :
        $r('app.color.design_surface_solid'))
      .margin({ right: 8, bottom: 6 })
      .onClick(() => {
        action();
      })
  }

  private toggleConflictDiff(conflict: SyncConflict): void {
    if (this.activeConflictPath === conflict.conflictPath) {
      this.activeConflictPath = '';
      this.conflictDiffLines = [];
      return;
    }
    this.activeConflictPath = conflict.conflictPath;
    this.conflictDiffLines = this.syncVm.diffConflict(this.vault, conflict);
  }

  private diffColor(line: DiffLine): ResourceColor {
    if (line.marker === '+') {
      return $r('app.color.design_accent');
    }
    if (line.marker === '-') {
      return $r('app.color.design_danger');
    }
    return $r('app.color.design_text_secondary');
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  /** 字段标签。 */
  @Builder
  fieldLabel(label: ResourceStr) {
    Text(label)
      .fontSize(12)
      .fontColor($r('app.color.design_text_secondary'))
      .width('100%')
      .margin({ top: 8, bottom: 4 })
  }

  /** 字段输入框。 */
  @Builder
  fieldInput(placeholder: ResourceStr, text: string, inputType: InputType,
    onChange: (value: string) => void) {
    TextInput({
      placeholder: placeholder,
      text: text
    })
      .type(inputType)
      .width('100%')
      .height(40)
      .fontSize(15)
      .padding({ left: 14, right: 14 })
      .borderRadius(12)
      .backgroundColor($r('app.color.design_elevated'))
      .placeholderColor($r('app.color.design_text_secondary'))
      .placeholderFont({ size: 14 })
      .fontColor($r('app.color.design_text_primary'))
      .caretColor($r('app.color.design_accent'))
      .onChange((value: string) => {
        onChange(value);
      })
  }
}
