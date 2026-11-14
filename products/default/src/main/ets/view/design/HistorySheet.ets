import { DiffLine, HistorySnapshot } from '@ohos/vault';
import { VaultViewModel } from '../../viewmodel/VaultViewModel';

/** 快照时间格式化。 */
function formatHistoryTime(timestamp: number): string {
  if (timestamp <= 0) {
    return '';
  }
  const value: Date = new Date(timestamp);
  const pad = (v: number): string => v < 10 ? `0${v}` : `${v}`;
  return `${value.getFullYear()}-${pad(value.getMonth() + 1)}-${pad(value.getDate())} ` +
    `${pad(value.getHours())}:${pad(value.getMinutes())}:${pad(value.getSeconds())}`;
}

/**
 * Material 3 历史版本浮层：快照列表 + 选中差异（DiffLine 渲染）+ 回滚。
 */
@ComponentV2
export struct HistorySheet {
  @Param vm: VaultViewModel = new VaultViewModel();
  @Event onClose: () => void = (): void => {};
  @Event onNoteMutated: () => void = (): void => {};

  /** 快照列表。 */
  @Local historyList: HistorySnapshot[] = [];
  /** 当前选中快照名（展开差异）。 */
  @Local historySelected: string = '';
  /** 选中快照与当前内容的差异行。 */
  @Local historyDiff: DiffLine[] = [];

  aboutToAppear(): void {
    this.vm.listHistory().then((list: HistorySnapshot[]): void => {
      this.historyList = list;
    });
  }

  build() {
    Stack() {
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.design_dim'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.Friction }))
      .onClick(() => {
        this.onClose();
      })

      Column() {
        Text($r('app.string.history_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_text_primary'))
          .width('100%')
          .margin({ bottom: 8 })

        if (this.historyList.length === 0) {
          Text($r('app.string.history_empty'))
            .fontSize(13)
            .fontColor($r('app.color.design_text_secondary'))
        } else {
          Scroll() {
            Column() {
              ForEach(this.historyList, (item: HistorySnapshot, index: number) => {
                this.historyRow(item, index)
              }, (item: HistorySnapshot, index: number): string => `hist_${item.name}`)
            }
            .width('100%')
          }
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .constraintSize({ maxHeight: 320 })
        }

        Row() {
          Button($r('app.string.dialog_cancel'))
            .type(ButtonType.Capsule)
            .height(40)
            .fontSize(16)
            .backgroundColor($r('app.color.design_elevated'))
            .fontColor($r('app.color.design_text_primary'))
            .layoutWeight(1)
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('88%')
      .constraintSize({ maxWidth: 460 })
      .padding(20)
      .borderRadius(28)
      .backgroundColor($r('app.color.design_surface_solid'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .shadow({ radius: 32, color: $r('app.color.design_shadow'), offsetY: 10 })
      .transition(TransitionEffect.scale({ x: 0.92, y: 0.92 })
        .combine(TransitionEffect.opacity(0))
        .animation({ duration: 220, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
  }

  /** 历史版本条目（点击查看差异，可回滚）。 */
  @Builder
  historyRow(item: HistorySnapshot, index: number) {
    Column() {
      Row() {
        Text(formatHistoryTime(item.timestamp))
          .fontSize(13)
          .fontColor(this.historySelected === item.name ? $r('app.color.design_accent')
            : $r('app.color.design_text_primary'))
          .layoutWeight(1)
        Text($r('app.string.history_rollback'))
          .fontSize(12)
          .fontColor($r('app.color.design_accent'))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(12)
          .backgroundColor($r('app.color.design_accent_weak'))
          .onClick(() => {
            this.rollbackSnapshot(item.name);
          })
      }
      .width('100%')

      if (this.historySelected === item.name) {
        Text($r('app.string.history_diff'))
          .fontSize(11)
          .fontColor($r('app.color.design_text_secondary'))
          .width('100%')
          .margin({ top: 4 })
        Column() {
          ForEach(this.historyDiff, (line: DiffLine, lineIndex: number) => {
            Text(`${line.marker}${line.text}`)
              .fontSize(11)
              .fontFamily('monospace')
              .fontColor(this.diffColor(line))
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }, (line: DiffLine, lineIndex: number): string => `d_${lineIndex}_${line.marker}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 2 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(10)
    .borderRadius(12)
    .backgroundColor($r('app.color.design_elevated'))
    .margin({ top: 6 })
    .onClick(() => {
      this.selectSnapshot(item.name);
    })
  }

  /** 选中快照并计算差异。 */
  private selectSnapshot(name: string): void {
    this.historySelected = name;
    this.vm.diffHistory(name).then((diff: DiffLine[]): void => {
      this.historyDiff = diff;
    });
  }

  /** 回滚到指定快照。 */
  private rollbackSnapshot(name: string): void {
    this.vm.rollbackHistory(name).then((ok: boolean): void => {
      if (!ok) {
        return;
      }
      this.onClose();
      this.toast($r('app.string.msg_history_rolled_back'));
      this.onNoteMutated();
    });
  }

  /** Diff 行颜色：+ 强调色 / - 危险色 / 其余次要文本。 */
  private diffColor(line: DiffLine): ResourceColor {
    if (line.marker === '+') {
      return $r('app.color.design_accent');
    }
    if (line.marker === '-') {
      return $r('app.color.design_danger');
    }
    return $r('app.color.design_text_secondary');
  }

  /** 轻提示（使用 UIContext 的 PromptAction，避免全局 promptAction 的弃用告警）。 */
  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }
}
