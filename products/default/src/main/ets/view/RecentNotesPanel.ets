import { RecentNoteItem } from '../viewmodel/VaultViewModel';

/**
 * 最近访问笔记选择器：鸿蒙风格顶部居中模态，模糊蒙层 + 圆角卡片。
 */
@ComponentV2
export struct RecentNotesPanel {
  @Param items: RecentNoteItem[] = [];
  @Event onOpenNote: (path: string) => void = (path: string): void => {};
  @Event onClose: () => void = (): void => {};

  build() {
    Stack() {
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.hm_mask'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .onClick(() => {
        this.onClose();
      })

      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.clock')
          )
            .fontSize(18)
            .fontColor([$r('app.color.hm_accent')])
          Text($r('app.string.recent_notes_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.hm_text_primary'))
            .layoutWeight(1)
            .padding({ left: 8 })
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.hm_text_secondary')])
            .padding(8)
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12 })
        .backgroundColor($r('app.color.hm_card_bg'))

        if (this.items.length === 0) {
          Column() {
            Text($r('app.string.recent_notes_empty'))
              .fontSize(14)
              .fontColor($r('app.color.hm_text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.items, (item: RecentNoteItem, index: number) => {
              ListItem() {
                Column() {
                  Text(item.title)
                    .fontSize(15)
                    .fontColor($r('app.color.hm_text_primary'))
                    .width('100%')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row() {
                    Text(item.path)
                      .fontSize(12)
                      .fontColor($r('app.color.hm_text_secondary'))
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.formatTime(item.openedAt))
                      .fontSize(12)
                      .fontColor($r('app.color.hm_text_secondary'))
                      .padding({ left: 8 })
                  }
                  .width('100%')
                  .margin({ top: 2 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                .borderRadius(8)
                .onClick(() => {
                  this.onOpenNote(item.path);
                })
              }
            }, (item: RecentNoteItem, index: number): string => `recent_${item.path}_${index}`)
          }
          .layoutWeight(1)
          .width('100%')
          .padding(6)
        }
      }
      .width('90%')
      .height('62%')
      .borderRadius(24)
      .backgroundColor($r('app.color.hm_card_bg'))
      .alignItems(HorizontalAlign.Start)
      .transition(TransitionEffect.scale({ x: 0.94, y: 0.94 })
        .combine(TransitionEffect.opacity(0))
        .animation({ duration: 220, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Top)
    .padding({ top: 64 })
    .transition(TransitionEffect.opacity(0)
      .animation({ duration: 220, curve: Curve.Friction }))
  }

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
