import { NoteRow } from '@ohos/domain';
import { SearchViewModel } from '../../viewmodel/SearchViewModel';

/**
 * Material 3 快速切换器浮层：顶部居中模态，输入笔记名即时过滤。
 * 数据与过滤逻辑归 SearchViewModel（quickKeyword / quickItems）。
 */
@ComponentV2
export struct QuickSwitcher {
  @Param searchVm: SearchViewModel = new SearchViewModel();
  @Event onOpenNote: (path: string) => void = (path: string): void => {};
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
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(18)
            .fontColor([$r('app.color.design_accent')])
          TextInput({
            placeholder: $r('app.string.quick_placeholder'),
            text: this.searchVm.quickKeyword
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
              this.searchVm.updateQuickKeyword(value);
            })
          if (this.searchVm.quickKeyword.length > 0) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(14)
              .fontColor([$r('app.color.design_text_secondary')])
              .onClick(() => {
                this.searchVm.updateQuickKeyword('');
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
          ForEach(this.searchVm.quickItems, (note: NoteRow) => {
            ListItem() {
              Column() {
                Text(note.title)
                  .fontSize(15)
                  .fontColor($r('app.color.design_text_primary'))
                  .width('100%')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(note.path)
                  .fontSize(12)
                  .fontColor($r('app.color.design_text_secondary'))
                  .width('100%')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .borderRadius(14)
              .onClick(() => {
                this.onOpenNote(note.path);
              })
            }
          }, (note: NoteRow): string => `quick_${note.path}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding(6)
      }
      .width('90%')
      .height('58%')
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
}
