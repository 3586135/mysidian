import { FlatFileNode } from '@ohos/domain';
import { FileTreeDataSource } from './FileTreeDataSource';

/**
 * 仓库文件树列表。父组件负责扁平化数据与展开状态，
 * 本组件只负责渲染与事件上报。
 */
@ComponentV2
export struct FileTreeView {
  @Param items: FlatFileNode[] = [];
  @Param selectedPath: string = '';
  @Event onSelect: (path: string, isDir: boolean) => void =
    (path: string, isDir: boolean): void => {};
  @Event onToggle: (path: string) => void = (path: string): void => {};
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
            Text(item.expanded ? '▾' : '▸')
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width(16)
            Text(item.node.name)
              .fontSize(15)
              .fontWeight(item.node.isDir ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(item.node.path === this.selectedPath ?
                $r('sys.color.ohos_id_color_emphasize') : $r('sys.color.ohos_id_color_text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .height(40)
          .padding({ left: 8 + item.depth * 16, right: 8 })
          .borderRadius(6)
          .backgroundColor(item.node.path === this.selectedPath ?
            $r('sys.color.ohos_id_color_component_activated') : Color.Transparent)
          .onClick(() => {
            if (item.node.isDir) {
              this.onToggle(item.node.path);
            } else {
              this.onSelect(item.node.path, false);
            }
          })
        }
      }, (item: FlatFileNode) => item.node.path)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
  }
}
