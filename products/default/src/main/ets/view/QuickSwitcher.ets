import { NoteRow } from '@ohos/domain';

/**
 * 快速切换器浮层：鸿蒙风格顶部居中模态，模糊蒙层 + 圆角卡片。
 */
@ComponentV2
export struct QuickSwitcher {
  @Param items: NoteRow[] = [];
  @Param keyword: string = '';
  @Event onKeywordChange: (value: string) => void = (value: string): void => {};
  @Event onOpenNote: (path: string) => void = (path: string): void => {};
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
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(18)
            .fontColor([$r('app.color.hm_accent')])
          TextInput({
            placeholder: $r('app.string.quick_placeholder'),
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
          ForEach(this.items, (note: NoteRow, index: number) => {
            ListItem() {
              Column() {
                Text(note.title)
                  .fontSize(15)
                  .fontColor($r('app.color.hm_text_primary'))
                  .width('100%')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(note.path)
                  .fontSize(12)
                  .fontColor($r('app.color.hm_text_secondary'))
                  .width('100%')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .borderRadius(8)
              .onClick(() => {
                this.onOpenNote(note.path);
              })
            }
          }, (note: NoteRow, index: number): string => `quick_${index}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding(6)
      }
      .width('90%')
      .height('62%')
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
