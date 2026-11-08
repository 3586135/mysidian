import { AppCommand } from '../viewmodel/AppCommand';

/**
 * 命令面板浮层。
 */
@ComponentV2
export struct CommandPalette {
  @Param commands: AppCommand[] = [];
  @Param keyword: string = '';
  @Event onKeywordChange: (value: string) => void = (value: string): void => {};
  @Event onRun: (command: AppCommand) => void = (command: AppCommand): void => {};
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
          TextInput({
            placeholder: $r('app.string.command_placeholder'),
            text: this.keyword
          })
            .layoutWeight(1)
            .onChange((value: string) => {
              this.onKeywordChange(value);
            })
          Button($r('app.string.dialog_cancel'))
            .type(ButtonType.Normal)
            .margin({ left: 8 })
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .padding(12)

        List() {
          ForEach(this.commands, (command: AppCommand, index: number) => {
            ListItem() {
              Row() {
                Text(command.title)
                  .fontSize(15)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                  .layoutWeight(1)
                if (command.hint.length > 0) {
                  Text(command.hint)
                    .fontSize(12)
                    .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                }
              }
              .width('100%')
              .padding({ top: 10, bottom: 10 })
              .onClick(() => {
                this.onRun(command);
              })
            }
          }, (command: AppCommand, index: number): string => `cmd_${command.id}`)
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('88%')
      .height('60%')
      .borderRadius(14)
      .backgroundColor($r('sys.color.ohos_id_color_background'))
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }
}
