/**
 * 编辑器页内查找 / 替换栏。
 *
 * 只负责输入与按钮；匹配计算、选区与文本替换归 EditorPane（经 @Event 上抛）。
 * 所有按钮 focusable(false)，避免点按钮时抢走输入焦点。
 */
@ComponentV2
export struct FindReplaceBar {
  /** 当前关键词的匹配总数。 */
  @Param matchCount: number = 0;
  /** 当前匹配序号（0 起，-1 表示尚未定位）。 */
  @Param currentIndex: number = -1;
  @Event onQueryChange: (keyword: string) => void = (_keyword: string): void => {};
  @Event onPrev: () => void = (): void => {};
  @Event onNext: () => void = (): void => {};
  @Event onReplace: (replacement: string) => void = (_replacement: string): void => {};
  @Event onReplaceAll: (replacement: string) => void = (_replacement: string): void => {};
  @Event onClose: () => void = (): void => {};

  @Local keyword: string = '';
  @Local replacement: string = '';
  @Local showReplace: boolean = false;

  /** 计数文案：未输入关键词时为空，无匹配显示 0/0。 */
  private countText(): string {
    if (this.keyword.length === 0) {
      return '';
    }
    const shown: number = this.matchCount === 0 ? 0 : this.currentIndex + 1;
    return `${shown}/${this.matchCount}`;
  }

  @Builder
  iconButton(symbol: Resource, label: Resource, enabled: boolean, action: () => void) {
    SymbolGlyph(symbol)
      .fontSize(20)
      .fontColor([$r('app.color.design_text_primary')])
      .width(36)
      .height(36)
      .opacity(enabled ? 1 : 0.4)
      .focusable(false)
      .accessibilityText(label)
      .onClick(() => {
        if (enabled) {
          action();
        }
      })
  }

  @Builder
  textAction(label: Resource, enabled: boolean, action: () => void) {
    Button(label)
      .fontSize(13)
      .height(32)
      .padding({ left: 12, right: 12 })
      .backgroundColor($r('app.color.design_surface_solid'))
      .fontColor($r('app.color.design_accent'))
      .borderRadius(8)
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .focusable(false)
      .opacity(enabled ? 1 : 0.4)
      .onClick(() => {
        if (enabled) {
          action();
        }
      })
  }

  build() {
    Column({ space: 6 }) {
      Row() {
        this.iconButton(
          this.showReplace ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'),
          $r('app.string.find_toggle_replace'), true, (): void => {
            this.showReplace = !this.showReplace;
          })
        TextInput({ placeholder: $r('app.string.find_placeholder'), text: this.keyword })
          .layoutWeight(1)
          .height(36)
          .fontSize(15)
          .fontColor($r('app.color.design_text_primary'))
          .placeholderColor($r('app.color.design_text_secondary'))
          .caretColor($r('app.color.design_accent'))
          .backgroundColor($r('app.color.design_surface_solid'))
          .borderRadius(10)
          .enterKeyType(EnterKeyType.Search)
          .onChange((value: string) => {
            this.keyword = value;
            this.onQueryChange(value);
          })
          .onSubmit(() => {
            this.onNext();
          })
        Text(this.countText())
          .fontSize(12)
          .fontColor($r('app.color.design_text_secondary'))
          .constraintSize({ minWidth: 40 })
          .textAlign(TextAlign.Center)
        this.iconButton($r('sys.symbol.chevron_up'), $r('app.string.find_prev'),
          this.matchCount > 0, (): void => {
            this.onPrev();
          })
        this.iconButton($r('sys.symbol.chevron_down'), $r('app.string.find_next'),
          this.matchCount > 0, (): void => {
            this.onNext();
          })
        this.iconButton($r('sys.symbol.xmark'), $r('app.string.find_close'), true, (): void => {
          this.onClose();
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.showReplace) {
        Row({ space: 8 }) {
          TextInput({ placeholder: $r('app.string.replace_placeholder'), text: this.replacement })
            .layoutWeight(1)
            .height(36)
            .fontSize(15)
            .fontColor($r('app.color.design_text_primary'))
            .placeholderColor($r('app.color.design_text_secondary'))
            .caretColor($r('app.color.design_accent'))
            .backgroundColor($r('app.color.design_surface_solid'))
            .borderRadius(10)
            .onChange((value: string) => {
              this.replacement = value;
            })
          this.textAction($r('app.string.replace_one'), this.matchCount > 0, (): void => {
            this.onReplace(this.replacement);
          })
          this.textAction($r('app.string.replace_all'), this.matchCount > 0, (): void => {
            this.onReplaceAll(this.replacement);
          })
        }
        .width('100%')
        .padding({ left: 36 })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 8, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.design_surface'))
    .border({ width: { bottom: 1 }, color: $r('app.color.design_stroke') })
  }
}
