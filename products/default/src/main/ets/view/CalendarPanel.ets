import { CalendarDay } from '@ohos/domain';

/**
 * 原生月历视图（对齐 Obsidian Calendar 插件）。
 *
 * 有日记的日期显示圆点，有未完成任务的日期显示角标；
 * 点击日期打开或创建当天日记，可切换月份与跳转到今天 / 本周周报。
 */
@ComponentV2
export struct CalendarPanel {
  @Param days: CalendarDay[] = [];
  @Param year: number = 2026;
  @Param month: number = 1;
  @Event onPrevMonth: () => void = (): void => {};
  @Event onNextMonth: () => void = (): void => {};
  @Event onToday: () => void = (): void => {};
  @Event onOpenWeekly: () => void = (): void => {};
  @Event onOpenDay: (date: string) => void = (date: string): void => {};
  @Event onClose: () => void = (): void => {};

  build() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(18)
          .fontColor([$r('app.color.hm_text_primary')])
          .width(32)
          .height(32)
          .onClick(() => {
            this.onPrevMonth();
          })
        Text(`${this.year}年${this.month}月`)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hm_text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([$r('app.color.hm_text_primary')])
          .width(32)
          .height(32)
          .onClick(() => {
            this.onNextMonth();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 8, right: 8 })

      Row() {
        Text('一').fontSize(11).fontColor($r('app.color.hm_text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
        Text('二').fontSize(11).fontColor($r('app.color.hm_text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
        Text('三').fontSize(11).fontColor($r('app.color.hm_text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
        Text('四').fontSize(11).fontColor($r('app.color.hm_text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
        Text('五').fontSize(11).fontColor($r('app.color.hm_text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
        Text('六').fontSize(11).fontColor($r('app.color.hm_text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
        Text('日').fontSize(11).fontColor($r('app.color.hm_text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ top: 8, bottom: 4 })

      Grid() {
        ForEach(this.cells(), (cell: CalendarDay) => {
          GridItem() {
            this.dayCell(cell)
          }
        }, (cell: CalendarDay): string => `cal_${cell.date}_${cell.day}`)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
      .rowsGap(2)
      .columnsGap(2)
      .width('100%')
      .layoutWeight(1)

      Row() {
        Button($r('app.string.calendar_today'))
          .type(ButtonType.Capsule)
          .height(34)
          .fontSize(13)
          .backgroundColor($r('app.color.hm_hover_bg'))
          .fontColor($r('app.color.hm_text_primary'))
          .layoutWeight(1)
          .onClick(() => {
            this.onToday();
          })
        Button($r('app.string.calendar_weekly'))
          .type(ButtonType.Capsule)
          .height(34)
          .fontSize(13)
          .backgroundColor($r('app.color.hm_accent'))
          .fontColor(Color.White)
          .layoutWeight(1)
          .margin({ left: 10 })
          .onClick(() => {
            this.onOpenWeekly();
          })
      }
      .width('100%')
      .padding({ top: 8, bottom: 4 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  /** 单个日期格子。 */
  @Builder
  dayCell(cell: CalendarDay) {
    Column() {
      Text(cell.day > 0 ? `${cell.day}` : '')
        .fontSize(13)
        .fontWeight(cell.today ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(cell.today ? $r('app.color.hm_accent') : $r('app.color.hm_text_primary'))
      if (cell.hasNote) {
        Row()
          .width(5)
          .height(5)
          .borderRadius(3)
          .backgroundColor($r('app.color.hm_accent'))
          .margin({ top: 2 })
      }
      if (cell.openTasks > 0) {
        Text(`${cell.openTasks}`)
          .fontSize(9)
          .fontColor(Color.White)
          .width(14)
          .height(14)
          .borderRadius(7)
          .textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.hm_danger'))
          .margin({ top: 1 })
      }
    }
    .width('100%')
    .height(46)
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .backgroundColor(cell.today ? $r('app.color.hm_accent_weak') : Color.Transparent)
    .onClick(() => {
      if (cell.date.length > 0) {
        this.onOpenDay(cell.date);
      }
    })
  }

  /** 计算月历格子（补齐首尾空位，整周对齐）。 */
  private cells(): CalendarDay[] {
    const list: CalendarDay[] = [];
    const first: Date = new Date(this.year, this.month - 1, 1);
    const leading: number = (first.getDay() + 6) % 7;
    for (let index = 0; index < leading; index++) {
      list.push(new CalendarDay());
    }
    for (const day of this.days) {
      list.push(day);
    }
    while (list.length % 7 !== 0) {
      list.push(new CalendarDay());
    }
    return list;
  }
}
