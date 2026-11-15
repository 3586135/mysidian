import { noteTitleFromPath } from './NoteActionHelper';

/**
 * 文件树条目操作菜单浮层（目录与笔记分流）。
 *
 * 目录：打开文件夹 / 在此新建笔记 / 新建子文件夹 / 删除文件夹；
 * 笔记：打开 / 收藏 / 分屏双开 / 重命名 / 移动到… / 移入回收站。
 */
@ComponentV2
export struct TreeItemMenuSheet {
  @Param targetPath: string = '';
  @Param isDir: boolean = false;
  @Param bookmarked: boolean = false;
  @Param showSplit: boolean = true;
  @Param showOpenFolder: boolean = false;
  @Param allowTrashFolder: boolean = true;
  @Event onClose: () => void = (): void => {};
  @Event onOpenFolder: (folder: string) => void = (_folder: string): void => {};
  @Event onNewNoteInFolder: (folder: string) => void = (_folder: string): void => {};
  @Event onNewSubfolder: (folder: string) => void = (_folder: string): void => {};
  @Event onTrashFolder: (folder: string) => void = (_folder: string): void => {};
  @Event onOpenNote: (path: string) => void = (_path: string): void => {};
  @Event onSplitOpen: (path: string) => void = (_path: string): void => {};
  @Event onToggleBookmark: (path: string) => void = (_path: string): void => {};
  @Event onRenameNote: (path: string) => void = (_path: string): void => {};
  @Event onMoveNote: (path: string) => void = (_path: string): void => {};
  @Event onTrashNote: (path: string) => void = (_path: string): void => {};

  private titleText(): string {
    return this.isDir ? (this.targetPath.lastIndexOf('/') >= 0
      ? this.targetPath.substring(this.targetPath.lastIndexOf('/') + 1) : this.targetPath)
      : noteTitleFromPath(this.targetPath);
  }

  @Builder
  menuRow(icon: Resource, label: ResourceStr, danger: boolean, action: () => void) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([danger ? $r('app.color.design_danger') : $r('app.color.design_accent')])
        .width(24)
      Text(label)
        .fontSize(15)
        .fontColor(danger ? $r('app.color.design_danger') : $r('app.color.design_text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(46)
    .padding({ left: 14, right: 14 })
    .borderRadius(14)
    .backgroundColor($r('app.color.design_elevated'))
    .margin({ top: 4, bottom: 4 })
    .onClick(() => {
      this.onClose();
      action();
    })
  }

  build() {
    Stack() {
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.design_dim'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .onClick(() => {
        this.onClose();
      })

      Column() {
        Row() {
          SymbolGlyph(this.isDir ? $r('sys.symbol.folder') : $r('sys.symbol.doc_plaintext'))
            .fontSize(18)
            .fontColor([$r('app.color.design_accent')])
            .margin({ right: 8 })
          Text(this.titleText())
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Stack() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(15)
              .fontColor([$r('app.color.design_text_secondary')])
          }
          .width(32)
          .height(32)
          .borderRadius(16)
          .backgroundColor($r('app.color.design_elevated'))
          .onClick(() => {
            this.onClose();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 10 })

        if (this.isDir) {
          if (this.showOpenFolder) {
            this.menuRow($r('sys.symbol.folder'), $r('app.string.tree_open_folder'),
              false, (): void => {
                this.onOpenFolder(this.targetPath);
              })
          }
          this.menuRow($r('sys.symbol.square_and_pencil'), $r('app.string.tree_new_note_here'),
            false, (): void => {
              this.onNewNoteInFolder(this.targetPath);
            })
          this.menuRow($r('sys.symbol.folder'), $r('app.string.tree_new_subfolder'),
            false, (): void => {
              this.onNewSubfolder(this.targetPath);
            })
          if (this.allowTrashFolder) {
            this.menuRow($r('sys.symbol.trash'), $r('app.string.action_delete_folder'),
              true, (): void => {
                this.onTrashFolder(this.targetPath);
              })
          }
        } else {
          this.menuRow($r('sys.symbol.doc_plaintext'), $r('app.string.vault_card_open'),
            false, (): void => {
              this.onOpenNote(this.targetPath);
            })
          this.menuRow(this.bookmarked ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'),
            this.bookmarked ? $r('app.string.bookmark_remove') : $r('app.string.bookmark_add'),
            false, (): void => {
              this.onToggleBookmark(this.targetPath);
            })
          if (this.showSplit) {
            this.menuRow($r('sys.symbol.rectangle_grid_1x2'), $r('app.string.action_split'),
              false, (): void => {
                this.onSplitOpen(this.targetPath);
              })
          }
          this.menuRow($r('sys.symbol.doc_plaintext_and_pencil'), $r('app.string.action_rename'),
            false, (): void => {
              this.onRenameNote(this.targetPath);
            })
          this.menuRow($r('sys.symbol.folder'), $r('app.string.action_move'),
            false, (): void => {
              this.onMoveNote(this.targetPath);
            })
          this.menuRow($r('sys.symbol.trash'), $r('app.string.action_trash'),
            true, (): void => {
              this.onTrashNote(this.targetPath);
            })
        }
      }
      .width('86%')
      .constraintSize({ maxWidth: 420 })
      .padding(18)
      .borderRadius(26)
      .backgroundColor($r('app.color.design_surface_solid'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .shadow({ radius: 32, color: $r('app.color.design_shadow'), offsetY: 10 })
      .transition(TransitionEffect.scale({ x: 0.94, y: 0.94 })
        .combine(TransitionEffect.opacity(0))
        .animation({ duration: 200, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
  }
}
