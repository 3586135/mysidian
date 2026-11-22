/** 工具栏条目类别。 */
enum ChipKind {
  FORMAT,
  UNDO,
  REDO,
  PICK_IMAGE,
  PICK_ATTACHMENT,
  DIVIDER
}

/**
 * 工具栏命令定义：每项有稳定 key（未来可做使用统计、自定义排序、子菜单），
 * syntax 与所见即所得引擎（WysiwygEditorEngine.applyToolbarAction）共用同一命令字。
 */
class ToolbarChipSpec {
  public readonly kind: ChipKind;
  public readonly key: string;
  public readonly label: ResourceStr;
  public readonly a11yRes: Resource;
  public readonly syntax: string;
  public readonly fontSize: number;

  constructor(kind: ChipKind, key: string, label: ResourceStr, a11yRes: Resource,
    syntax: string, fontSize: number) {
    this.kind = kind;
    this.key = key;
    this.label = label;
    this.a11yRes = a11yRes;
    this.syntax = syntax;
    this.fontSize = fontSize;
  }
}

/**
 * 工具栏命令表（参考 obsidian-editing-toolbar 的命令化设计）：
 * 行内格式 | 标题（单键循环）| 块级 | 历史 | 插入，五组渐进披露。
 */
const TOOLBAR_CHIPS: ToolbarChipSpec[] = [
  new ToolbarChipSpec(ChipKind.FORMAT, 'bold', 'B', $r('app.string.toolbar_a11y_bold'), '**', 13),
  new ToolbarChipSpec(ChipKind.FORMAT, 'italic', 'I', $r('app.string.toolbar_a11y_italic'), '*', 13),
  new ToolbarChipSpec(ChipKind.FORMAT, 'strike', 'S', $r('app.string.toolbar_a11y_strike'), '~~', 13),
  new ToolbarChipSpec(ChipKind.FORMAT, 'highlight', '==', $r('app.string.toolbar_a11y_highlight'), '==', 12),
  new ToolbarChipSpec(ChipKind.FORMAT, 'code', '`', $r('app.string.toolbar_a11y_code'), '`', 13),
  new ToolbarChipSpec(ChipKind.DIVIDER, 'div_inline', '', $r('app.string.toolbar_a11y_bold'), '', 12),
  new ToolbarChipSpec(ChipKind.FORMAT, 'heading', 'H', $r('app.string.toolbar_a11y_heading'), 'heading', 13),
  new ToolbarChipSpec(ChipKind.DIVIDER, 'div_heading', '', $r('app.string.toolbar_a11y_bold'), '', 12),
  new ToolbarChipSpec(ChipKind.FORMAT, 'quote', '>', $r('app.string.toolbar_a11y_quote'), '> ', 13),
  new ToolbarChipSpec(ChipKind.FORMAT, 'bullet', '-', $r('app.string.toolbar_a11y_bullet'), '- ', 13),
  new ToolbarChipSpec(ChipKind.FORMAT, 'ordered', '1.', $r('app.string.toolbar_a11y_ordered'), '1. ', 12),
  new ToolbarChipSpec(ChipKind.FORMAT, 'task', $r('app.string.toolbar_task'), $r('app.string.toolbar_a11y_task'), '- [ ] ', 11),
  new ToolbarChipSpec(ChipKind.FORMAT, 'hr', '—', $r('app.string.toolbar_a11y_hr'), '---\n', 13),
  new ToolbarChipSpec(ChipKind.DIVIDER, 'div_block', '', $r('app.string.toolbar_a11y_bold'), '', 12),
  new ToolbarChipSpec(ChipKind.UNDO, 'undo', '↶', $r('app.string.toolbar_a11y_undo'), '', 14),
  new ToolbarChipSpec(ChipKind.REDO, 'redo', '↷', $r('app.string.toolbar_a11y_redo'), '', 14),
  new ToolbarChipSpec(ChipKind.DIVIDER, 'div_history', '', $r('app.string.toolbar_a11y_bold'), '', 12),
  new ToolbarChipSpec(ChipKind.PICK_IMAGE, 'image', $r('app.string.toolbar_image'), $r('app.string.toolbar_a11y_image'), '', 11),
  new ToolbarChipSpec(ChipKind.PICK_ATTACHMENT, 'attachment', $r('app.string.toolbar_attachment'), $r('app.string.toolbar_a11y_attachment'), '', 11),
  new ToolbarChipSpec(ChipKind.FORMAT, 'table', $r('app.string.toolbar_table'), $r('app.string.toolbar_a11y_table'), 'table', 11),
  new ToolbarChipSpec(ChipKind.FORMAT, 'wikilink', '[[', $r('app.string.toolbar_a11y_wikilink'), '[[', 12),
  new ToolbarChipSpec(ChipKind.FORMAT, 'tag', '#', $r('app.string.toolbar_a11y_tag'), '#', 12)
];

@ComponentV2
struct ToolbarChip {
  @Param label: ResourceStr = '';
  @Param fontSize: number = 12;
  @Param hPad: number = 10;
  @Param active: boolean = false;
  @Param tapEnabled: boolean = true;
  @Param a11yText: string = '';
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
      .enabled(this.tapEnabled)
      .opacity(this.tapEnabled ? 1 : 0.4)
      .accessibilityText(this.a11yText)
      .onClick(() => {
        this.onTap();
      })
  }
}

/**
 * 编辑模式底部格式化工具栏（单行横向滚动胶囊条）。
 * 命令化重构：
 * - 按钮来自 TOOLBAR_CHIPS 命令表，命令字与所见引擎共用，源码/所见两模式语义对齐；
 * - 五组渐进披露（行内/标题/块级/历史/插入），标题单键循环 H1→H4→正文；
 * - 撤销/重做为真实禁用态；内容溢出时右缘渐隐提示，屏外按钮可感知；
 * - 右侧固定「收起键盘」按钮；全部条目带无障碍朗读文本。
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
  @Event onPickAttachment: () => void = (): void => {};
  @Event onDismissKeyboard: () => void = (): void => {};

  /** 内容宽于视口时右缘渐隐提示（滚动条隐藏，溢出必须可感知）。 */
  @Local hasOverflow: boolean = false;
  private contentWidthVp: number = 0;
  private viewportWidthVp: number = 0;

  /** FORMAT 命令激活态映射（所见模式由引擎格式态驱动，源码模式由 EditorPane 置空）。 */
  private chipActive(spec: ToolbarChipSpec): boolean {
    if (spec.kind !== ChipKind.FORMAT) {
      return false;
    }
    switch (spec.key) {
      case 'bold':
        return this.activeBold;
      case 'italic':
        return this.activeItalic;
      case 'strike':
        return this.activeStrike;
      case 'highlight':
        return this.activeHighlight;
      case 'code':
        return this.activeCode;
      case 'heading':
        return this.activeHeading > 0;
      case 'quote':
        return this.activeBlockKind === 'quote';
      case 'bullet':
        return this.activeBlockKind === 'bullet';
      case 'ordered':
        return this.activeBlockKind === 'ordered';
      case 'task':
        return this.activeBlockKind === 'task';
      default:
        return false;
    }
  }

  /** 命令内容宽度/视口宽度变化后刷新溢出提示。 */
  private refreshOverflow(): void {
    this.hasOverflow = this.contentWidthVp > this.viewportWidthVp + 1;
  }

  /** 无障碍朗读文本（资源化文案，读取失败回退空串使用默认标签）。 */
  private resolveA11yText(res: Resource): string {
    try {
      const hostCtx = this.getUIContext().getHostContext();
      if (hostCtx !== undefined && hostCtx !== null) {
        return hostCtx.resourceManager.getStringSync(res.id);
      }
    } catch (error) {
    }
    return '';
  }

  @Builder
  chipView(spec: ToolbarChipSpec) {
    if (spec.kind === ChipKind.DIVIDER) {
      Divider()
        .vertical(true)
        .height(18)
        .strokeWidth(1)
        .color($r('app.color.design_divider'))
        .margin({ left: 3, right: 3 })
    } else if (spec.kind === ChipKind.UNDO) {
      ToolbarChip({
        label: spec.label, fontSize: spec.fontSize, hPad: 10, active: false,
        tapEnabled: this.undoDepth > 0, a11yText: this.resolveA11yText(spec.a11yRes),
        onTap: (): void => { this.onUndo(); }
      })
    } else if (spec.kind === ChipKind.REDO) {
      ToolbarChip({
        label: spec.label, fontSize: spec.fontSize, hPad: 10, active: false,
        tapEnabled: this.redoDepth > 0, a11yText: this.resolveA11yText(spec.a11yRes),
        onTap: (): void => { this.onRedo(); }
      })
    } else if (spec.kind === ChipKind.PICK_IMAGE) {
      ToolbarChip({
        label: spec.label, fontSize: spec.fontSize, hPad: 9, active: false, tapEnabled: true,
        a11yText: this.resolveA11yText(spec.a11yRes),
        onTap: (): void => { this.onPickImage(); }
      })
    } else if (spec.kind === ChipKind.PICK_ATTACHMENT) {
      ToolbarChip({
        label: spec.label, fontSize: spec.fontSize, hPad: 10, active: false, tapEnabled: true,
        a11yText: this.resolveA11yText(spec.a11yRes),
        onTap: (): void => { this.onPickAttachment(); }
      })
    } else {
      ToolbarChip({
        label: spec.key === 'heading'
          ? (this.activeHeading > 0 ? `H${this.activeHeading}` : 'H')
          : spec.label,
        fontSize: spec.fontSize,
        hPad: 10,
        active: this.chipActive(spec),
        tapEnabled: true,
        a11yText: this.resolveA11yText(spec.a11yRes),
        onTap: (): void => { this.onInsertFormat(spec.syntax); }
      })
    }
  }

  build() {
    Row() {
      Stack() {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(TOOLBAR_CHIPS, (spec: ToolbarChipSpec) => {
              this.chipView(spec)
            }, (spec: ToolbarChipSpec) => spec.key)
          }
          .height('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ left: 12, right: 12 })
          .onAreaChange((_oldArea: Area, newArea: Area): void => {
            this.contentWidthVp = Number(newArea.width);
            this.refreshOverflow();
          })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .height('100%')
        .onAreaChange((_oldArea: Area, newArea: Area): void => {
          this.viewportWidthVp = Number(newArea.width);
          this.refreshOverflow();
        })

        if (this.hasOverflow) {
          Row() {
            Column()
              .width(18)
              .height('100%')
              .linearGradient({
                angle: 0,
                colors: [[Color.Transparent, 0], [$r('app.color.design_glass_bg'), 1]]
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.End)
          .hitTestBehavior(HitTestMode.Transparent)
        }
      }
      .height('100%')
      .layoutWeight(1)

      Divider()
        .vertical(true)
        .height(24)
        .strokeWidth(1)
        .color($r('app.color.design_divider'))

      Button() {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(15)
          .fontColor([$r('app.color.design_text_primary')])
      }
      .type(ButtonType.Normal)
      .height(32)
      .padding({ left: 9, right: 9 })
      .backgroundColor($r('app.color.design_elevated'))
      .borderRadius(10)
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .focusable(false)
      .accessibilityText(this.resolveA11yText($r('app.string.toolbar_a11y_keyboard')))
      .margin({ left: 6, right: 8 })
      .onClick((): void => {
        this.onDismissKeyboard();
      })
    }
    .width('100%')
    .height(48)
    .backgroundColor($r('app.color.design_glass_bg'))
    .backgroundBlurStyle(BlurStyle.Thin)
    .border({ width: { top: 1 }, color: $r('app.color.design_divider') })
  }
}
