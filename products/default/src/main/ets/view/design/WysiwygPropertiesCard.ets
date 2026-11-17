import { MdPropType, MdProperty } from '@ohos/domain';
import { FrontmatterParser, FrontmatterSerializer } from '@ohos/markdown';

/**
 * 编辑模式顶部的可折叠笔记属性卡片（对标 Obsidian Live Preview 顶部属性区）。
 *
 * 全部变更仅作用于内存中的 frontmatterRaw 草稿，
 * 与正文编辑原子提交（点击保存时落盘，取消时整体丢弃）。
 */
@ComponentV2
export struct WysiwygPropertiesCard {
  @Param hasFrontmatter: boolean = false;
  @Param frontmatterRaw: string = '';
  @Param fontSize: number = 15;
  @Event onChange: (hasFm: boolean, nextRaw: string) => void =
    (_hasFm: boolean, _nextRaw: string): void => {};

  @Local expanded: boolean = false;
  @Local editingKey: string = '';
  @Local editValue: string = '';
  @Local addingProp: boolean = false;
  @Local newPropKey: string = '';
  @Local newPropType: number = 0;
  @Local listInputKey: string = '';
  @Local listInputText: string = '';

  aboutToAppear(): void {
    this.expanded = this.hasFrontmatter && this.properties.length > 0;
  }

  /** 缓存的属性解析结果：仅在 frontmatterRaw / hasFrontmatter 变化时重算，
   *  避免 build() 中每次渲染重复解析 6 次。 */
  @Computed
  get properties(): MdProperty[] {
    if (!this.hasFrontmatter && this.frontmatterRaw.trim().length === 0) {
      return [];
    }
    const lines: string[] = ['---', ...this.frontmatterRaw.split('\n'), '---'];
    return FrontmatterParser.parse(lines).frontmatter.properties;
  }

  private applyPropertyChanges(properties: MdProperty[], removedKeys: string[] = []): void {
    const baseDoc: string = this.hasFrontmatter || this.frontmatterRaw.trim().length > 0
      ? `---\n${this.frontmatterRaw}\n---\n`
      : '';
    const rebuilt: string = FrontmatterSerializer.rebuild(baseDoc, properties, removedKeys);
    const lines: string[] = rebuilt.replace(/\r\n/g, '\n').split('\n');
    let end: number = -1;
    if (lines.length > 0 && lines[0].trim() === '---') {
      for (let i: number = 1; i < lines.length; i++) {
        if (lines[i].trim() === '---') {
          end = i;
          break;
        }
      }
    }
    if (end > 0) {
      const nextRaw: string = lines.slice(1, end).join('\n');
      const hasAny: boolean = nextRaw.trim().length > 0;
      this.onChange(hasAny, hasAny ? nextRaw : '');
    } else {
      this.onChange(false, '');
    }
  }

  private commitScalarEdit(prop: MdProperty): void {
    const props: MdProperty[] = this.properties;
    for (const item of props) {
      if (item.key === prop.key && item.type !== MdPropType.MAP && item.type !== MdPropType.LIST) {
        item.value = this.editValue;
        break;
      }
    }
    this.editingKey = '';
    this.applyPropertyChanges(props);
  }

  private toggleBool(prop: MdProperty, nextVal: boolean): void {
    const props: MdProperty[] = this.properties;
    for (const item of props) {
      if (item.key === prop.key) {
        item.value = nextVal ? 'true' : 'false';
        break;
      }
    }
    this.applyPropertyChanges(props);
  }

  private removeListItem(prop: MdProperty, idx: number): void {
    const props: MdProperty[] = this.properties;
    for (const item of props) {
      if (item.key === prop.key && item.type === MdPropType.LIST) {
        item.listValue = item.listValue.filter((_v: string, i: number): boolean => i !== idx);
        break;
      }
    }
    this.applyPropertyChanges(props);
  }

  private addListItem(prop: MdProperty): void {
    const text: string = this.listInputText.trim();
    if (text.length === 0) {
      return;
    }
    const props: MdProperty[] = this.properties;
    for (const item of props) {
      if (item.key === prop.key && item.type === MdPropType.LIST) {
        item.listValue = [...item.listValue, text];
        break;
      }
    }
    this.listInputText = '';
    this.listInputKey = '';
    this.applyPropertyChanges(props);
  }

  private removeProp(key: string): void {
    const props: MdProperty[] = this.properties.filter((p: MdProperty): boolean => p.key !== key);
    this.applyPropertyChanges(props, [key]);
  }

  private commitNewProp(): void {
    const key: string = this.newPropKey.trim();
    if (key.length === 0) {
      return;
    }
    const props: MdProperty[] = this.properties;
    for (const p of props) {
      if (p.key === key) {
        this.addingProp = false;
        this.newPropKey = '';
        return;
      }
    }
    const created: MdProperty = new MdProperty();
    created.key = key;
    if (this.newPropType === 1) {
      created.type = MdPropType.BOOLEAN;
      created.value = 'false';
    } else if (this.newPropType === 2) {
      created.type = MdPropType.LIST;
      created.listValue = [];
    } else {
      created.type = MdPropType.STRING;
      created.value = '';
    }
    props.push(created);
    this.addingProp = false;
    this.newPropKey = '';
    this.newPropType = 0;
    this.expanded = true;
    this.applyPropertyChanges(props);
  }

  @Builder
  propRow(prop: MdProperty) {
    Row() {
      Text(prop.key)
        .fontSize(Math.max(12, this.fontSize - 2))
        .fontColor($r('app.color.design_text_secondary'))
        .width(88)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })

      Column() {
        if (prop.type === MdPropType.MAP) {
          Text(prop.rawBlock)
            .fontSize(12)
            .fontColor($r('app.color.design_text_secondary'))
            .fontFamily('monospace')
            .width('100%')
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else if (prop.type === MdPropType.BOOLEAN) {
          Toggle({ type: ToggleType.Switch, isOn: prop.value === 'true' })
            .selectedColor($r('app.color.design_accent'))
            .height(26)
            .onChange((isOn: boolean): void => {
              this.toggleBool(prop, isOn);
            })
        } else if (prop.type === MdPropType.LIST) {
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            ForEach(prop.listValue, (val: string, idx: number) => {
              Row({ space: 4 }) {
                Text(prop.key.toLowerCase() === 'tags' ? `#${val.replace(/^#/, '')}` : val)
                  .fontSize(12)
                  .fontColor(prop.key.toLowerCase() === 'tags'
                    ? $r('app.color.design_accent') : $r('app.color.design_text_primary'))
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(10)
                  .fontColor([$r('app.color.design_text_secondary')])
                  .onClick(() => {
                    this.removeListItem(prop, idx);
                  })
              }
              .padding({ left: 8, right: 6, top: 3, bottom: 3 })
              .borderRadius(9)
              .backgroundColor(prop.key.toLowerCase() === 'tags'
                ? $r('app.color.design_accent_weak') : $r('app.color.design_surface_solid'))
              .margin({ right: 6, bottom: 4 })
            }, (val: string, idx: number): string => `wp_${prop.key}_${idx}_${val}`)

            if (this.listInputKey === prop.key) {
              TextInput({ placeholder: $r('app.string.props_new_item'), text: this.listInputText })
                .width(136)
                .height(34)
                .fontSize(12)
                .padding({ left: 10, right: 10, top: 0, bottom: 0 })
                .placeholderFont({ size: 12 })
                .borderRadius(9)
                .backgroundColor($r('app.color.design_surface_solid'))
                .fontColor($r('app.color.design_text_primary'))
                .placeholderColor($r('app.color.design_text_secondary'))
                .caretColor($r('app.color.design_accent'))
                .onChange((v: string): void => {
                  this.listInputText = v;
                })
                .onSubmit(() => {
                  this.addListItem(prop);
                })
            } else {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(13)
                .fontColor([$r('app.color.design_accent')])
                .padding(5)
                .borderRadius(9)
                .backgroundColor($r('app.color.design_accent_weak'))
                .margin({ bottom: 4 })
                .onClick(() => {
                  this.listInputKey = prop.key;
                  this.listInputText = '';
                })
            }
          }
          .width('100%')
        } else if (this.editingKey === prop.key) {
          Row({ space: 6 }) {
            TextInput({ text: this.editValue })
              .layoutWeight(1)
              .height(34)
              .fontSize(13)
              .padding({ left: 10, right: 10, top: 0, bottom: 0 })
              .borderRadius(8)
              .backgroundColor($r('app.color.design_surface_solid'))
              .fontColor($r('app.color.design_text_primary'))
              .caretColor($r('app.color.design_accent'))
              .border({ width: 1, color: $r('app.color.design_stroke') })
              .onChange((v: string): void => {
                this.editValue = v;
              })
              .onSubmit(() => {
                this.commitScalarEdit(prop);
              })
            Text($r('app.string.props_save'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.design_accent'))
              .onClick(() => {
                this.commitScalarEdit(prop);
              })
          }
          .width('100%')
        } else {
          Text(prop.value.length > 0 ? prop.value : '—')
            .fontSize(Math.max(12, this.fontSize - 2))
            .fontColor(prop.value.length > 0
              ? $r('app.color.design_text_primary') : $r('app.color.design_text_secondary'))
            .width('100%')
            .padding({ top: 4, bottom: 4 })
            .onClick(() => {
              this.editingKey = prop.key;
              this.editValue = prop.value;
            })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(12)
        .fontColor([$r('app.color.design_text_secondary')])
        .padding(6)
        .onClick(() => {
          this.removeProp(prop.key);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 3, bottom: 3 })
  }

  build() {
    Column({ space: 4 }) {
      Row() {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.list_bullet'))
            .fontSize(14)
            .fontColor([$r('app.color.design_text_secondary')])
          Text($r('app.string.editor_props_title'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_text_secondary'))
          if (this.properties.length > 0) {
            Text(`${this.properties.length}`)
              .fontSize(11)
              .fontColor($r('app.color.design_accent'))
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .borderRadius(8)
              .backgroundColor($r('app.color.design_accent_weak'))
          }
          if (this.properties.length > 0) {
            SymbolGlyph(this.expanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
              .fontSize(12)
              .fontColor([$r('app.color.design_text_secondary')])
          }
        }
        .layoutWeight(1)
        .onClick(() => {
          if (this.properties.length > 0) {
            this.expanded = !this.expanded;
          } else {
            this.addingProp = !this.addingProp;
            this.expanded = true;
          }
        })

        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(13)
            .fontColor([$r('app.color.design_accent')])
          Text($r('app.string.editor_props_add'))
            .fontSize(12)
            .fontColor($r('app.color.design_accent'))
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(10)
        .backgroundColor($r('app.color.design_accent_weak'))
        .onClick(() => {
          this.addingProp = true;
          this.expanded = true;
          this.newPropKey = '';
          this.newPropType = 0;
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.expanded && this.properties.length > 0) {
        Scroll() {
          Column({ space: 2 }) {
            ForEach(this.properties, (prop: MdProperty, idx: number) => {
              this.propRow(prop)
            }, (prop: MdProperty, idx: number): string => `wprop_${idx}_${prop.key}_${prop.value}_${prop.listValue.length}`)
          }
          .width('100%')
          .padding({ top: 4 })
        }
        .width('100%')
        .constraintSize({ maxHeight: 196 })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      }

      if (this.addingProp) {
        Column({ space: 8 }) {
          TextInput({ placeholder: $r('app.string.props_key_hint'), text: this.newPropKey })
            .width('100%')
            .height(38)
            .fontSize(13)
            .padding({ left: 12, right: 12, top: 0, bottom: 0 })
            .placeholderFont({ size: 13 })
            .borderRadius(10)
            .backgroundColor($r('app.color.design_surface_solid'))
            .border({ width: 1, color: $r('app.color.design_stroke') })
            .fontColor($r('app.color.design_text_primary'))
            .placeholderColor($r('app.color.design_text_secondary'))
            .caretColor($r('app.color.design_accent'))
            .onChange((v: string): void => {
              this.newPropKey = v;
            })
            .onSubmit(() => {
              this.commitNewProp();
            })

          Row({ space: 6 }) {
            this.typePill(0, $r('app.string.props_type_text'))
            this.typePill(1, $r('app.string.props_type_bool'))
            this.typePill(2, $r('app.string.props_type_list'))
            Blank()
            Text($r('app.string.dialog_cancel'))
              .fontSize(12)
              .fontColor($r('app.color.design_text_secondary'))
              .padding({ left: 6, right: 6, top: 5, bottom: 5 })
              .onClick(() => {
                this.addingProp = false;
              })
            Text($r('app.string.props_add'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.design_accent'))
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(9)
              .backgroundColor($r('app.color.design_accent_weak'))
              .onClick(() => {
                this.commitNewProp();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ top: 4 })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .borderRadius(14)
    .backgroundColor($r('app.color.design_elevated'))
    .border({ width: 1, color: $r('app.color.design_stroke') })
  }

  @Builder
  typePill(idx: number, label: Resource) {
    Text(label)
      .fontSize(11)
      .fontColor(this.newPropType === idx ? $r('app.color.design_accent') : $r('app.color.design_text_secondary'))
      .padding({ left: 9, right: 9, top: 3, bottom: 3 })
      .borderRadius(8)
      .backgroundColor(this.newPropType === idx
        ? $r('app.color.design_accent_weak') : $r('app.color.design_surface_solid'))
      .onClick(() => {
        this.newPropType = idx;
      })
  }
}
