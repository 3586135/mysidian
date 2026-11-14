import { CompletionCandidate } from '../../viewmodel/EditorTextUtils';

/**
 * wiki 链接 / 标签补全浮层：跟随光标位置展示候选。
 * 由 EditorPane 在 TextArea 的 Stack 内按光标坐标定位。
 */
@ComponentV2
export struct CompletionPopup {
  @Param items: CompletionCandidate[] = [];
  @Param posX: number = 0;
  @Param posY: number = 0;
  @Event onApply: (item: CompletionCandidate) => void = (item: CompletionCandidate): void => {};

  build() {
    Column() {
      ForEach(this.items, (item: CompletionCandidate) => {
        Row() {
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(14)
            .fontColor([$r('app.color.design_text_secondary')])
            .width(18)
          Text(item.title)
            .fontSize(14)
            .fontColor($r('app.color.design_text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .height(32)
        .padding({ left: 10, right: 10 })
        .onClick(() => {
          this.onApply(item);
        })
      }, (item: CompletionCandidate, index: number): string => `ac_${index}_${item.title}`)
    }
    .width(210)
    .borderRadius(14)
    .backgroundColor($r('app.color.design_surface_solid'))
    .border({ width: 1, color: $r('app.color.design_stroke') })
    .shadow({ radius: 16, color: $r('app.color.design_shadow'), offsetY: 4 })
    .position({ x: this.posX, y: this.posY + 20 })
    .zIndex(10)
  }
}
