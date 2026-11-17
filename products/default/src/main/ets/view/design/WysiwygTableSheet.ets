import { WysiwygTableAlign, WysiwygTableCodec, WysiwygTableData } from '@ohos/markdown';
import { DesignTokens } from '../../viewmodel/DesignTokens';

@ObservedV2
class EditableTableColumn {
  readonly id: number;
  @Trace title: string = '';
  @Trace align: WysiwygTableAlign = 'left';

  constructor(id: number, title: string, align: WysiwygTableAlign) {
    this.id = id;
    this.title = title;
    this.align = align;
  }
}

@ObservedV2
class EditableTableCell {
  readonly id: number;
  @Trace value: string = '';

  constructor(id: number, value: string) {
    this.id = id;
    this.value = value;
  }
}

@ObservedV2
class EditableTableRow {
  readonly id: number;
  @Trace cells: EditableTableCell[] = [];

  constructor(id: number, cells: EditableTableCell[]) {
    this.id = id;
    this.cells = cells;
  }
}

/**
 * 原生 Markdown 可视化表格编辑弹窗：
 * - 点击 WYSIWYG 中的可视化表格后弹出（也可由顶部工具栏插入新表格触发）
 * - 支持直接编辑表头/单元格、增删行列、逐列切换对齐（左/中/右）
 * - 支持一键切换「源码微调」双工编辑与删除整张表格
 */
@ComponentV2
export struct WysiwygTableSheet {
  @Param tableId: number = 0;
  @Param rawMd: string = '';
  @Event onCancel: () => void = (): void => {};
  @Event onConfirm: (tableId: number, nextRawMd: string) => void = (_id: number, _md: string): void => {};
  @Event onDelete: (tableId: number) => void = (_id: number): void => {};

  @Local private columns: EditableTableColumn[] = [];
  @Local private rows: EditableTableRow[] = [];
  @Local private sourceMode: boolean = false;
  @Local private sourceDraft: string = '';
  @Local private gridContainerWidthVp: number = 0;

  private nextUid: number = 1;
  private readonly hScroller: Scroller = new Scroller();
  private readonly vScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadFromRawMarkdown(this.rawMd);
  }

  @Monitor('tableId', 'rawMd')
  onInputChanged(): void {
    this.loadFromRawMarkdown(this.rawMd);
  }

  private loadFromRawMarkdown(md: string): void {
    const parsed: WysiwygTableData = md.trim().length > 0
      ? WysiwygTableCodec.parseFromMarkdown(md)
      : WysiwygTableCodec.defaultTable();
    const cols: EditableTableColumn[] = [];
    for (let c: number = 0; c < parsed.headers.length; c++) {
      const align: WysiwygTableAlign = c < parsed.aligns.length ? parsed.aligns[c] : 'left';
      cols.push(new EditableTableColumn(this.nextUid++, parsed.headers[c], align));
    }
    const rowModels: EditableTableRow[] = [];
    for (const r of parsed.rows) {
      const cellModels: EditableTableCell[] = [];
      for (let c: number = 0; c < cols.length; c++) {
        cellModels.push(new EditableTableCell(this.nextUid++, c < r.length ? r[c] : ''));
      }
      rowModels.push(new EditableTableRow(this.nextUid++, cellModels));
    }
    this.columns = cols;
    this.rows = rowModels;
    this.sourceDraft = md.trim().length > 0 ? md.trim() : WysiwygTableCodec.toMarkdown(parsed);
    this.sourceMode = false;
  }

  private toTableData(): WysiwygTableData {
    const data: WysiwygTableData = new WysiwygTableData();
    data.headers = [];
    data.aligns = [];
    for (const col of this.columns) {
      data.headers.push(col.title);
      data.aligns.push(col.align);
    }
    data.rows = [];
    for (const row of this.rows) {
      const vals: string[] = [];
      for (let c: number = 0; c < this.columns.length; c++) {
        vals.push(c < row.cells.length ? row.cells[c].value : '');
      }
      data.rows.push(vals);
    }
    return data;
  }

  private toggleSourceMode(): void {
    if (this.sourceMode) {
      this.loadFromRawMarkdown(this.sourceDraft);
      this.sourceMode = false;
    } else {
      this.sourceDraft = WysiwygTableCodec.toMarkdown(this.toTableData());
      this.sourceMode = true;
    }
  }

  private cycleColumnAlign(colIdx: number): void {
    if (colIdx < 0 || colIdx >= this.columns.length) {
      return;
    }
    const cur: WysiwygTableAlign = this.columns[colIdx].align;
    if (cur === 'left') {
      this.columns[colIdx].align = 'center';
    } else if (cur === 'center') {
      this.columns[colIdx].align = 'right';
    } else {
      this.columns[colIdx].align = 'left';
    }
  }

  private addRow(): void {
    if (this.sourceMode) {
      this.loadFromRawMarkdown(this.sourceDraft);
    }
    const cells: EditableTableCell[] = [];
    for (let c: number = 0; c < this.columns.length; c++) {
      cells.push(new EditableTableCell(this.nextUid++, ''));
    }
    this.rows.push(new EditableTableRow(this.nextUid++, cells));
  }

  private removeRow(rowIdx: number): void {
    if (rowIdx < 0 || rowIdx >= this.rows.length) {
      return;
    }
    this.rows.splice(rowIdx, 1);
  }

  private addColumn(): void {
    if (this.sourceMode) {
      this.loadFromRawMarkdown(this.sourceDraft);
    }
    const nextIdx: number = this.columns.length + 1;
    this.columns.push(new EditableTableColumn(this.nextUid++, `列${nextIdx}`, 'left'));
    for (const row of this.rows) {
      row.cells.push(new EditableTableCell(this.nextUid++, ''));
    }
  }

  private removeColumn(colIdx: number): void {
    if (this.columns.length <= 1 || colIdx < 0 || colIdx >= this.columns.length) {
      return;
    }
    this.columns.splice(colIdx, 1);
    for (const row of this.rows) {
      if (colIdx < row.cells.length) {
        row.cells.splice(colIdx, 1);
      }
    }
  }

  private alignLabel(align: WysiwygTableAlign): Resource {
    if (align === 'center') {
      return $r('app.string.table_editor_align_center');
    }
    if (align === 'right') {
      return $r('app.string.table_editor_align_right');
    }
    return $r('app.string.table_editor_align_left');
  }

  private alignIconText(align: WysiwygTableAlign): string {
    if (align === 'center') {
      return '⬌ 中';
    }
    if (align === 'right') {
      return '➡ 右';
    }
    return '⬅ 左';
  }

  private colTextAlign(colIdx: number): TextAlign {
    if (colIdx < 0 || colIdx >= this.columns.length) {
      return TextAlign.Start;
    }
    const align: WysiwygTableAlign = this.columns[colIdx].align;
    if (align === 'center') {
      return TextAlign.Center;
    }
    if (align === 'right') {
      return TextAlign.End;
    }
    return TextAlign.Start;
  }

  private commitChanges(): void {
    if (this.sourceMode) {
      const normalized: WysiwygTableData = WysiwygTableCodec.parseFromMarkdown(this.sourceDraft);
      this.onConfirm(this.tableId, WysiwygTableCodec.toMarkdown(normalized));
      return;
    }
    const nextMd: string = WysiwygTableCodec.toMarkdown(this.toTableData());
    this.onConfirm(this.tableId, nextMd);
  }

  private cellWidthVp(): number {
    const colCount: number = Math.max(1, this.columns.length);
    if (this.gridContainerWidthVp > 120) {
      const avail: number = Math.floor((this.gridContainerWidthVp - 36) / colCount);
      return Math.max(112, avail);
    }
    return colCount <= 2 ? 128 : 114;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.design_dim'))
        .backgroundBlurStyle(BlurStyle.Thin)
        .onClick(() => {
          this.onCancel();
        })

      this.cardContent()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private cardContent() {
    Column({ space: 12 }) {
      // 标题栏 + 源码切换胶囊
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text($r('app.string.table_editor_title'))
            .fontSize(DesignTokens.FONT_TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.design_text_primary'))
          Text(`${this.columns.length} 列 × ${this.rows.length} 数据行`)
            .fontSize(DesignTokens.FONT_SM)
            .fontColor($r('app.color.design_text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button({ type: ButtonType.Capsule, stateEffect: true }) {
          Text(this.sourceMode ? $r('app.string.table_editor_grid_mode') : $r('app.string.table_editor_source_mode'))
            .fontSize(DesignTokens.FONT_SM)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.sourceMode ? $r('app.color.design_on_accent') : $r('app.color.design_accent'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        }
        .backgroundColor(this.sourceMode ? $r('app.color.design_accent') : $r('app.color.design_accent_weak'))
        .height(34)
        .onClick(() => {
          this.toggleSourceMode();
        })
      }
      .width('100%')

      // 结构操作条（+ 行 / + 列 / 删除表格）
      Row({ space: 8 }) {
        if (!this.sourceMode) {
          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            Text($r('app.string.table_editor_add_row'))
              .fontSize(DesignTokens.FONT_SM)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.design_text_primary'))
              .padding({ left: 12, right: 12 })
          }
          .height(34)
          .backgroundColor($r('app.color.design_elevated'))
          .onClick(() => {
            this.addRow();
          })

          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            Text($r('app.string.table_editor_add_col'))
              .fontSize(DesignTokens.FONT_SM)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.design_text_primary'))
              .padding({ left: 12, right: 12 })
          }
          .height(34)
          .backgroundColor($r('app.color.design_elevated'))
          .onClick(() => {
            this.addColumn();
          })
        }

        Blank()

        Button({ type: ButtonType.Capsule, stateEffect: true }) {
          Text($r('app.string.table_editor_delete'))
            .fontSize(DesignTokens.FONT_SM)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_danger'))
            .padding({ left: 12, right: 12 })
        }
        .height(34)
        .backgroundColor($r('app.color.design_tint_rose_bg'))
        .onClick(() => {
          this.onDelete(this.tableId);
        })
      }
      .width('100%')

      if (this.sourceMode) {
        this.sourceEditorBody()
      } else {
        this.gridEditorBody()
      }

      // 底部取消 / 完成按钮
      Row({ space: 10 }) {
        Button($r('app.string.table_editor_cancel'))
          .layoutWeight(1)
          .height(42)
          .fontSize(DesignTokens.FONT_MD)
          .fontColor($r('app.color.design_text_primary'))
          .backgroundColor($r('app.color.design_elevated'))
          .borderRadius(21)
          .onClick(() => {
            this.onCancel();
          })

        Button($r('app.string.table_editor_done'))
          .layoutWeight(1)
          .height(42)
          .fontSize(DesignTokens.FONT_MD)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_on_accent'))
          .backgroundColor($r('app.color.design_accent'))
          .borderRadius(21)
          .onClick(() => {
            this.commitChanges();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('92%')
    .constraintSize({ maxWidth: 560, maxHeight: '84%' })
    .borderRadius(DesignTokens.RADIUS_SHEET)
    .backgroundColor($r('app.color.design_surface_solid'))
    .shadow({ radius: 32, color: $r('app.color.design_shadow'), offsetY: 10 })
    .onClick(() => {})
  }

  @Builder
  private sourceEditorBody() {
    Column({ space: 8 }) {
      TextArea({ text: this.sourceDraft })
        .fontSize(DesignTokens.FONT_MD)
        .fontFamily('monospace')
        .fontColor($r('app.color.design_text_primary'))
        .backgroundColor($r('app.color.design_elevated'))
        .borderRadius(14)
        .padding(12)
        .width('100%')
        .height(220)
        .onChange((val: string) => {
          this.sourceDraft = val;
        })
      Text($r('app.string.table_editor_source_hint'))
        .fontSize(DesignTokens.FONT_XS)
        .fontColor($r('app.color.design_text_secondary'))
        .width('100%')
    }
    .width('100%')
  }

  @Builder
  private gridEditorBody() {
    Column({ space: 6 }) {
      Scroll(this.hScroller) {
        Scroll(this.vScroller) {
          Column({ space: 0 }) {
            // 表头行 + 列对齐切换 + 删除列
            Row({ space: 0 }) {
              Text('#')
                .width(34)
                .fontSize(DesignTokens.FONT_XS)
                .fontColor($r('app.color.design_text_secondary'))
                .textAlign(TextAlign.Center)

              ForEach(this.columns, (col: EditableTableColumn) => {
                Column({ space: 4 }) {
                  Row({ space: 4 }) {
                    Text(this.alignIconText(col.align))
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.design_accent'))
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(6)
                      .backgroundColor($r('app.color.design_surface_solid'))
                      .accessibilityText(this.alignLabel(col.align))
                      .onClick(() => {
                        this.cycleColumnAlign(this.columns.indexOf(col));
                      })

                    Blank()

                    if (this.columns.length > 1) {
                      Text('×')
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.design_text_secondary'))
                        .width(22)
                        .height(22)
                        .textAlign(TextAlign.Center)
                        .borderRadius(11)
                        .backgroundColor($r('app.color.design_surface_solid'))
                        .onClick(() => {
                          this.removeColumn(this.columns.indexOf(col));
                        })
                    }
                  }
                  .width('100%')

                  TextInput({ text: col.title, placeholder: $r('app.string.table_editor_col_placeholder') })
                    .fontSize(DesignTokens.FONT_MD)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.design_text_primary'))
                    .textAlign(this.colTextAlign(this.columns.indexOf(col)))
                    .backgroundColor($r('app.color.design_surface_solid'))
                    .borderRadius(8)
                    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                    .width('100%')
                    .onChange((val: string) => {
                      col.title = val;
                    })
                }
                .width(this.cellWidthVp())
                .padding({ left: 5, right: 5, top: 6, bottom: 8 })
                .border({
                  width: { left: 0.5 },
                  color: $r('app.color.design_divider')
                })
              }, (col: EditableTableColumn): string => `col_${col.id}`)
            }
            .backgroundColor($r('app.color.design_accent_weak'))
            .border({
              width: { bottom: 1 },
              color: $r('app.color.design_divider')
            })

            // 数据行
            ForEach(this.rows, (row: EditableTableRow, rIdx: number) => {
              Row({ space: 0 }) {
                Stack({ alignContent: Alignment.Center }) {
                  Text('×')
                    .fontSize(14)
                    .fontColor($r('app.color.design_text_secondary'))
                    .textAlign(TextAlign.Center)
                }
                .width(34)
                .height(36)
                .onClick(() => {
                  this.removeRow(this.rows.indexOf(row));
                })

                ForEach(row.cells, (cell: EditableTableCell) => {
                  Column() {
                    TextInput({ text: cell.value, placeholder: $r('app.string.table_editor_cell_placeholder') })
                      .fontSize(DesignTokens.FONT_MD)
                      .fontColor($r('app.color.design_text_primary'))
                      .textAlign(this.colTextAlign(row.cells.indexOf(cell)))
                      .backgroundColor(Color.Transparent)
                      .borderRadius(6)
                      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                      .width('100%')
                      .onChange((val: string) => {
                        cell.value = val;
                      })
                  }
                  .width(this.cellWidthVp())
                  .padding({ left: 4, right: 4, top: 3, bottom: 3 })
                  .border({
                    width: { left: 0.5 },
                    color: $r('app.color.design_divider')
                  })
                }, (cell: EditableTableCell): string => `cell_${cell.id}`)
              }
              .backgroundColor(rIdx % 2 === 1 ? $r('app.color.design_elevated') : $r('app.color.design_surface_solid'))
              .border({
                width: { bottom: 0.5 },
                color: $r('app.color.design_divider')
              })
            }, (row: EditableTableRow): string => `row_${row.id}`)
          }
          .alignItems(HorizontalAlign.Start)
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .constraintSize({ maxHeight: 300 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .borderRadius(14)
      .border({ width: 1, color: $r('app.color.design_divider') })
      .clip(true)
      .width('100%')
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        const w: number = Number(newArea.width);
        if (w > 100 && Math.abs(w - this.gridContainerWidthVp) >= 2) {
          this.gridContainerWidthVp = w;
        }
      })

      Text($r('app.string.table_editor_source_hint'))
        .fontSize(DesignTokens.FONT_XS)
        .fontColor($r('app.color.design_text_secondary'))
        .width('100%')
    }
    .width('100%')
  }
}
