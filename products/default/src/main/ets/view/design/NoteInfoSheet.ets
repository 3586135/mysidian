import { MdPropType, OutlineEntry } from '@ohos/domain';
import { NoteInfoPanel } from '../NoteInfoPanel';
import { VaultViewModel } from '../../viewmodel/VaultViewModel';

/**
 * 笔记信息面板（Material 3 包装层）：大纲 / 反链 / 标签 / 属性 / 图谱五页签。
 * 数据统一从 VaultViewModel 取，属性删除二次确认内置，
 * 打开笔记 / 标签 / 大纲定位经 @Event 上抛 WorkspaceView。
 */
@ComponentV2
export struct NoteInfoSheet {
  @Param vm: VaultViewModel = new VaultViewModel();
  @Event onOpenNote: (path: string) => void = (path: string): void => {};
  @Event onOpenTag: (tag: string) => void = (tag: string): void => {};
  @Event onOutlineClick: (entry: OutlineEntry) => void = (entry: OutlineEntry): void => {};

  build() {
    NoteInfoPanel({
      outlineEntries: this.vm.outline,
      backlinks: this.vm.backlinks,
      unlinked: this.vm.unlinked,
      tags: this.vm.noteTags,
      properties: this.vm.noteProperties,
      graph: this.vm.graph,
      currentTab: this.vm.infoTabIndex,
      onTabChange: (index: number): void => {
        this.vm.setInfoTab(index);
        if (index === 1) {
          this.vm.loadUnlinked();
        } else if (index === 4) {
          this.vm.loadGraph();
        }
      },
      onOpenNote: (path: string): void => {
        this.onOpenNote(path);
      },
      onOpenTag: (tag: string): void => {
        this.onOpenTag(tag);
      },
      onOutlineClick: (entry: OutlineEntry): void => {
        this.onOutlineClick(entry);
      },
      onUpdateProperty: (key: string, value: string, listValue: string[]): void => {
        this.vm.updateProperty(key, value, listValue);
      },
      onAddProperty: (key: string, type: MdPropType): void => {
        this.vm.addProperty(key, type);
      },
      onRemoveProperty: (key: string): void => {
        this.confirmRemoveProperty(key);
      },
      onLinkMention: (path: string, title: string): void => {
        this.vm.linkMention(path, title);
      },
      onOpenGraphNode: (path: string): void => {
        this.onOpenNote(path);
      }
    })
  }

  /** 删除属性前二次确认（属性删除立即落盘，不可撤销）。 */
  private confirmRemoveProperty(key: string): void {
    AlertDialog.show({
      title: $r('app.string.props_delete'),
      message: key,
      primaryButton: {
        value: $r('app.string.dialog_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.dialog_confirm'),
        fontColor: $r('app.color.design_danger'),
        action: (): void => {
          this.vm.removeProperty(key);
        }
      },
      alignment: DialogAlignment.Bottom
    });
  }
}
