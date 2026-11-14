import { AppCommand } from '../../viewmodel/AppCommand';

/**
 * Material 3 命令面板浮层：顶部模态，模糊蒙层 + 圆角卡片。
 * 关键词过滤在组件内部完成（命令列表为静态数据）。
 */
@ComponentV2
export struct CommandPalette {
  @Param commands: AppCommand[] = [];
  @Event onRun: (command: AppCommand) => void = (command: AppCommand): void => {};
  @Event onClose: () => void = (): void => {};

  @Local keyword: string = '';

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
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.arrow_left_arrow_right_and_rectangle_portrait'))
            .fontSize(18)
            .fontColor([$r('app.color.design_accent')])
          TextInput({
            placeholder: $r('app.string.command_placeholder'),
            text: this.keyword
          })
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .padding({ left: 0, right: 8 })
            .height(44)
            .fontSize(16)
            .placeholderColor($r('app.color.design_text_secondary'))
            .placeholderFont({ size: 15 })
            .fontColor($r('app.color.design_text_primary'))
            .caretColor($r('app.color.design_accent'))
            .onChange((value: string) => {
              this.keyword = value;
            })
          if (this.keyword.length > 0) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(14)
              .fontColor([$r('app.color.design_text_secondary')])
              .onClick(() => {
                this.keyword = '';
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .borderRadius({ topLeft: 24, topRight: 24 })
        .backgroundColor($r('app.color.design_elevated'))

        Divider()
          .color($r('app.color.design_divider'))
          .margin({ top: 4 })

        List() {
          ForEach(this.filteredCommands(), (command: AppCommand) => {
            ListItem() {
              Row({ space: 10 }) {
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('app.color.design_text_secondary')])
                Text(command.title)
                  .fontSize(15)
                  .fontColor($r('app.color.design_text_primary'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (command.hint.length > 0) {
                  Text(command.hint)
                    .fontSize(12)
                    .fontColor($r('app.color.design_text_secondary'))
                }
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .borderRadius(14)
              .onClick(() => {
                this.onRun(command);
              })
            }
          }, (command: AppCommand): string => `cmd_${command.id}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding(6)
      }
      .width('86%')
      .height('52%')
      .borderRadius(24)
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
    .alignContent(Alignment.Top)
    .padding({ top: '10%' })
  }

  /** 按关键词过滤命令。 */
  private filteredCommands(): AppCommand[] {
    const keyword: string = this.keyword.trim().toLowerCase();
    if (keyword.length === 0) {
      return this.commands;
    }
    const result: AppCommand[] = [];
    for (const command of this.commands) {
      if (command.title.toLowerCase().includes(keyword)) {
        result.push(command);
      }
    }
    return result;
  }
}
