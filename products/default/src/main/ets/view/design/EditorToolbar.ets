@ComponentV2
struct ToolbarChip {
  @Param label: string = '';
  @Param fontSize: number = 12;
  @Param hPad: number = 10;
  @Param btnOpacity: number = 1;
  @Param active: boolean = false;
  @Event onTap: () => void = (): void => {};

  build() {
    Button(this.label)
      .type(ButtonType.Normal)
      .fontSize(this.fontSize)
      .fontWeight(this.active ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.active ? $r('app.color.design_accent') : $r('app.color.design_text_primary'))
      .height(32)
      .constraintSize({ minWidth: 34 })
      .padding({ left: this.hPad, right: this.hPad })
      .backgroundColor(this.active ? $r('app.color.design_accent_weak') : $r('app.color.design_elevated'))
      .borderRadius(10)
      .border({
        width: this.active ? 1.5 : 1,
        color: this.active ? $r('app.color.design_accent') : $r('app.color.design_stroke')
      })
      .focusable(false)
      .opacity(this.btnOpacity)
      .onClick(() => {
        this.onTap();
      })
  }
}

/**
 * 编辑模式底部格式化工具栏（单行横向滚动胶囊条，避免多行换行占用视口）。
 * 17 个按钮全部经 @Event 上抛，编辑逻辑归 EditorPane。
 */
@ComponentV2
export struct EditorToolbar {
  @Param undoDepth: number = 0;
  @Param redoDepth: number = 0;
  @Param activeBold: boolean = false;
  @Param activeItalic: boolean = false;
  @Param activeStrike: boolean = false;
  @Param activeHighlight: boolean = false;
  @Param activeCode: boolean = false;
  @Param activeHeading: number = 0;
  @Param activeBlockKind: string = '';
  @Event onInsertFormat: (syntax: string) => void = (_syntax: string): void => {};
  @Event onUndo: () => void = (): void => {};
  @Event onRedo: () => void = (): void => {};
  @Event onPickImage: () => void = (): void => {};

  build() {
    Scroll() {
      Row({ space: 6 }) {
        ToolbarChip({
          label: 'B', fontSize: 13, hPad: 10, btnOpacity: 1, active: this.activeBold,
          onTap: (): void => { this.onInsertFormat('**'); }
        })
        ToolbarChip({
          label: 'I', fontSize: 13, hPad: 10, btnOpacity: 1, active: this.activeItalic,
          onTap: (): void => { this.onInsertFormat('*'); }
        })
        ToolbarChip({
          label: '~', fontSize: 13, hPad: 10, btnOpacity: 1, active: this.activeStrike,
          onTap: (): void => { this.onInsertFormat('~~'); }
        })
        ToolbarChip({
          label: '==', fontSize: 12, hPad: 10, btnOpacity: 1, active: this.activeHighlight,
          onTap: (): void => { this.onInsertFormat('=='); }
        })
        ToolbarChip({
          label: '`', fontSize: 13, hPad: 10, btnOpacity: 1, active: this.activeCode,
          onTap: (): void => { this.onInsertFormat('`'); }
        })
        ToolbarChip({
          label: 'H1', fontSize: 12, hPad: 10, btnOpacity: 1, active: this.activeHeading === 1,
          onTap: (): void => { this.onInsertFormat('# '); }
        })
        ToolbarChip({
          label: 'H2', fontSize: 12, hPad: 10, btnOpacity: 1, active: this.activeHeading === 2,
          onTap: (): void => { this.onInsertFormat('## '); }
        })
        ToolbarChip({
          label: 'H3', fontSize: 12, hPad: 10, btnOpacity: 1, active: this.activeHeading === 3,
          onTap: (): void => { this.onInsertFormat('### '); }
        })
        ToolbarChip({
          label: '>', fontSize: 13, hPad: 10, btnOpacity: 1, active: this.activeBlockKind === 'quote',
          onTap: (): void => { this.onInsertFormat('> '); }
        })
        ToolbarChip({
          label: '-', fontSize: 13, hPad: 10, btnOpacity: 1, active: this.activeBlockKind === 'bullet',
          onTap: (): void => { this.onInsertFormat('- '); }
        })
        ToolbarChip({
          label: '1.', fontSize: 12, hPad: 10, btnOpacity: 1, active: this.activeBlockKind === 'ordered',
          onTap: (): void => { this.onInsertFormat('1. '); }
        })
        ToolbarChip({
          label: '-[]', fontSize: 11, hPad: 10, btnOpacity: 1, active: this.activeBlockKind === 'task',
          onTap: (): void => { this.onInsertFormat('- [ ] '); }
        })
        ToolbarChip({
          label: '—', fontSize: 13, hPad: 10, btnOpacity: 1, active: false,
          onTap: (): void => { this.onInsertFormat('---\n'); }
        })
        ToolbarChip({
          label: '↶', fontSize: 14, hPad: 10, btnOpacity: this.undoDepth > 0 ? 1 : 0.4, active: false,
          onTap: (): void => { this.onUndo(); }
        })
        ToolbarChip({
          label: '↷', fontSize: 14, hPad: 10, btnOpacity: this.redoDepth > 0 ? 1 : 0.4, active: false,
          onTap: (): void => { this.onRedo(); }
        })
        ToolbarChip({
          label: 'IMG', fontSize: 11, hPad: 9, btnOpacity: 1, active: false,
          onTap: (): void => { this.onPickImage(); }
        })
        ToolbarChip({
          label: '表格', fontSize: 12, hPad: 10, btnOpacity: 1, active: false,
          onTap: (): void => { this.onInsertFormat('table'); }
        })
        ToolbarChip({
          label: '[[', fontSize: 12, hPad: 10, btnOpacity: 1, active: false,
          onTap: (): void => { this.onInsertFormat('[['); }
        })
        ToolbarChip({
          label: '#', fontSize: 12, hPad: 10, btnOpacity: 1, active: false,
          onTap: (): void => { this.onInsertFormat('#'); }
        })
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
