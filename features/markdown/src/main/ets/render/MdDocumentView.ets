import { DataViewResult, DataViewTask, MdBlock, MdDocument } from '@ohos/domain';
import { MdBlockView } from './MdBlockView';
import { MdPropertiesView } from './MdPropertiesView';

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
  @Event onToggleTask: (rawLine: string, lineNumber: number, checked: boolean) => void =
    (rawLine: string, lineNumber: number, checked: boolean): void => {};
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
  /** 点击图片全屏预览。 */
  @Event onPreviewImage: (uri: string) => void = (_uri: string): void => {};
  /** 点击文档附件（PDF 等）打开系统查看器。 */
  @Event onOpenAttachment: (target: string) => void = (_target: string): void => {};
  /** 阅读态正文是否处于长按划词选中状态（用于避免父容器抢占拖动手势）。 */
  @Event onSelectionChange: (active: boolean) => void = (_active: boolean): void => {};
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.controller.scrollToBlock = (ordinal: number): void => {
      if (ordinal >= 0 && ordinal < this.document.blocks.length) {
        // frontmatter 属性卡占首个 ListItem，块序号需偏移。
        const offset: number = this.document.frontmatter.properties.length > 0 ? 1 : 0;
        this.scroller.scrollToIndex(ordinal + offset, true);
      }
    };
  }

  build() {
    List({ scroller: this.scroller }) {
      if (this.document.frontmatter.properties.length > 0) {
        ListItem() {
          MdPropertiesView({
            frontmatter: this.document.frontmatter,
            fontSize: this.fontSize,
            onOpenTag: (tag: string): void => {
              this.onOpenTag(tag);
            }
          })
        }
      }
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
            onToggleTask: (rawLine: string, lineNumber: number, checked: boolean): void => {
              this.onToggleTask(rawLine, lineNumber, checked);
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
            },
            onPreviewImage: (uri: string): void => {
              this.onPreviewImage(uri);
            },
            onOpenAttachment: (target: string): void => {
              this.onOpenAttachment(target);
            },
            onSelectionChange: (active: boolean): void => {
              this.onSelectionChange(active);
            }
          })
        }
        .transition(TransitionEffect.opacity(0)
          .combine(TransitionEffect.translate({ y: 8 }))
          .animation({ duration: 240, curve: Curve.Friction }))
      }, (block: MdBlock, index: number): string =>
        `${this.docKey}_${index}_${block.type}_${block.keyHash !== 0
          ? block.keyHash : MdDocumentView.contentHash(block.rawContent)}`)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
  }

  /**
   * 块内容哈希（djb2）：参与 ForEach key。
   * 勾选任务等操作会用新 MdDocument 整体替换 document，但块序号与类型
   * 不变——key 不含内容时框架复用旧节点，界面停留在旧状态。
   */
  private static contentHash(text: string): number {
    let h: number = 5381;
    for (let i = 0; i < text.length; i++) {
      h = ((h << 5) + h + text.charCodeAt(i)) | 0;
    }
    return h >>> 0;
  }
}
