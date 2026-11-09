import { SyncConflict } from '@ohos/domain';

/**
 * 同步设置浮层：鸿蒙风格设置卡片。
 */
@ComponentV2
export struct SyncSettings {
  @Param serverUrl: string = '';
  @Param username: string = '';
  @Param password: string = '';
  @Param remoteRoot: string = '';
  @Param caCertPath: string = '';
  @Param skipCertVerify: boolean = false;
  @Param autoSync: boolean = false;
  @Param statusText: string = '';
  @Param conflicts: SyncConflict[] = [];
  @Event onServerUrlChange: (value: string) => void = (value: string): void => {};
  @Event onUsernameChange: (value: string) => void = (value: string): void => {};
  @Event onPasswordChange: (value: string) => void = (value: string): void => {};
  @Event onRemoteRootChange: (value: string) => void = (value: string): void => {};
  @Event onImportCert: () => void = (): void => {};
  @Event onClearCert: () => void = (): void => {};
  @Event onSkipCertChange: (value: boolean) => void = (value: boolean): void => {};
  @Event onAutoSyncChange: (value: boolean) => void = (value: boolean): void => {};
  @Event onSyncNow: () => void = (): void => {};
  @Event onClose: () => void = (): void => {};

  build() {
    Stack() {
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.hm_mask'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .onClick(() => {
        this.onClose();
      })

      Column() {
        Row() {
          Text($r('app.string.sync_title'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.hm_text_primary'))
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([$r('app.color.hm_text_secondary')])
            .padding(6)
            .borderRadius(14)
            .backgroundColor($r('app.color.hm_hover_bg'))
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 10 })

        Scroll() {
          Column() {
            this.fieldLabel($r('app.string.sync_server'))
            this.fieldInput($r('app.string.sync_server_placeholder'), this.serverUrl, InputType.Normal,
              (value: string): void => {
                this.onServerUrlChange(value);
              })

            this.fieldLabel($r('app.string.sync_username'))
            this.fieldInput($r('app.string.sync_username_placeholder'), this.username, InputType.Normal,
              (value: string): void => {
                this.onUsernameChange(value);
              })

            this.fieldLabel($r('app.string.sync_password'))
            this.fieldInput($r('app.string.sync_password_placeholder'), this.password, InputType.Password,
              (value: string): void => {
                this.onPasswordChange(value);
              })

            this.fieldLabel($r('app.string.sync_root'))
            this.fieldInput($r('app.string.sync_root_placeholder'), this.remoteRoot, InputType.Normal,
              (value: string): void => {
                this.onRemoteRootChange(value);
              })

            this.fieldLabel($r('app.string.sync_cert'))
            Row() {
              Text(this.caCertPath.length > 0 ? $r('app.string.sync_cert_imported')
                : $r('app.string.sync_cert_system'))
                .fontSize(13)
                .fontColor($r('app.color.hm_text_secondary'))
                .layoutWeight(1)
              Button(this.caCertPath.length > 0 ? $r('app.string.sync_cert_remove')
                : $r('app.string.sync_cert_import'))
                .type(ButtonType.Capsule)
                .height(30)
                .fontSize(13)
                .padding({ left: 12, right: 12 })
                .backgroundColor($r('app.color.hm_hover_bg'))
                .fontColor(this.caCertPath.length > 0 ? $r('app.color.hm_danger')
                  : $r('app.color.hm_text_primary'))
                .onClick(() => {
                  if (this.caCertPath.length > 0) {
                    this.onClearCert();
                  } else {
                    this.onImportCert();
                  }
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 4, bottom: 8 })

            Row() {
              Column() {
                Text($r('app.string.sync_skip_cert'))
                  .fontSize(14)
                  .fontColor($r('app.color.hm_text_primary'))
                Text($r('app.string.sync_skip_cert_desc'))
                  .fontSize(12)
                  .fontColor($r('app.color.hm_text_secondary'))
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.skipCertVerify })
                .selectedColor($r('app.color.hm_danger'))
                .onChange((isOn: boolean) => {
                  this.onSkipCertChange(isOn);
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 4, bottom: 8 })

            Row() {
              Toggle({ type: ToggleType.Switch, isOn: this.autoSync })
                .selectedColor($r('app.color.hm_accent'))
                .onChange((isOn: boolean) => {
                  this.onAutoSyncChange(isOn);
                })
              Column() {
                Text($r('app.string.sync_auto'))
                  .fontSize(15)
                  .fontColor($r('app.color.hm_text_primary'))
                Text($r('app.string.sync_auto_desc'))
                  .fontSize(12)
                  .fontColor($r('app.color.hm_text_secondary'))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 16, bottom: 8 })

            Button($r('app.string.sync_now'))
              .type(ButtonType.Capsule)
              .width('100%')
              .height(42)
              .fontSize(15)
              .backgroundColor($r('app.color.hm_accent'))
              .fontColor(Color.White)
              .margin({ top: 12, bottom: 8 })
              .onClick(() => {
                this.onSyncNow();
              })

            Text(this.statusText)
              .fontSize(13)
              .fontColor($r('app.color.hm_text_secondary'))
              .width('100%')
              .margin({ top: 8, bottom: 8 })

            if (this.conflicts.length > 0) {
              Column() {
                Text($r('app.string.sync_conflicts'))
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.hm_text_primary'))
                  .width('100%')
                  .margin({ bottom: 6 })
                ForEach(this.conflicts, (conflict: SyncConflict, index: number) => {
                  Column() {
                    Text(conflict.path)
                      .fontSize(13)
                      .fontColor($r('app.color.hm_text_primary'))
                      .width('100%')
                    Text(conflict.conflictPath)
                      .fontSize(12)
                      .fontColor($r('app.color.hm_text_secondary'))
                      .width('100%')
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                  .padding({ top: 6, bottom: 6, left: 8, right: 8 })
                  .borderRadius(8)
                  .backgroundColor($r('app.color.hm_hover_bg'))
                  .margin({ bottom: 4 })
                }, (conflict: SyncConflict, index: number): string => `conflict_${index}`)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, bottom: 16 })
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('90%')
      .height('78%')
      .borderRadius(24)
      .backgroundColor($r('app.color.hm_card_bg'))
      .alignItems(HorizontalAlign.Start)
      .transition(TransitionEffect.scale({ x: 0.94, y: 0.94 })
        .combine(TransitionEffect.opacity(0))
        .animation({ duration: 220, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
    .transition(TransitionEffect.opacity(0)
      .animation({ duration: 220, curve: Curve.Friction }))
  }

  @Builder
  fieldLabel(label: ResourceStr) {
    Text(label)
      .fontSize(12)
      .fontColor($r('app.color.hm_text_secondary'))
      .width('100%')
      .margin({ top: 10, bottom: 6 })
  }

  @Builder
  fieldInput(placeholder: ResourceStr, text: string, inputType: InputType,
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
}
