import { SyncConflict } from '@ohos/domain';

/**
 * 同步设置浮层：服务器配置、手动同步与冲突展示。
 */
@ComponentV2
export struct SyncSettings {
  @Param serverUrl: string = '';
  @Param username: string = '';
  @Param password: string = '';
  @Param remoteRoot: string = '';
  @Param autoSync: boolean = false;
  @Param statusText: string = '';
  @Param conflicts: SyncConflict[] = [];
  @Event onServerUrlChange: (value: string) => void = (value: string): void => {};
  @Event onUsernameChange: (value: string) => void = (value: string): void => {};
  @Event onPasswordChange: (value: string) => void = (value: string): void => {};
  @Event onRemoteRootChange: (value: string) => void = (value: string): void => {};
  @Event onAutoSyncChange: (value: boolean) => void = (value: boolean): void => {};
  @Event onSyncNow: () => void = (): void => {};
  @Event onClose: () => void = (): void => {};

  build() {
    Stack() {
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      .opacity(0.5)
      .onClick(() => {
        this.onClose();
      })

      Column() {
        Row() {
          Text($r('app.string.sync_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .layoutWeight(1)
          Button($r('app.string.dialog_cancel'))
            .type(ButtonType.Normal)
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 10 })

        Scroll() {
          Column() {
            Text($r('app.string.sync_server'))
              .fontSize(13)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width('100%')
              .margin({ top: 8, bottom: 4 })
            TextInput({
              placeholder: $r('app.string.sync_server_placeholder'),
              text: this.serverUrl
            })
              .width('100%')
              .onChange((value: string) => {
                this.onServerUrlChange(value);
              })

            Text($r('app.string.sync_username'))
              .fontSize(13)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width('100%')
              .margin({ top: 12, bottom: 4 })
            TextInput({
              placeholder: $r('app.string.sync_username_placeholder'),
              text: this.username
            })
              .width('100%')
              .onChange((value: string) => {
                this.onUsernameChange(value);
              })

            Text($r('app.string.sync_password'))
              .fontSize(13)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width('100%')
              .margin({ top: 12, bottom: 4 })
            TextInput({
              placeholder: $r('app.string.sync_password_placeholder'),
              text: this.password
            })
              .type(InputType.Password)
              .width('100%')
              .onChange((value: string) => {
                this.onPasswordChange(value);
              })

            Text($r('app.string.sync_root'))
              .fontSize(13)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width('100%')
              .margin({ top: 12, bottom: 4 })
            TextInput({
              placeholder: $r('app.string.sync_root_placeholder'),
              text: this.remoteRoot
            })
              .width('100%')
              .onChange((value: string) => {
                this.onRemoteRootChange(value);
              })

            Row() {
              Toggle({ type: ToggleType.Switch, isOn: this.autoSync })
                .selectedColor($r('sys.color.ohos_id_color_emphasize'))
                .onChange((isOn: boolean) => {
                  this.onAutoSyncChange(isOn);
                })
              Text($r('app.string.sync_auto'))
                .fontSize(14)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
                .margin({ left: 10 })
            }
            .width('100%')
            .margin({ top: 16, bottom: 8 })

            Button($r('app.string.sync_now'))
              .type(ButtonType.Normal)
              .width('100%')
              .margin({ top: 12, bottom: 8 })
              .onClick(() => {
                this.onSyncNow();
              })

            Text(this.statusText)
              .fontSize(13)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width('100%')
              .margin({ top: 8, bottom: 8 })

            if (this.conflicts.length > 0) {
              Column() {
                Text($r('app.string.sync_conflicts'))
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                  .width('100%')
                  .margin({ bottom: 6 })
                ForEach(this.conflicts, (conflict: SyncConflict, index: number) => {
                  Column() {
                    Text(conflict.path)
                      .fontSize(13)
                      .fontColor($r('sys.color.ohos_id_color_text_primary'))
                      .width('100%')
                    Text(conflict.conflictPath)
                      .fontSize(12)
                      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                      .width('100%')
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                  .padding({ top: 6, bottom: 6 })
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
      .width('92%')
      .height('80%')
      .borderRadius(14)
      .backgroundColor($r('sys.color.ohos_id_color_background'))
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }
}
