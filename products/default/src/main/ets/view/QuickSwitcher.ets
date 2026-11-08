import { NoteRow } from '@ohos/domain';

/**
 * 快速切换器浮层：模糊匹配笔记标题。
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
      .backgroundColor(Color.Black)
      .opacity(0.5)
      .onClick(() => {
        this.onClose();
      })

      Column() {
        Row() {
          TextInput({
            placeholder: $r('app.string.quick_placeholder'),
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
          ForEach(this.items, (note: NoteRow, index: number) => {
            ListItem() {
              Column() {
                Text(note.title)
                  .fontSize(15)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                  .width('100%')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(note.path)
                  .fontSize(12)
                  .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                  .width('100%')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ top: 8, bottom: 8 })
              .onClick(() => {
                this.onOpenNote(note.path);
              })
            }
          }, (note: NoteRow, index: number): string => `quick_${index}`)
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
