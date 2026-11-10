import { DataViewTask, MdBlock, MdBlockType, MdInlineSegment, MdListItem } from '@ohos/domain';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { DataViewQuery } from '../parser/DataViewQuery';
import { InlineParser } from '../parser/InlineParser';
import { MdInlineFlattener } from './MdInlineFlattener';
import { MdInlineText } from './MdInlineText';
import { MdWebFallback } from './MdWebFallback';

/** 任务元数据标签。 */
class TaskChip {
  label: string = '';
  kind: string = '';
}

/**
 * 块级渲染器：按块类型输出原生 ArkUI 组件。
 */
@ComponentV2
export struct MdBlockView {
  @Param block: MdBlock = new MdBlock();
  @Param fontSize: number = 16;
  @Local copied: boolean = false;
  private inlineParser: InlineParser = new InlineParser();
  @Event onOpenLink: (target: string, kind: string) => void =
    (target: string, kind: string): void => {};
  @Event onOpenTag: (tag: string) => void = (tag: string): void => {};
  @Event onToggleTask: (rawLine: string, checked: boolean) => void =
    (rawLine: string, checked: boolean): void => {};
  @Event onLoadDataView: (query: string, onResult: (tasks: DataViewTask[]) => void) => void =
    (query: string, onResult: (tasks: DataViewTask[]) => void): void => {};
  @Event onToggleDataViewTask: (task: DataViewTask, checked: boolean) => void =
    (task: DataViewTask, checked: boolean): void => {};
  @Local dataTasks: DataViewTask[] = [];
  @Local dataLoaded: boolean = false;
  private dataViewQuery: DataViewQuery | null = null;
  @Local dataViewTableRows: string[][] = [];
  @Local dataViewListItems: string[] = [];
  @Local dataViewTableLoaded: boolean = false;
  @Local dataViewListLoaded: boolean = false;

  aboutToAppear(): void {
    if (this.block.type === MdBlockType.CODE && this.block.lang.trim().toLowerCase() === 'dataview') {
      const query: DataViewQuery = DataViewQuery.parse(this.block.rawContent);
      if (query.isTaskQuery()) {
        this.dataViewQuery = query;
        this.onLoadDataView(this.block.rawContent, (tasks: DataViewTask[]): void => {
          this.dataTasks = tasks;
          this.dataLoaded = true;
        });
      } else if (query.isTableQuery() && query.parsedOk) {
        this.dataViewQuery = query;
        this.dataViewTableRows = query.tableRows;
        this.dataViewTableLoaded = true;
      } else if (query.isListQuery() && query.parsedOk) {
        this.dataViewQuery = query;
        this.dataViewListItems = query.listItems;
        this.dataViewListLoaded = true;
      }
    }
  }

  private isDataViewQuery(): boolean {
    return this.dataViewQuery !== null;
  }

  build() {
    Column() {
      if (this.block.type === MdBlockType.HEADING) {
        this.headingView()
      } else if (this.block.type === MdBlockType.PARAGRAPH) {
        MdInlineText({
          segments: MdInlineFlattener.flatten(this.block.inlines),
          fontSize: this.fontSize,
          onOpenLink: (target: string, kind: string): void => {
            this.onOpenLink(target, kind);
          },
          onOpenTag: (tag: string): void => {
            this.onOpenTag(tag);
          }
        })
      } else if (this.block.type === MdBlockType.LIST) {
        this.listView()
      } else if (this.block.type === MdBlockType.CODE) {
        if (this.isDataViewQuery()) {
          if (this.dataViewQuery !== null && this.dataViewQuery.isTableQuery()) {
            this.dataViewTableView()
          } else if (this.dataViewQuery !== null && this.dataViewQuery.isListQuery()) {
            this.dataViewListView()
          } else {
            this.dataViewTaskView()
          }
        } else {
          this.codeView()
        }
      } else if (this.block.type === MdBlockType.QUOTE) {
        this.quoteView()
      } else if (this.block.type === MdBlockType.CALLOUT) {
        this.calloutView()
      } else if (this.block.type === MdBlockType.TABLE) {
        this.tableView()
      } else if (this.block.type === MdBlockType.THEMATIC_BREAK) {
        Divider()
          .color($r('sys.color.ohos_id_color_text_secondary'))
          .margin({ top: 8, bottom: 8 })
      } else if (this.block.type === MdBlockType.HTML) {
        MdWebFallback({
          html: this.block.rawContent,
          contentHeight: this.htmlHeight()
        })
        .width('100%')
      } else {
        this.rawView()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  headingView() {
    Row() {
      MdInlineText({
        segments: MdInlineFlattener.flatten(this.block.inlines),
        fontSize: this.headingFontSize(),
        onOpenLink: (target: string, kind: string): void => {
          this.onOpenLink(target, kind);
        },
        onOpenTag: (tag: string): void => {
          this.onOpenTag(tag);
        }
      })
    }
    .width('100%')
    .margin({ top: 12, bottom: 6 })
  }

  @Builder
  listView() {
    Column() {
      ForEach(this.block.items, (item: MdListItem, index: number) => {
        this.listItemView(item, 0)
      }, (item: MdListItem, index: number): string => `item_${index}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 4, bottom: 4 })
  }

  @Builder
  listItemView(item: MdListItem, depth: number) {
    Column() {
      Row() {
        Text(this.bulletText(item))
          .fontSize(this.fontSize)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width(24)
        if (item.isTask) {
          SymbolGlyph(item.checked ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.circle'))
            .fontSize(20)
            .fontColor([item.checked ? $r('sys.color.ohos_id_color_emphasize')
              : $r('sys.color.ohos_id_color_text_secondary')])
            .width(26)
            .margin({ top: 2 })
            .onClick(() => {
              this.onToggleTask(item.rawLine, !item.checked);
            })
        }
        Column() {
          MdInlineText({
            segments: MdInlineFlattener.flatten(item.inlines),
            fontSize: this.fontSize,
            onOpenLink: (target: string, kind: string): void => {
              this.onOpenLink(target, kind);
            },
            onOpenTag: (tag: string): void => {
              this.onOpenTag(tag);
            }
          })
          if (item.isTask && this.taskHasMeta(item)) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.taskChips(item), (chip: TaskChip) => {
                this.taskChipView(chip)
              }, (chip: TaskChip, index: number): string => `chip_${index}`)
            }
            .margin({ top: 2 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      ForEach(item.children, (child: MdListItem, index: number) => {
        this.listItemView(child, depth + 1)
      }, (child: MdListItem, index: number): string => `child_${depth}_${index}`)
    }
    .width('100%')
    .padding({ left: depth * 18 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 任务元数据标签。 */
  @Builder
  taskChipView(chip: TaskChip) {
    Text(chip.label)
      .fontSize(10)
      .fontColor(this.chipColor(chip.kind))
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .borderRadius(8)
      .backgroundColor($r('app.color.md_chip_bg'))
      .margin({ right: 4, bottom: 2 })
  }

  private chipColor(kind: string): ResourceColor {
    if (kind === 'danger') {
      return $r('app.color.md_danger');
    }
    if (kind === 'accent') {
      return $r('sys.color.ohos_id_color_emphasize');
    }
    return $r('sys.color.ohos_id_color_text_secondary');
  }

  private taskHasMeta(item: MdListItem): boolean {
    return item.priority.length > 0 || item.dueDate.length > 0 ||
      item.scheduledDate.length > 0 || item.startDate.length > 0 ||
      item.doneDate.length > 0 || item.createdDate.length > 0 ||
      item.recurrence.length > 0;
  }

  private taskChips(item: MdListItem): TaskChip[] {
    const chips: TaskChip[] = [];
    if (item.priority.length > 0) {
      const chip: TaskChip = new TaskChip();
      chip.label = item.priority;
      chip.kind = item.priority === '⏫' ? 'danger' : 'accent';
      chips.push(chip);
    }
    if (item.dueDate.length > 0) {
      const chip: TaskChip = new TaskChip();
      chip.label = `📅 ${item.dueDate}`;
      chip.kind = 'danger';
      chips.push(chip);
    }
    if (item.scheduledDate.length > 0) {
      const chip: TaskChip = new TaskChip();
      chip.label = `⏳ ${item.scheduledDate}`;
      chips.push(chip);
    }
    if (item.startDate.length > 0) {
      const chip: TaskChip = new TaskChip();
      chip.label = `🛫 ${item.startDate}`;
      chips.push(chip);
    }
    if (item.doneDate.length > 0) {
      const chip: TaskChip = new TaskChip();
      chip.label = `✅ ${item.doneDate}`;
      chip.kind = 'accent';
      chips.push(chip);
    }
    if (item.createdDate.length > 0) {
      const chip: TaskChip = new TaskChip();
      chip.label = `➕ ${item.createdDate}`;
      chips.push(chip);
    }
    if (item.recurrence.length > 0) {
      const chip: TaskChip = new TaskChip();
      chip.label = `🔁 ${item.recurrence}`;
      chips.push(chip);
    }
    return chips;
  }

  @Builder
  codeView() {
    Column() {
      Row() {
        Text(this.codeLangLabel())
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .layoutWeight(1)
        SymbolGlyph(this.copied ? $r('sys.symbol.checkmark') : $r('sys.symbol.doc_text_on_doc_text'))
          .fontSize(15)
          .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
          .padding(6)
          .borderRadius(12)
          .onClick(() => {
            this.copyCode();
          })
      }
      .width('100%')
      .margin({ bottom: 6 })

      Text(this.block.rawContent)
        .fontSize(this.fontSize - 2)
        .fontFamily('monospace')
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
    .margin({ top: 6, bottom: 6 })
  }

  /** 常见语言别名（fence 标记 �?显示名）�?*/
  private static readonly LANG_ALIASES: Record<string, string> = {
    'js': 'JavaScript', 'javascript': 'JavaScript', 'ts': 'TypeScript', 'typescript': 'TypeScript',
    'jsx': 'JSX', 'tsx': 'TSX', 'py': 'Python', 'python': 'Python', 'java': 'Java',
    'kotlin': 'Kotlin', 'swift': 'Swift', 'c': 'C', 'cpp': 'C++', 'c++': 'C++', 'csharp': 'C#',
    'go': 'Go', 'rust': 'Rust', 'php': 'PHP', 'ruby': 'Ruby', 'html': 'HTML', 'css': 'CSS',
    'json': 'JSON', 'yaml': 'YAML', 'yml': 'YAML', 'xml': 'XML', 'md': 'Markdown',
    'markdown': 'Markdown', 'sh': 'Shell', 'bash': 'Shell', 'shell': 'Shell', 'zsh': 'Shell',
    'sql': 'SQL', 'dart': 'Dart', 'arkts': 'ArkTS', 'ets': 'ArkTS'
  };

  /** 代码块语言标签：别名映射，未知语言原样显示�?*/
  private codeLangLabel(): string {
    const lang: string = this.block.lang.trim();
    if (lang.length === 0) {
      return '';
    }
    const mapped: string | undefined = MdBlockView.LANG_ALIASES[lang.toLowerCase()];
    return mapped !== undefined ? mapped : lang;
  }

  /** 复制代码块内容到系统剪贴板，图标短暂变为对勾�?*/
  private copyCode(): void {
    if (this.block.rawContent.length === 0) {
      return;
    }
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.block.rawContent);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      this.copied = true;
      setTimeout((): void => {
        this.copied = false;
      }, 1500);
    }).catch((error: BusinessError): void => {
    });
  }

  /** Dataview TASK 查询结果：按来源笔记分组渲染跨笔记任务。 */
  @Builder
  dataViewTaskView() {
    Column() {
      if (this.dataLoaded && this.dataTasks.length === 0) {
        Text($r('app.string.md_dataview_empty'))
          .fontSize(this.fontSize - 2)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      ForEach(this.dataTasks, (task: DataViewTask, index: number) => {
        if (this.needGroupHeader(index)) {
          Text(task.fileName)
            .fontSize(this.fontSize - 1)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .margin({ top: index === 0 ? 0 : 10, bottom: 4 })
        }
        Row() {
          SymbolGlyph(task.item.checked ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.circle'))
            .fontSize(20)
            .fontColor([task.item.checked ? $r('sys.color.ohos_id_color_emphasize')
              : $r('sys.color.ohos_id_color_text_secondary')])
            .width(26)
            .margin({ top: 2 })
            .onClick(() => {
              this.toggleDataViewTask(task);
            })
          Column() {
            MdInlineText({
              segments: MdInlineFlattener.flatten(task.item.inlines),
              fontSize: this.fontSize,
              onOpenLink: (target: string, kind: string): void => {
                this.onOpenLink(target, kind);
              },
              onOpenTag: (tag: string): void => {
                this.onOpenTag(tag);
              }
            })
            if (this.taskHasMeta(task.item)) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.taskChips(task.item), (chip: TaskChip) => {
                  this.taskChipView(chip)
                }, (chip: TaskChip, chipIndex: number): string =>
                  `dvchip_${index}_${chipIndex}_${task.item.checked}`)
              }
              .margin({ top: 2 })
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }, (task: DataViewTask, index: number): string => `dv_${index}_${task.item.checked}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
    .margin({ top: 6, bottom: 6 })
  }

  /** Dataview TABLE 查询结果：直接渲染解析后的表格数据。 */
  @Builder
  dataViewTableView() {
    Column() {
      if (this.dataViewTableLoaded && this.dataViewTableRows.length === 0) {
        Text($r('app.string.md_dataview_empty'))
          .fontSize(this.fontSize - 2)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      if (this.dataViewQuery !== null && this.dataViewQuery.tableColumns.length > 0) {
        Row() {
          ForEach(this.dataViewQuery.tableColumns, (col: string, colIndex: number) => {
            MdInlineText({
              segments: MdInlineFlattener.flatten(this.inlineParser.parse(col)),
              fontSize: this.fontSize,
              textAlignment: TextAlign.Center,
              forceBold: true,
              onOpenLink: (target: string, kind: string): void => {
                this.onOpenLink(target, kind);
              },
              onOpenTag: (tag: string): void => {
                this.onOpenTag(tag);
              }
            })
              .layoutWeight(1)
          }, (col: string, colIndex: number): string => `dvthead_${colIndex}`)
        }
        .width('100%')
        .padding({ bottom: 4 })
        Divider()
          .color($r('sys.color.ohos_id_color_text_secondary'))
      }
      ForEach(this.dataViewTableRows, (row: string[], rowIndex: number) => {
        Row() {
          ForEach(row, (cell: string, cellIndex: number) => {
            MdInlineText({
              segments: MdInlineFlattener.flatten(this.inlineParser.parse(cell)),
              fontSize: this.fontSize,
              textAlignment: TextAlign.Start,
              onOpenLink: (target: string, kind: string): void => {
                this.onOpenLink(target, kind);
              },
              onOpenTag: (tag: string): void => {
                this.onOpenTag(tag);
              }
            })
              .layoutWeight(1)
          }, (cell: string, cellIndex: number): string => `dvtbody_${rowIndex}_${cellIndex}`)
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })
      }, (row: string[], rowIndex: number): string => `dvtbody_${rowIndex}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
    .margin({ top: 6, bottom: 6 })
  }

  /** Dataview LIST 查询结果：直接渲染条目列表。 */
  @Builder
  dataViewListView() {
    Column() {
      if (this.dataViewListLoaded && this.dataViewListItems.length === 0) {
        Text($r('app.string.md_dataview_empty'))
          .fontSize(this.fontSize - 2)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      ForEach(this.dataViewListItems, (item: string, index: number) => {
        MdInlineText({
          segments: MdInlineFlattener.flatten(this.inlineParser.parse(item)),
          fontSize: this.fontSize,
          onOpenLink: (target: string, kind: string): void => {
            this.onOpenLink(target, kind);
          },
          onOpenTag: (tag: string): void => {
            this.onOpenTag(tag);
          }
        })
        if (index < this.dataViewListItems.length - 1) {
          Divider()
            .color($r('sys.color.ohos_id_color_text_secondary'))
            .margin({ top: 2, bottom: 2 })
        }
      }, (item: string, index: number): string => `dvlist_${index}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
    .margin({ top: 6, bottom: 6 })
  }

  /** 分组头：首项或来源笔记切换时显示。 */
  private needGroupHeader(index: number): boolean {
    if (index === 0) {
      return true;
    }
    const prev: DataViewTask = this.dataTasks[index - 1];
    return this.dataTasks[index].fileName !== prev.fileName;
  }

  /** 本地翻转勾选状态（即时反馈）并通知宿主回写。 */
  private toggleDataViewTask(task: DataViewTask): void {
    const next: boolean = !task.item.checked;
    task.item.checked = next;
    this.dataTasks = this.dataTasks.slice();
    this.onToggleDataViewTask(task, next);
  }

  @Builder
  quoteView() {
    Row() {
      Column() {
        MdInlineText({
          segments: MdInlineFlattener.flatten(this.block.inlines),
          fontSize: this.fontSize,
          onOpenLink: (target: string, kind: string): void => {
            this.onOpenLink(target, kind);
          },
          onOpenTag: (tag: string): void => {
            this.onOpenTag(tag);
          }
        })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 12, top: 4, bottom: 4 })
    .borderWidth({ left: 3 })
    .borderColor($r('sys.color.ohos_id_color_emphasize'))
    .margin({ top: 4, bottom: 4 })
  }

  @Builder
  calloutView() {
    Row() {
      Text(this.calloutIcon())
        .fontSize(this.fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_emphasize'))
        .width(24)
      Column() {
        Text(this.block.calloutType)
          .fontSize(this.fontSize)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        MdInlineText({
          segments: MdInlineFlattener.flatten(this.block.inlines),
          fontSize: this.fontSize,
          onOpenLink: (target: string, kind: string): void => {
            this.onOpenLink(target, kind);
          },
          onOpenTag: (tag: string): void => {
            this.onOpenTag(tag);
          }
        })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('sys.color.ohos_id_color_component_activated'))
    .margin({ top: 6, bottom: 6 })
  }

  @Builder
  tableView() {
    Column() {
      Row() {
        ForEach(this.block.headers, (header: string, index: number) => {
          MdInlineText({
            segments: MdInlineFlattener.flatten(this.inlineParser.parse(header)),
            fontSize: this.fontSize,
            textAlignment: this.cellAlign(index),
            forceBold: true,
            onOpenLink: (target: string, kind: string): void => {
              this.onOpenLink(target, kind);
            },
            onOpenTag: (tag: string): void => {
              this.onOpenTag(tag);
            }
          })
            .layoutWeight(1)
        }, (header: string, index: number): string => `head_${index}`)
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })
      Divider()
        .color($r('sys.color.ohos_id_color_text_secondary'))
      ForEach(this.block.rows, (row: string[], rowIndex: number) => {
        Row() {
          ForEach(row, (cell: string, cellIndex: number) => {
            MdInlineText({
              segments: MdInlineFlattener.flatten(this.inlineParser.parse(cell)),
              fontSize: this.fontSize,
              textAlignment: this.cellAlign(cellIndex),
              onOpenLink: (target: string, kind: string): void => {
                this.onOpenLink(target, kind);
              },
              onOpenTag: (tag: string): void => {
                this.onOpenTag(tag);
              }
            })
              .layoutWeight(1)
          }, (cell: string, cellIndex: number): string => `cell_${rowIndex}_${cellIndex}`)
        }
        .width('100%')
        .padding({ top: 6, bottom: 6 })
      }, (row: string[], rowIndex: number): string => `row_${rowIndex}`)
    }
    .width('100%')
    .margin({ top: 6, bottom: 6 })
  }

  /** 表格列对齐：依据分隔�?`:---:` 解析结果映射�?TextAlign�?*/
  private cellAlign(index: number): TextAlign {
    const align: string = index < this.block.aligns.length ? this.block.aligns[index] : 'left';
    if (align === 'center') {
      return TextAlign.Center;
    }
    if (align === 'right') {
      return TextAlign.End;
    }
    return TextAlign.Start;
  }

  @Builder
  rawView() {
    Column() {
      Text(this.block.rawContent)
        .fontSize(this.fontSize - 2)
        .fontFamily('monospace')
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding(10)
    .borderRadius(8)
    .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
    .margin({ top: 6, bottom: 6 })
  }

  private htmlHeight(): number {
    const length: number = this.block.rawContent.length;
    const lines: number = Math.max(1, Math.floor(length / 40));
    return Math.min(420, 80 + lines * 20);
  }

  private headingFontSize(): number {    if (this.block.level <= 1) {
      return this.fontSize + 8;
    }
    if (this.block.level === 2) {
      return this.fontSize + 5;
    }
    if (this.block.level === 3) {
      return this.fontSize + 2;
    }
    return this.fontSize;
  }

  private bulletText(item: MdListItem): string {
    if (this.block.ordered) {
      return `${item.ordinal}.`;
    }
    return '•';
  }

  private calloutIcon(): string {
    const type: string = this.block.calloutType;
    if (type === 'TIP') {
      return '✓';
    }
    if (type === 'NOTE') {
      return 'i';
    }
    return '!';
  }
}
