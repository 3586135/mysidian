import { MdBlock, MdDocument } from '@ohos/domain';
import { MdBlockView } from './MdBlockView';

/**
 * 文档渲染器：按块顺序渲染整篇文档。
 */
@ComponentV2
export struct MdDocumentView {
  @Param document: MdDocument = new MdDocument();
  @Param fontSize: number = 16;
  @Event onOpenLink: (target: string, kind: string) => void =
    (target: string, kind: string): void => {};
  @Event onOpenTag: (tag: string) => void = (tag: string): void => {};

  build() {
    List() {
      ForEach(this.document.blocks, (block: MdBlock, index: number) => {
        ListItem() {
          MdBlockView({
            block: block,
            fontSize: this.fontSize,
            onOpenLink: (target: string, kind: string): void => {
              this.onOpenLink(target, kind);
            },
            onOpenTag: (tag: string): void => {
              this.onOpenTag(tag);
            }
          })
        }
      }, (block: MdBlock, index: number): string => `block_${index}`)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
  }
}
