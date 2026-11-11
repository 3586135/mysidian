import { BacklinkItem, GraphData, MdPropType, MdProperty, OutlineEntry, UnlinkedMention } from '@ohos/domain';
import { GraphView } from './GraphView';

/**
 * 笔记信息面板：自定义页签栏承载 大纲 / 反链 / 标签 / 属性 / 图谱。
 *
 * 属性页签为可交互表单：布尔值用开关、列表用可增删的标签胶囊、
 * 日期用日期选择器，修改后由上层回写 frontmatter。
 */
@ComponentV2
export struct NoteInfoPanel {
  @Param outlineEntries: OutlineEntry[] = [];
  @Param backlinks: BacklinkItem[] = [];
  @Param unlinked: UnlinkedMention[] = [];
  @Param tags: string[] = [];
  @Param properties: MdProperty[] = [];
  @Param graph: GraphData = new GraphData();
  @Param currentTab: number = 0;
  @Event onTabChange: (index: number) => void = (index: number): void => {};
  @Event onOpenNote: (path: string) => void = (path: string): void => {};
  @Event onOpenTag: (tag: string) => void = (tag: string): void => {};
  @Event onOutlineClick: (entry: OutlineEntry) => void = (entry: OutlineEntry): void => {};
  /** 属性变更：value 用于标量，listValue 用于列表。 */
  @Event onUpdateProperty: (key: string, value: string, listValue: string[]) => void =
    (key: string, value: string, listValue: string[]): void => {};
  /** 新增属性。 */
  @Event onAddProperty: (key: string, type: MdPropType) => void =
    (key: string, type: MdPropType): void => {};
  /** 删除属性。 */
  @Event onRemoveProperty: (key: string) => void = (key: string): void => {};
  /** 未链接提及转双链。 */
  @Event onLinkMention: (path: string, title: string) => void =
    (path: string, title: string): void => {};
  /** 图谱节点点击。 */
  @Event onOpenGraphNode: (path: string) => void = (path: string): void => {};
  private tabsController: TabsController = new TabsController();
  /** 正在编辑的属性 key。 */
  @Local editingKey: string = '';
  @Local editValue: string = '';
  /** 列表属性新增项。 */
  @Local listInput: string = '';
  /** 是否正在新增属性。 */
  @Local addingProp: boolean = false;
  /** 新增属性的名称。 */
  @Local newPropKey: string = '';
  /** 新增属性的类型序号：0 文本 / 1 开关 / 2 列表。 */
  @Local newPropTypeIndex: number = 0;

  build() {
    Column() {
      Row() {
        this.tabButton(0, $r('app.string.tab_outline'))
        this.tabButton(1, $r('app.string.tab_backlinks'))
        this.tabButton(2, $r('app.string.tab_tags'))
        this.tabButton(3, $r('app.string.tab_props'))
        this.tabButton(4, $r('app.string.tab_graph'))
      }
      .width('100%')
      .height(48)

      Tabs({ index: this.currentTab, controller: this.tabsController }) {
        TabContent() {
          this.outlineView()
        }
        TabContent() {
          this.backlinksView()
        }
        TabContent() {
          this.tagsView()
        }
        TabContent() {
          this.propertiesView()
        }
        TabContent() {
          this.graphView()
        }
      }
      .barHeight(0)
      .scrollable(true)
      .width('100%')
      .layoutWeight(1)
      .onChange((index: number) => {
        this.onTabChange(index);
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  tabButton(index: number, label: Resource) {
    Column({ space: 3 }) {
      Text(label)
        .fontSize(14)
        .fontWeight(this.currentTab === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentTab === index ? $r('app.color.hm_accent')
          : $r('app.color.hm_text_secondary'))
        .maxLines(1)
      Column()
        .width(18)
        .height(2)
        .borderRadius(1)
        .backgroundColor(this.currentTab === index ? $r('app.color.hm_accent')
          : Color.Transparent)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.tabsController.changeIndex(index);
    })
  }

  @Builder
  outlineView() {
    Scroll() {
      Column() {
        if (this.outlineEntries.length === 0) {
          Text($r('app.string.empty_outline'))
            .fontSize(13)
            .fontColor($r('app.color.hm_text_secondary'))
        } else {
          ForEach(this.outlineEntries, (entry: OutlineEntry, index: number) => {
            Text(entry.text)
              .fontSize(14)
              .fontColor($r('app.color.hm_text_primary'))
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 8 + (entry.level - 1) * 12, top: 6, bottom: 6 })
              .borderRadius(6)
              .onClick(() => {
                this.onOutlineClick(entry);
              })
          }, (entry: OutlineEntry, index: number): string => `outline_${index}`)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  backlinksView() {
    Scroll() {
      Column() {
        if (this.backlinks.length === 0 && this.unlinked.length === 0) {
          Text($r('app.string.empty_backlinks'))
            .fontSize(13)
            .fontColor($r('app.color.hm_text_secondary'))
        } else {
          if (this.backlinks.length > 0) {
            Text($r('app.string.backlinks_linked'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.hm_text_secondary'))
              .width('100%')
              .margin({ top: 8, bottom: 2 })
            ForEach(this.backlinks, (item: BacklinkItem, index: number) => {
              Column() {
                Text(item.sourceTitle)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.hm_accent'))
                  .width('100%')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.context)
                  .fontSize(12)
                  .fontColor($r('app.color.hm_text_secondary'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .margin({ top: 2 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(10)
              .borderRadius(10)
              .backgroundColor($r('app.color.hm_hover_bg'))
              .margin({ top: 6 })
              .onClick(() => {
                this.onOpenNote(item.sourcePath);
              })
            }, (item: BacklinkItem, index: number): string => `backlink_${index}`)
          }
          if (this.unlinked.length > 0) {
            Text($r('app.string.backlinks_unlinked'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.hm_text_secondary'))
              .width('100%')
              .margin({ top: 12, bottom: 2 })
            ForEach(this.unlinked, (item: UnlinkedMention, index: number) => {
              Column() {
                Row() {
                  Text(item.title)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.hm_text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  Text($r('app.string.backlinks_link_it'))
                    .fontSize(12)
                    .fontColor($r('app.color.hm_accent'))
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .borderRadius(8)
                    .backgroundColor($r('app.color.hm_accent_weak'))
                    .onClick(() => {
                      this.onLinkMention(item.path, item.title);
                    })
                }
                .width('100%')
                Text(item.context)
                  .fontSize(12)
                  .fontColor($r('app.color.hm_text_secondary'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .margin({ top: 2 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(10)
              .borderRadius(10)
              .backgroundColor($r('app.color.hm_hover_bg'))
              .margin({ top: 6 })
              .onClick(() => {
                this.onOpenNote(item.path);
              })
            }, (item: UnlinkedMention, index: number): string => `unlinked_${index}`)
          }
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  tagsView() {
    Scroll() {
      Column() {
        if (this.tags.length === 0) {
          Text($r('app.string.empty_tags'))
            .fontSize(13)
            .fontColor($r('app.color.hm_text_secondary'))
        } else {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.tags, (tag: string, index: number) => {
              Text(`#${tag}`)
                .fontSize(13)
                .fontColor($r('app.color.hm_accent'))
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .borderRadius(10)
                .backgroundColor($r('app.color.hm_accent_weak'))
                .margin({ right: 6, top: 6 })
                .onClick(() => {
                  this.onOpenTag(tag);
                })
            }, (tag: string, index: number): string => `tag_${index}`)
          }
          .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  propertiesView() {
    Scroll() {
      Column() {
        if (this.properties.length === 0) {
          Text($r('app.string.empty_props'))
            .fontSize(13)
            .fontColor($r('app.color.hm_text_secondary'))
        } else {
          ForEach(this.properties, (property: MdProperty, index: number) => {
            this.propertyRow(property)
          }, (property: MdProperty, index: number): string => `prop_${property.key}`)
        }
        if (this.addingProp) {
          this.newPropertyForm()
        } else {
          Text($r('app.string.props_add_new'))
            .fontSize(13)
            .fontColor($r('app.color.hm_accent'))
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(8)
            .backgroundColor($r('app.color.hm_hover_bg'))
            .margin({ top: 10 })
            .onClick(() => {
              this.addingProp = true;
              this.newPropKey = '';
              this.newPropTypeIndex = 0;
            })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .height('100%')
  }

  /** 新增属性表单：属性名 + 类型选择。 */
  @Builder
  newPropertyForm() {
    Column() {
      TextInput({ placeholder: $r('app.string.props_key_hint'), text: this.newPropKey })
        .fontSize(13)
        .height(32)
        .width('100%')
        .backgroundColor($r('app.color.hm_input_bg'))
        .placeholderColor($r('app.color.hm_text_secondary'))
        .onChange((value: string): void => {
          this.newPropKey = value;
        })
      Row() {
        this.propTypeChip(0, $r('app.string.props_type_text'))
        this.propTypeChip(1, $r('app.string.props_type_bool'))
        this.propTypeChip(2, $r('app.string.props_type_list'))
      }
      .width('100%')
      .margin({ top: 8 })
      Row() {
        Text($r('app.string.props_add'))
          .fontSize(13)
          .fontColor($r('app.color.hm_accent'))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            this.commitNewProperty();
          })
        Text($r('app.string.dialog_cancel'))
          .fontSize(13)
          .fontColor($r('app.color.hm_text_secondary'))
          .padding({ left: 12, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            this.addingProp = false;
          })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .margin({ top: 10 })
  }

  /** 属性类型选择胶囊。 */
  @Builder
  propTypeChip(index: number, label: Resource) {
    Text(label)
      .fontSize(12)
      .fontColor(this.newPropTypeIndex === index ? $r('app.color.hm_accent')
        : $r('app.color.hm_text_secondary'))
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .margin({ right: 6 })
      .borderRadius(10)
      .backgroundColor(this.newPropTypeIndex === index ? $r('app.color.hm_accent_weak')
        : $r('app.color.hm_hover_bg'))
      .onClick(() => {
        this.newPropTypeIndex = index;
      })
  }

  /** 提交新增属性。 */
  private commitNewProperty(): void {
    const key: string = this.newPropKey.trim();
    if (key.length === 0) {
      return;
    }
    let type: MdPropType = MdPropType.STRING;
    if (this.newPropTypeIndex === 1) {
      type = MdPropType.BOOLEAN;
    } else if (this.newPropTypeIndex === 2) {
      type = MdPropType.LIST;
    }
    this.onAddProperty(key, type);
    this.addingProp = false;
    this.newPropKey = '';
    this.newPropTypeIndex = 0;
  }

  /** 单个属性的可交互表单行。 */
  @Builder
  propertyRow(property: MdProperty) {
    Column() {
      Row() {
        Text(property.key)
          .fontSize(13)
          .fontColor($r('app.color.hm_text_secondary'))
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(11)
          .fontColor([$r('app.color.hm_text_secondary')])
          .width(18)
          .height(18)
          .margin({ right: 6 })
          .onClick(() => {
            this.onRemoveProperty(property.key);
          })
        if (property.type === MdPropType.BOOLEAN) {
          Toggle({ type: ToggleType.Switch, isOn: property.value === 'true' })
            .selectedColor($r('app.color.hm_accent'))
            .onChange((isOn: boolean): void => {
              this.onUpdateProperty(property.key, isOn ? 'true' : 'false', []);
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (property.type === MdPropType.LIST) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(property.listValue, (item: string, itemIndex: number) => {
            Row() {
              Text(item)
                .fontSize(12)
                .fontColor($r('app.color.hm_text_primary'))
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(11)
                .fontColor([$r('app.color.hm_text_secondary')])
                .width(16)
                .height(16)
                .margin({ left: 4 })
                .onClick(() => {
                  this.removeListItem(property, itemIndex);
                })
            }
            .padding({ left: 8, right: 6, top: 3, bottom: 3 })
            .borderRadius(10)
            .backgroundColor($r('app.color.hm_hover_bg'))
            .margin({ right: 6, top: 6 })
          }, (item: string, itemIndex: number): string => `pv_${property.key}_${itemIndex}`)
        }
        .width('100%')
        Row() {
          TextInput({ placeholder: $r('app.string.props_new_item'), text: this.listInput })
            .fontSize(12)
            .height(30)
            .layoutWeight(1)
            .backgroundColor($r('app.color.hm_input_bg'))
            .placeholderColor($r('app.color.hm_text_secondary'))
            .onChange((value: string): void => {
              this.listInput = value;
            })
          Button($r('app.string.props_add'))
            .type(ButtonType.Capsule)
            .height(30)
            .fontSize(12)
            .backgroundColor($r('app.color.hm_hover_bg'))
            .fontColor($r('app.color.hm_text_primary'))
            .margin({ left: 6 })
            .onClick(() => {
              this.addListItem(property);
            })
        }
        .width('100%')
        .margin({ top: 6 })
      } else if (property.type !== MdPropType.BOOLEAN) {
        if (this.editingKey === property.key) {
          Row() {
            TextInput({ text: this.editValue })
              .fontSize(13)
              .height(32)
              .layoutWeight(1)
              .backgroundColor($r('app.color.hm_input_bg'))
              .onChange((value: string): void => {
                this.editValue = value;
              })
              .onSubmit(() => {
                this.commitEdit(property);
              })
            Text($r('app.string.props_save'))
              .fontSize(12)
              .fontColor($r('app.color.hm_accent'))
              .padding({ left: 8, right: 4 })
              .onClick(() => {
                this.commitEdit(property);
              })
            Text($r('app.string.dialog_cancel'))
              .fontSize(12)
              .fontColor($r('app.color.hm_text_secondary'))
              .padding({ left: 4 })
              .onClick(() => {
                this.editingKey = '';
              })
          }
          .width('100%')
          .margin({ top: 4 })
        } else {
          Row() {
            Text(this.propertyValue(property))
              .fontSize(13)
              .fontColor($r('app.color.hm_text_primary'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.isDateLike(property.value)) {
              Text($r('app.string.props_pick_date'))
                .fontSize(12)
                .fontColor($r('app.color.hm_accent'))
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(8)
                .backgroundColor($r('app.color.hm_accent_weak'))
                .onClick(() => {
                  this.pickDate(property);
                })
            }
          }
          .width('100%')
          .margin({ top: 4 })
          .onClick(() => {
            this.editingKey = property.key;
            this.editValue = property.value;
          })
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 8, bottom: 8 })
    .border({ width: { bottom: 1 }, color: $r('app.color.hm_divider') })
  }

  /** 局部关系图谱。 */
  @Builder
  graphView() {
    Column() {
      if (this.graph.nodes.length <= 1) {
        Text($r('app.string.graph_empty'))
          .fontSize(13)
          .fontColor($r('app.color.hm_text_secondary'))
      } else {
        GraphView({
          graph: this.graph,
          canvasWidth: 280,
          canvasHeight: 240,
          onOpenNode: (path: string): void => {
            this.onOpenGraphNode(path);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  private propertyValue(property: MdProperty): string {
    if (property.listValue.length > 0) {
      return property.listValue.join(', ');
    }
    return property.value;
  }

  /** 提交标量属性编辑。 */
  private commitEdit(property: MdProperty): void {
    this.editingKey = '';
    this.onUpdateProperty(property.key, this.editValue, []);
  }

  /** 追加列表属性项。 */
  private addListItem(property: MdProperty): void {
    const value: string = this.listInput.trim();
    if (value.length === 0) {
      return;
    }
    const next: string[] = property.listValue.slice();
    next.push(value);
    this.listInput = '';
    this.onUpdateProperty(property.key, '', next);
  }

  /** 删除列表属性项。 */
  private removeListItem(property: MdProperty, index: number): void {
    const next: string[] = property.listValue.slice();
    if (index < 0 || index >= next.length) {
      return;
    }
    next.splice(index, 1);
    this.onUpdateProperty(property.key, '', next);
  }

  /** 判断字符串是否为日期（YYYY-MM-DD）。 */
  private isDateLike(value: string): boolean {
    return /^\d{4}-\d{2}-\d{2}$/.test(value.trim());
  }

  /** 打开日期选择器。 */
  private pickDate(property: MdProperty): void {
    const selected: Date = this.parseDate(property.value);
    this.getUIContext().showDatePickerDialog({
      start: new Date(2000, 0, 1),
      end: new Date(2100, 0, 1),
      selected: selected,
      onDateAccept: (value: Date): void => {
        const month: string = value.getMonth() + 1 < 10
          ? `0${value.getMonth() + 1}` : `${value.getMonth() + 1}`;
        const day: string = value.getDate() < 10 ? `0${value.getDate()}` : `${value.getDate()}`;
        this.onUpdateProperty(property.key, `${value.getFullYear()}-${month}-${day}`, []);
      }
    });
  }

  /** 解析日期字符串，失败时返回今天。 */
  private parseDate(value: string): Date {
    const match: RegExpExecArray | null = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim());
    if (match === null) {
      return new Date();
    }
    return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  }
}
