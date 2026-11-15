import { VaultViewModel } from '../../viewmodel/VaultViewModel';

/** 长按手势修饰器：为首页笔记/文件夹条目统一绑定长按弹出操作菜单，避免卡片重复代码。 */
export class ItemLongPressModifier implements GestureModifier {
  private path: string;
  private isDir: boolean;
  private onTrigger: (path: string, isDir: boolean) => void;
  private onEnd: () => void;
  private onCancel: () => void;

  constructor(path: string, isDir: boolean,
    onTrigger: (path: string, isDir: boolean) => void,
    onEnd: () => void,
    onCancel: () => void) {
    this.path = path;
    this.isDir = isDir;
    this.onTrigger = onTrigger;
    this.onEnd = onEnd;
    this.onCancel = onCancel;
  }

  applyGesture(event: UIGestureEvent): void {
    event.clearGestures();
    event.addGesture(
      new LongPressGestureHandler({ repeat: false, duration: 320 })
        .onAction((_ev: GestureEvent) => {
          this.onTrigger(this.path, this.isDir);
        })
        .onActionEnd((_ev: GestureEvent) => {
          this.onEnd();
        })
        .onActionCancel(() => {
          this.onCancel();
        })
    );
  }
}

/** 通用三点「更多操作」图标：避免 sys.symbol.more 渲染为四宫格图标而与视图切换/更多页混淆。 */
@Builder
export function ThreeDotsIcon(dotSize: number, gap: number, color: Resource, iconOpacity: number) {
  Row({ space: gap }) {
    Circle({ width: dotSize, height: dotSize }).fill(color)
    Circle({ width: dotSize, height: dotSize }).fill(color)
    Circle({ width: dotSize, height: dotSize }).fill(color)
  }
  .opacity(iconOpacity)
}

/** 从相对路径提取展示标题（笔记去掉 .md 扩展名，目录取最后一段）。 */
export function noteTitleFromPath(path: string): string {
  const slash: number = path.lastIndexOf('/');
  const base: string = slash >= 0 ? path.substring(slash + 1) : path;
  return base.toLowerCase().endsWith('.md') ? base.substring(0, base.length - 3) : base;
}

/** 二次确认后将指定笔记移入回收站（首页与工作台共用）。 */
export function confirmTrashNoteAction(vm: VaultViewModel, path: string,
  onSuccess: () => void, onError: (msg: ResourceStr) => void): void {
  if (path.length === 0) {
    onError($r('app.string.msg_no_note_selected'));
    return;
  }
  AlertDialog.show({
    title: $r('app.string.dialog_trash_title'),
    message: $r('app.string.dialog_trash_msg'),
    primaryButton: {
      value: $r('app.string.dialog_cancel'),
      action: (): void => {}
    },
    secondaryButton: {
      value: $r('app.string.action_trash'),
      fontColor: $r('app.color.design_danger'),
      action: (): void => {
        vm.trashNote(path).then((ok: boolean): void => {
          if (!ok) {
            onError($r('app.string.msg_trash_failed'));
            return;
          }
          onSuccess();
        });
      }
    },
    alignment: DialogAlignment.Bottom
  });
}

/** 二次确认后将指定文件夹及其内所有笔记移入回收站并删除目录（首页与工作台共用）。 */
export function confirmTrashFolderAction(vm: VaultViewModel, dirPath: string,
  onSuccess: () => void, onError: (msg: ResourceStr) => void): void {
  if (dirPath.length === 0) {
    return;
  }
  const slash: number = dirPath.lastIndexOf('/');
  const leaf: string = slash >= 0 ? dirPath.substring(slash + 1) : dirPath;
  const noteCount: number = vm.countNotesInFolder(dirPath);
  const message: ResourceStr = noteCount > 0
    ? $r('app.string.dialog_trash_folder_msg_with_notes', leaf, noteCount)
    : $r('app.string.dialog_trash_folder_msg_empty', leaf);
  AlertDialog.show({
    title: $r('app.string.dialog_trash_folder_title'),
    message: message,
    primaryButton: {
      value: $r('app.string.dialog_cancel'),
      action: (): void => {}
    },
    secondaryButton: {
      value: $r('app.string.action_delete_folder'),
      fontColor: $r('app.color.design_danger'),
      action: (): void => {
        vm.trashFolder(dirPath).then((ok: boolean): void => {
          if (!ok) {
            onError($r('app.string.msg_trash_folder_failed'));
            return;
          }
          onSuccess();
        });
      }
    },
    alignment: DialogAlignment.Bottom
  });
}
