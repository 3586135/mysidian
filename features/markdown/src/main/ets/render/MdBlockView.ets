import { MdBlock, MdBlockType, MdListItem } from '@ohos/domain';
import { MdInlineFlattener } from './MdInlineFlattener';
import { MdInlineText } from './MdInlineText';
import { MdWebFallback } from './MdWebFallback';

/**
 * 块级渲染器：按块类型输出原生 ArkUI 组件。
 */
@ComponentV2
export struct MdBlockView {
  @Param block: MdBlock = new MdBlock();
  @Param fontSize: number = 16;
  @Event onOpenLink: (target: string, kind: string) => void =
    (target: string, kind: string): void => {};
  @Event onOpenTag: (tag: string) => void = (tag: string): void => {};

  build() {
    Column() {
      if (this.block.type === MdBlockType.HEADING) {
        this.headingView()
      } else if (this.block.type === MdBlockType.PARAGRAPH) {
        MdInlineText({
          segments: MdInlineFlattener.flatten(this.block.inlines),
          fontSize: this.fontSize,
          onOpenLink: (target: string, kind: string): void => {
            this.onOpenLink(target, kind);
          },
          onOpenTag: (tag: string): void => {
            this.onOpenTag(tag);
          }
        })
      } else if (this.block.type === MdBlockType.LIST) {
        this.listView()
      } else if (this.block.type === MdBlockType.CODE) {
        this.codeView()
      } else if (this.block.type === MdBlockType.QUOTE) {
        this.quoteView()
      } else if (this.block.type === MdBlockType.CALLOUT) {
        this.calloutView()
      } else if (this.block.type === MdBlockType.TABLE) {
        this.tableView()
      } else if (this.block.type === MdBlockType.THEMATIC_BREAK) {
        Divider()
          .color($r('sys.color.ohos_id_color_text_secondary'))
          .margin({ top: 8, bottom: 8 })
      } else if (this.block.type === MdBlockType.HTML) {
        MdWebFallback({
          html: this.block.rawContent,
          contentHeight: this.htmlHeight()
        })
        .width('100%')
      } else {
        this.rawView()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  headingView() {
    Row() {
      MdInlineText({
        segments: MdInlineFlattener.flatten(this.block.inlines),
        fontSize: this.headingFontSize(),
        onOpenLink: (target: string, kind: string): void => {
          this.onOpenLink(target, kind);
        },
        onOpenTag: (tag: string): void => {
          this.onOpenTag(tag);
        }
      })
    }
    .width('100%')
    .margin({ top: 12, bottom: 6 })
  }

  @Builder
  listView() {
    Column() {
      ForEach(this.block.items, (item: MdListItem, index: number) => {
        this.listItemView(item, 0)
      }, (item: MdListItem, index: number): string => `item_${index}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 4, bottom: 4 })
  }

  @Builder
  listItemView(item: MdListItem, depth: number) {
    Column() {
      Row() {
        Text(this.bulletText(item))
          .fontSize(this.fontSize)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width(24)
        if (item.isTask) {
          Text(item.checked ? '☑' : '☐')
            .fontSize(this.fontSize)
            .width(22)
        }
        MdInlineText({
          segments: MdInlineFlattener.flatten(item.inlines),
          fontSize: this.fontSize,
          onOpenLink: (target: string, kind: string): void => {
            this.onOpenLink(target, kind);
          },
          onOpenTag: (tag: string): void => {
            this.onOpenTag(tag);
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      ForEach(item.children, (child: MdListItem, index: number) => {
        this.listItemView(child, depth + 1)
      }, (child: MdListItem, index: number): string => `child_${depth}_${index}`)
    }
    .width('100%')
    .padding({ left: depth * 18 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  codeView() {
    Column() {
      Text(this.block.rawContent)
        .fontSize(this.fontSize - 2)
        .fontFamily('monospace')
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
    .margin({ top: 6, bottom: 6 })
  }

  @Builder
  quoteView() {
    Row() {
      Column() {
        MdInlineText({
          segments: MdInlineFlattener.flatten(this.block.inlines),
          fontSize: this.fontSize,
          onOpenLink: (target: string, kind: string): void => {
            this.onOpenLink(target, kind);
          },
          onOpenTag: (tag: string): void => {
            this.onOpenTag(tag);
          }
        })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 12, top: 4, bottom: 4 })
    .borderWidth({ left: 3 })
    .borderColor($r('sys.color.ohos_id_color_emphasize'))
    .margin({ top: 4, bottom: 4 })
  }

  @Builder
  calloutView() {
    Row() {
      Text(this.calloutIcon())
        .fontSize(this.fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_emphasize'))
        .width(24)
      Column() {
        Text(this.block.calloutType)
          .fontSize(this.fontSize)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        MdInlineText({
          segments: MdInlineFlattener.flatten(this.block.inlines),
          fontSize: this.fontSize,
          onOpenLink: (target: string, kind: string): void => {
            this.onOpenLink(target, kind);
          },
          onOpenTag: (tag: string): void => {
            this.onOpenTag(tag);
          }
        })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('sys.color.ohos_id_color_component_activated'))
    .margin({ top: 6, bottom: 6 })
  }

  @Builder
  tableView() {
    Column() {
      Row() {
        ForEach(this.block.headers, (header: string, index: number) => {
          Text(header)
            .fontSize(this.fontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .layoutWeight(1)
        }, (header: string, index: number): string => `head_${index}`)
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })
      Divider()
        .color($r('sys.color.ohos_id_color_text_secondary'))
      ForEach(this.block.rows, (row: string[], rowIndex: number) => {
        Row() {
          ForEach(row, (cell: string, cellIndex: number) => {
            Text(cell)
              .fontSize(this.fontSize)
              .fontColor($r('sys.color.ohos_id_color_text_primary'))
              .layoutWeight(1)
          }, (cell: string, cellIndex: number): string => `cell_${rowIndex}_${cellIndex}`)
        }
        .width('100%')
        .padding({ top: 6, bottom: 6 })
      }, (row: string[], rowIndex: number): string => `row_${rowIndex}`)
    }
    .width('100%')
    .margin({ top: 6, bottom: 6 })
  }

  @Builder
  rawView() {
    Column() {
      Text(this.block.rawContent)
        .fontSize(this.fontSize - 2)
        .fontFamily('monospace')
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding(10)
    .borderRadius(8)
    .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
    .margin({ top: 6, bottom: 6 })
  }

  private htmlHeight(): number {
    const length: number = this.block.rawContent.length;
    const lines: number = Math.max(1, Math.floor(length / 40));
    return Math.min(420, 80 + lines * 20);
  }

  private headingFontSize(): number {    if (this.block.level <= 1) {
      return this.fontSize + 8;
    }
    if (this.block.level === 2) {
      return this.fontSize + 5;
    }
    if (this.block.level === 3) {
      return this.fontSize + 2;
    }
    return this.fontSize;
  }

  private bulletText(item: MdListItem): string {
    if (this.block.ordered) {
      return `${item.ordinal}.`;
    }
    return '•';
  }

  private calloutIcon(): string {
    const type: string = this.block.calloutType;
    if (type === 'TIP') {
      return '✓';
    }
    if (type === 'NOTE') {
      return 'i';
    }
    return '!';
  }
}
