/**
 * 编辑模式底部格式化工具栏（单行横向滚动胶囊条，避免多行换行占用视口）。
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
  chipButton(label: string, fontSize: number, hPad: number, btnOpacity: number, onTap: () => void) {
    Button(label)
      .type(ButtonType.Normal)
      .fontSize(fontSize)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.design_text_primary'))
      .height(32)
      .constraintSize({ minWidth: 34 })
      .padding({ left: hPad, right: hPad })
      .backgroundColor($r('app.color.design_elevated'))
      .borderRadius(10)
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .focusable(false)
      .opacity(btnOpacity)
      .onClick(() => {
        onTap();
      })
  }

  @Builder
  toolbarButton(label: string, insertText: string, fontSize: number) {
    this.chipButton(label, fontSize, 10, 1, (): void => {
      this.onInsertFormat(insertText);
    })
  }

  build() {
    Scroll() {
      Row({ space: 6 }) {
        this.toolbarButton('B', '**', 13)
        this.toolbarButton('I', '*', 13)
        this.toolbarButton('~', '~~', 13)
        this.toolbarButton('`', '`', 13)
        this.toolbarButton('H1', '# ', 12)
        this.toolbarButton('H2', '## ', 12)
        this.toolbarButton('H3', '### ', 12)
        this.toolbarButton('>', '> ', 13)
        this.toolbarButton('-', '- ', 13)
        this.toolbarButton('1.', '1. ', 12)
        this.toolbarButton('-[]', '- [ ] ', 11)
        this.toolbarButton('—', '---\n', 13)
        this.chipButton('↶', 14, 10, this.undoDepth > 0 ? 1 : 0.4, (): void => {
          this.onUndo();
        })
        this.chipButton('↷', 14, 10, this.redoDepth > 0 ? 1 : 0.4, (): void => {
          this.onRedo();
        })
        this.chipButton('IMG', 11, 9, 1, (): void => {
          this.onPickImage();
        })
        this.toolbarButton('[[', '[[', 12)
        this.toolbarButton('#', '#', 12)
      }
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 12, right: 12 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height(48)
    .backgroundColor($r('app.color.design_glass_bg'))
    .backgroundBlurStyle(BlurStyle.Thin)
    .border({ width: { top: 1 }, color: $r('app.color.design_divider') })
  }
}
