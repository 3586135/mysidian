import { SyncConflict } from '@ohos/domain';
import { SyncViewModel } from '../../viewmodel/SyncViewModel';

/**
 * Material 3 WebDAV 同步设置浮层：服务器 / 账号 / 远程目录、
 * 自定义证书导入、跳过校验、自动同步开关、立即同步与冲突列表。
 * 配置直接写 SyncViewModel；证书选择与定时器重建经 @Event 上抛宿主。
 */
@ComponentV2
export struct SyncSettingsSheet {
  @Param syncVm: SyncViewModel = new SyncViewModel();
  @Event onImportCert: () => void = (): void => {};
  @Event onAutoSyncChange: (value: boolean) => void = (value: boolean): void => {};
  @Event onSyncNow: () => void = (): void => {};
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
          Text($r('app.string.sync_title'))
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
        .margin({ bottom: 6 })

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
                Text($r('app.string.sync_skip_cert_desc'))
                  .fontSize(12)
                  .fontColor($r('app.color.design_text_secondary'))
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
              Toggle({ type: ToggleType.Switch, isOn: this.syncVm.autoSync })
                .selectedColor($r('app.color.design_accent'))
                .onChange((isOn: boolean) => {
                  this.syncVm.autoSync = isOn;
                  this.onAutoSyncChange(isOn);
                })
              Column() {
                Text($r('app.string.sync_auto'))
                  .fontSize(15)
                  .fontColor($r('app.color.design_text_primary'))
                Text($r('app.string.sync_auto_desc'))
                  .fontSize(12)
                  .fontColor($r('app.color.design_text_secondary'))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 12, bottom: 4 })

            Button($r('app.string.sync_now'))
              .type(ButtonType.Capsule)
              .width('100%')
              .height(42)
              .fontSize(15)
              .backgroundColor($r('app.color.design_accent'))
              .fontColor(Color.White)
              .margin({ top: 12, bottom: 8 })
              .onClick(() => {
                this.onSyncNow();
              })

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
                      .fontColor($r('app.color.design_text_primary'))
                      .width('100%')
                    Text(conflict.conflictPath)
                      .fontSize(12)
                      .fontColor($r('app.color.design_text_secondary'))
                      .width('100%')
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                  .padding({ top: 6, bottom: 6, left: 10, right: 10 })
                  .borderRadius(10)
                  .backgroundColor($r('app.color.design_elevated'))
                  .margin({ bottom: 4 })
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
      .height('78%')
      .constraintSize({ maxWidth: 520 })
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

  /** 字段标签。 */
  @Builder
  fieldLabel(label: ResourceStr) {
    Text(label)
      .fontSize(12)
      .fontColor($r('app.color.design_text_secondary'))
      .width('100%')
      .margin({ top: 10, bottom: 6 })
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
      .height(42)
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
