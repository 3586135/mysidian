import { RecentNoteItem, VaultViewModel } from '../../viewmodel/VaultViewModel';

/**
 * Material 3 最近访问浮层：顶部居中模态，按访问时间倒序列出笔记。
 */
@ComponentV2
export struct RecentNotesPanel {
  @Param vm: VaultViewModel = new VaultViewModel();
  @Event onOpenNote: (path: string) => void = (path: string): void => {};
  @Event onClose: () => void = (): void => {};

  aboutToAppear(): void {
    this.vm.loadRecentNotes();
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
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(18)
            .fontColor([$r('app.color.design_accent')])
          Text($r('app.string.recent_notes_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_text_primary'))
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(14)
            .fontColor([$r('app.color.design_text_secondary')])
            .padding(8)
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 10, top: 14, bottom: 10 })

        Divider()
          .color($r('app.color.design_divider'))

        if (this.vm.recentNotes.length === 0) {
          Column() {
            Text($r('app.string.recent_notes_empty'))
              .fontSize(14)
              .fontColor($r('app.color.design_text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.vm.recentNotes, (item: RecentNoteItem) => {
              ListItem() {
                Column() {
                  Text(item.title)
                    .fontSize(15)
                    .fontColor($r('app.color.design_text_primary'))
                    .width('100%')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row() {
                    Text(item.path)
                      .fontSize(12)
                      .fontColor($r('app.color.design_text_secondary'))
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.formatTime(item.openedAt))
                      .fontSize(12)
                      .fontColor($r('app.color.design_text_secondary'))
                      .padding({ left: 8 })
                  }
                  .width('100%')
                  .margin({ top: 2 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                .borderRadius(14)
                .onClick(() => {
                  this.onOpenNote(item.path);
                })
              }
            }, (item: RecentNoteItem): string => `recent_${item.path}`)
          }
          .layoutWeight(1)
          .width('100%')
          .padding(6)
        }
      }
      .width('90%')
      .height('58%')
      .borderRadius(24)
      .backgroundColor($r('app.color.design_surface_solid'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .shadow({ radius: 32, color: $r('app.color.design_shadow'), offsetY: 10 })
      .alignItems(HorizontalAlign.Start)
      .transition(TransitionEffect.scale({ x: 0.94, y: 0.94 })
        .combine(TransitionEffect.opacity(0))
        .animation({ duration: 220, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Top)
    .padding({ top: '10%' })
  }

  /** 访问时间文案：今天只显示时间，其余显示月-日 时间。 */
  private formatTime(stamp: number): string {
    const date: Date = new Date(stamp);
    const now: Date = new Date();
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    const time: string = `${pad(date.getHours())}:${pad(date.getMinutes())}`;
    if (date.getFullYear() === now.getFullYear() && date.getMonth() === now.getMonth() &&
      date.getDate() === now.getDate()) {
      return time;
    }
    return `${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${time}`;
  }
}
