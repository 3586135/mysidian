import { VaultViewModel } from '../../viewmodel/VaultViewModel';

/** 长按手势修饰器：为首页笔记/文件夹条目统一绑定长按弹出操作菜单，避免卡片重复代码；支持动态路径解析以适配虚拟滚动复用。 */
export class ItemLongPressModifier implements GestureModifier {
  private path: string;
  private isDir: boolean;
  private onTrigger: (path: string, isDir: boolean) => void;
  private onEnd: () => void;
  private onCancel: () => void;
  private resolvePath: (() => string) | undefined;

  constructor(path: string, isDir: boolean,
    onTrigger: (path: string, isDir: boolean) => void,
    onEnd: () => void,
    onCancel: () => void,
    resolvePath?: () => string) {
    this.path = path;
    this.isDir = isDir;
    this.onTrigger = onTrigger;
    this.onEnd = onEnd;
    this.onCancel = onCancel;
    this.resolvePath = resolvePath;
  }

  applyGesture(event: UIGestureEvent): void {
    event.clearGestures();
    event.addGesture(
      new LongPressGestureHandler({ repeat: false, duration: 320 })
        .onAction((_ev: GestureEvent) => {
          const currentPath: string = this.resolvePath !== undefined ? this.resolvePath() : this.path;
          this.onTrigger(currentPath, this.isDir);
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

const NOTE_TINT_BG_PALETTE: Resource[] = [
  $r('app.color.design_tint_sage_bg'),
  $r('app.color.design_tint_ochre_bg'),
  $r('app.color.design_tint_rose_bg'),
  $r('app.color.design_tint_violet_bg'),
  $r('app.color.design_tint_sky_bg')
];

const NOTE_TINT_PILL_PALETTE: Resource[] = [
  $r('app.color.design_tint_sage_pill'),
  $r('app.color.design_tint_ochre_pill'),
  $r('app.color.design_tint_rose_pill'),
  $r('app.color.design_tint_violet_pill'),
  $r('app.color.design_tint_sky_pill')
];

const NOTE_TINT_FG_PALETTE: Resource[] = [
  $r('app.color.design_tint_sage_fg'),
  $r('app.color.design_tint_ochre_fg'),
  $r('app.color.design_tint_rose_fg'),
  $r('app.color.design_tint_violet_fg'),
  $r('app.color.design_tint_sky_fg')
];

/** 按路径哈希稳定选取 5 款素雅低饱和纸色索引。 */
export function noteTintIndex(path: string): number {
  let hash: number = 0;
  for (let i: number = 0; i < path.length; i++) {
    hash = (hash * 31 + path.charCodeAt(i)) & 0x7fffffff;
  }
  return hash % NOTE_TINT_BG_PALETTE.length;
}

/** 笔记/目录卡片底色令牌。 */
export function noteTintBg(path: string): Resource {
  return NOTE_TINT_BG_PALETTE[noteTintIndex(path)];
}

/** 笔记/目录徽章与描边柔彩色令牌。 */
export function noteTintPill(path: string): Resource {
  return NOTE_TINT_PILL_PALETTE[noteTintIndex(path)];
}

/** 笔记/目录前景色令牌。 */
export function noteTintFg(path: string): Resource {
  return NOTE_TINT_FG_PALETTE[noteTintIndex(path)];
}

/** 按路径哈希稳定选取 4 款莫兰迪便签封面色。 */
export function noteCoverColor(path: string): Resource {
  let hash: number = 0;
  for (let i: number = 0; i < path.length; i++) {
    hash = (hash * 31 + path.charCodeAt(i)) & 0x7fffffff;
  }
  const idx: number = hash % 4;
  if (idx === 0) {
    return $r('app.color.design_cover_rose');
  }
  if (idx === 1) {
    return $r('app.color.design_cover_sage');
  }
  if (idx === 2) {
    return $r('app.color.design_cover_ochre');
  }
  return $r('app.color.design_cover_violet');
}

/** 提取笔记所属目录名称（保留嵌套路径如 `日记 · 2026-11`）。 */
export function noteFolderBadge(path: string): string {
  const lastSlash: number = path.lastIndexOf('/');
  return lastSlash > 0 ? path.substring(0, lastSlash).replace(/\//g, ' · ') : '根目录';
}

/** 判断笔记路径是否属于日记文件。 */
export function isDailyNotePath(path: string): boolean {
  const title: string = noteTitleFromPath(path);
  return path.startsWith('日记/') ||
    (title.length >= 10 && title.charAt(4) === '-' && title.charAt(7) === '-');
}

/** 最近访问的相对时间文案。 */
export function formatNoteRelativeTime(openedAt: number): ResourceStr {
  if (openedAt <= 0) {
    return '';
  }
  const diffMs: number = Date.now() - openedAt;
  const minuteMs: number = 60 * 1000;
  const hourMs: number = 60 * minuteMs;
  const dayMs: number = 24 * hourMs;
  if (diffMs < minuteMs) {
    return $r('app.string.design_time_now');
  }
  if (diffMs < hourMs) {
    return $r('app.string.design_time_min', Math.floor(diffMs / minuteMs));
  }
  if (diffMs < dayMs) {
    return $r('app.string.design_time_hour', Math.floor(diffMs / hourMs));
  }
  if (diffMs < 2 * dayMs) {
    return $r('app.string.design_time_yesterday');
  }
  const date: Date = new Date(openedAt);
  const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
  return `${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}
