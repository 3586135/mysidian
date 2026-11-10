import { unifiedDataChannel } from '@kit.ArkData';
import { FileNode, FlatFileNode } from '@ohos/domain';
import { FileTreeDataSource } from './FileTreeDataSource';

/** 拖拽数据使用的 MIME 类型。 */
const DRAG_TYPE_TEXT: string = 'text/plain';

/**
 * 文件树列表。父组件负责扁平化数据与展开状态，
 * 本组件只负责渲染与事件上报。图标使用鸿蒙 SymbolGlyph。
 *
 * 长按条目可拖动文件，拖到目录条目上即完成移动。
 */
@ComponentV2
export struct FileTreeView {
  @Param items: FlatFileNode[] = [];
  @Param selectedPath: string = '';
  @Param selectedBgColor: ResourceColor = $r('sys.color.ohos_id_color_component_activated');
  @Param selectedTextColor: ResourceColor = $r('sys.color.ohos_id_color_emphasize');
  @Event onSelect: (path: string, isDir: boolean) => void =
    (path: string, isDir: boolean): void => {};
  @Event onToggle: (path: string) => void = (path: string): void => {};
  /** 拖动文件到目标目录（目标目录为空串表示仓库根目录）。 */
  @Event onMoveNote: (path: string, destDir: string) => void =
    (path: string, destDir: string): void => {};
  private dataSource: FileTreeDataSource = new FileTreeDataSource();

  aboutToAppear(): void {
    this.dataSource.setItems(this.items);
  }

  @Monitor('items')
  onItemsChange(): void {
    this.dataSource.setItems(this.items);
  }

  build() {
    List() {
      LazyForEach(this.dataSource, (item: FlatFileNode) => {
        ListItem() {
          Row() {
            if (item.node.isDir) {
              SymbolGlyph(item.expanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
                .fontSize(14)
                .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
                .width(16)
                .onClick(() => {
                  this.onToggle(item.node.path);
                })
              SymbolGlyph($r('sys.symbol.folder'))
                .fontSize(16)
                .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
                .width(18)
                .margin({ left: 2 })
            } else {
              Row() {
                SymbolGlyph($r('sys.symbol.doc_plaintext'))
                  .fontSize(16)
                  .fontColor([item.node.path === this.selectedPath ?
                    this.selectedTextColor : $r('sys.color.ohos_id_color_text_secondary')])
              }
              .width(36)
              .justifyContent(FlexAlign.End)
              .margin({ right: 2 })
            }
            Text(this.displayName(item.node.name))
              .fontSize(15)
              .fontWeight(item.node.isDir ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(item.node.path === this.selectedPath ?
                this.selectedTextColor : $r('sys.color.ohos_id_color_text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .height(38)
          .padding({ left: 8 + item.depth * 16, right: 8 })
          .borderRadius(8)
          .backgroundColor(item.node.path === this.selectedPath ?
            this.selectedBgColor : Color.Transparent)
          .onClick(() => {
            if (item.node.isDir) {
              this.onToggle(item.node.path);
            } else {
              this.onSelect(item.node.path, false);
            }
          })
          .onDragStart((event: DragEvent): void => {
            this.startDrag(event, item.node.path);
          })
          .onDrop((event: DragEvent): void => {
            this.handleDrop(event, item.node);
          })
        }
      }, (item: FlatFileNode) => item.node.path)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .padding({ left: 4, right: 4 })
  }

  /** 开始拖拽：把被拖动条目的仓库相对路径写入拖拽数据。 */
  private startDrag(event: DragEvent, path: string): void {
    try {
      const data: unifiedDataChannel.UnifiedData = new unifiedDataChannel.UnifiedData();
      const record: unifiedDataChannel.UnifiedRecord =
        new unifiedDataChannel.UnifiedRecord(DRAG_TYPE_TEXT, path);
      data.addRecord(record);
      event.setData(data);
    } catch (error) {
      // 拖拽数据构造失败时保持静默：不阻断普通点击行为。
    }
  }

  /** 处理放下：只有目录才能作为放置目标。 */
  private handleDrop(event: DragEvent, node: FileNode): void {
    if (!node.isDir) {
      return;
    }
    const source: string = this.readDraggedPath(event);
    if (source.length === 0 || source === node.path) {
      return;
    }
    if (source.startsWith(`${node.path}/`)) {
      // 不能把目录拖进它自己的子目录。
      return;
    }
    this.onMoveNote(source, node.path);
  }

  /** 从拖拽数据中读出被拖动条目的相对路径。 */
  private readDraggedPath(event: DragEvent): string {
    try {
      const data: unifiedDataChannel.UnifiedData = event.getData();
      const records: unifiedDataChannel.UnifiedRecord[] = data.getRecords();
      if (records.length === 0) {
        return '';
      }
      const value: unifiedDataChannel.ValueType = records[0].getValue();
      if (typeof value === 'string') {
        return value;
      }
      return '';
    } catch (error) {
      return '';
    }
  }

  private displayName(name: string): string {
    if (name.length > 3 && name.substring(name.length - 3) === '.md') {
      return name.substring(0, name.length - 3);
    }
    return name;
  }
}
