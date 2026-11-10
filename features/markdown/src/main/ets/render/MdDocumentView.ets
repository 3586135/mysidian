import { DataViewResult, DataViewTask, MdBlock, MdDocument } from '@ohos/domain';
import { MdBlockView } from './MdBlockView';

/** 文档滚动控制器：由 MdDocumentView 注册实现，供外部滚动到指定块。 */
export class MdDocumentViewController {
  public scrollToBlock: (ordinal: number) => void = (ordinal: number): void => {};
}

/**
 * 文档渲染器：按块顺序渲染整篇文档。
 * docKey（笔记路径）参与块 key 生成，切换笔记时强制重建列表项，避免复用旧内容。
 */
@ComponentV2
export struct MdDocumentView {
  @Param document: MdDocument = new MdDocument();
  @Param docKey: string = '';
  @Param fontSize: number = 16;
  @Param controller: MdDocumentViewController = new MdDocumentViewController();
  @Event onOpenLink: (target: string, kind: string) => void =
    (target: string, kind: string): void => {};
  @Event onOpenTag: (tag: string) => void = (tag: string): void => {};
  @Event onToggleTask: (rawLine: string, checked: boolean) => void =
    (rawLine: string, checked: boolean): void => {};
  @Event onLoadDataView: (query: string, onResult: (result: DataViewResult) => void) => void =
    (query: string, onResult: (result: DataViewResult) => void): void => {};
  @Event onToggleDataViewTask: (task: DataViewTask, checked: boolean) => void =
    (task: DataViewTask, checked: boolean): void => {};
  /** 加载嵌入笔记正文。 */
  @Event onLoadEmbed: (target: string, onResult: (text: string) => void) => void =
    (target: string, onResult: (text: string) => void): void => {};
  /** 解析图片资源 URI。 */
  @Event onResolveAsset: (target: string, onResult: (uri: string) => void) => void =
    (target: string, onResult: (uri: string) => void): void => {};
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.controller.scrollToBlock = (ordinal: number): void => {
      if (ordinal >= 0 && ordinal < this.document.blocks.length) {
        this.scroller.scrollToIndex(ordinal, true);
      }
    };
  }

  build() {
    List({ scroller: this.scroller }) {
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
            },
            onToggleTask: (rawLine: string, checked: boolean): void => {
              this.onToggleTask(rawLine, checked);
            },
            onLoadDataView: (query: string, onResult: (result: DataViewResult) => void): void => {
              this.onLoadDataView(query, onResult);
            },
            onToggleDataViewTask: (task: DataViewTask, checked: boolean): void => {
              this.onToggleDataViewTask(task, checked);
            },
            onLoadEmbed: (target: string, onResult: (text: string) => void): void => {
              this.onLoadEmbed(target, onResult);
            },
            onResolveAsset: (target: string, onResult: (uri: string) => void): void => {
              this.onResolveAsset(target, onResult);
            }
          })
        }
        .transition(TransitionEffect.opacity(0)
          .combine(TransitionEffect.translate({ y: 8 }))
          .animation({ duration: 240, curve: Curve.Friction }))
      }, (block: MdBlock, index: number): string => `${this.docKey}_${index}_${block.type}`)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
  }
}
