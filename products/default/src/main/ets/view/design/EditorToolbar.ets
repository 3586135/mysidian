/**
 * 编辑模式底部格式化工具栏（横向滚动，避免窄屏按钮溢出）。
 * 17 个按钮全部经 @Event 上抛，编辑逻辑归 EditorPane。
 */
@ComponentV2
export struct EditorToolbar {
  @Param undoDepth: number = 0;
  @Param redoDepth: number = 0;
  @Event onInsertFormat: (syntax: string) => void = (_syntax: string): void => {};
  @Event onUndo: () => void = (): void => {};
  @Event onRedo: () => void = (): void => {};
  @Event onPickImage: () => void = (): void => {};

  @Builder
  toolbarButton(label: string, insertText: string, fontSize: number) {
    Button(label)
      .fontSize(fontSize)
      .height(32)
      .padding({ left: 10, right: 10 })
      .backgroundColor($r('app.color.design_surface_solid'))
      .borderRadius(8)
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .focusable(false)
      .onClick(() => {
        this.onInsertFormat(insertText);
      })
  }

  build() {
    Scroll() {
      Row() {
        this.toolbarButton('B', '**', 14)
        this.toolbarButton('I', '*', 14)
        this.toolbarButton('~', '~~', 14)
        this.toolbarButton('`', '`', 14)
        this.toolbarButton('H1', '# ', 13)
        this.toolbarButton('H2', '## ', 13)
        this.toolbarButton('H3', '### ', 13)
        this.toolbarButton('>', '> ', 14)
        this.toolbarButton('-', '- ', 14)
        this.toolbarButton('1.', '1. ', 13)
        this.toolbarButton('-[]', '- [ ] ', 12)
        this.toolbarButton('—', '---\n', 14)
        Button('↶')
          .fontSize(15)
          .height(32)
          .padding({ left: 10, right: 10 })
          .backgroundColor($r('app.color.design_surface_solid'))
          .borderRadius(8)
          .border({ width: 1, color: $r('app.color.design_stroke') })
          .focusable(false)
          .opacity(this.undoDepth > 0 ? 1 : 0.4)
          .onClick(() => {
            this.onUndo();
          })
        Button('↷')
          .fontSize(15)
          .height(32)
          .padding({ left: 10, right: 10 })
          .backgroundColor($r('app.color.design_surface_solid'))
          .borderRadius(8)
          .border({ width: 1, color: $r('app.color.design_stroke') })
          .focusable(false)
          .opacity(this.redoDepth > 0 ? 1 : 0.4)
          .onClick(() => {
            this.onRedo();
          })
        Button('IMG')
          .fontSize(12)
          .height(32)
          .padding({ left: 8, right: 8 })
          .backgroundColor($r('app.color.design_surface_solid'))
          .borderRadius(8)
          .border({ width: 1, color: $r('app.color.design_stroke') })
          .focusable(false)
          .onClick(() => {
            this.onPickImage();
          })
        this.toolbarButton('[[', '[[', 12)
        this.toolbarButton('#', '#', 12)
      }
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(48)
    .backgroundColor($r('app.color.design_surface'))
    .backgroundBlurStyle(BlurStyle.Thin)
    .border({ width: { top: 1 }, color: $r('app.color.design_stroke') })
  }
}
