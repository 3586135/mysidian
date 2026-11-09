import { AppCommand } from '../viewmodel/AppCommand';

/**
 * 命令面板浮层：鸿蒙风格顶部模态，模糊蒙层 + 圆角卡片。
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
      .backgroundColor($r('app.color.hm_mask'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .onClick(() => {
        this.onClose();
      })

      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.arrow_left_arrow_right_and_rectangle_portrait'))
            .fontSize(18)
            .fontColor([$r('app.color.hm_accent')])
          TextInput({
            placeholder: $r('app.string.command_placeholder'),
            text: this.keyword
          })
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .padding({ left: 8, right: 8 })
            .height(44)
            .fontSize(16)
            .placeholderColor($r('app.color.hm_text_secondary'))
            .fontColor($r('app.color.hm_text_primary'))
            .caretColor($r('app.color.hm_accent'))
            .onChange((value: string) => {
              this.onKeywordChange(value);
            })
        }
        .width('100%')
        .padding({ left: 14, right: 14 })
        .borderRadius({ topLeft: 24, topRight: 24 })
        .backgroundColor($r('app.color.hm_input_bg'))

        Divider()
          .color($r('app.color.hm_divider'))

        List() {
          ForEach(this.commands, (command: AppCommand, index: number) => {
            ListItem() {
              Row() {
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('app.color.hm_text_secondary')])
                Text(command.title)
                  .fontSize(15)
                  .fontColor($r('app.color.hm_text_primary'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (command.hint.length > 0) {
                  Text(command.hint)
                    .fontSize(12)
                    .fontColor($r('app.color.hm_text_secondary'))
                }
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .borderRadius(8)
              .onClick(() => {
                this.onRun(command);
              })
            }
          }, (command: AppCommand, index: number): string => `cmd_${command.id}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding(6)
      }
      .width('86%')
      .height('58%')
      .borderRadius(24)
      .backgroundColor($r('app.color.hm_card_bg'))
      .alignItems(HorizontalAlign.Start)
      .transition(TransitionEffect.scale({ x: 0.94, y: 0.94 })
        .combine(TransitionEffect.opacity(0))
        .animation({ duration: 220, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Top)
    .padding({ top: 64 })
    .transition(TransitionEffect.opacity(0)
      .animation({ duration: 220, curve: Curve.Friction }))
  }
}
