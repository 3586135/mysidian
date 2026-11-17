import { CalendarDay } from '@ohos/domain';
import { VaultViewModel } from '../../viewmodel/VaultViewModel';

/**
 * Material 3 月历浮层：有日记的日期显示圆点，有未完成任务的日期显示角标。
 * 点击日期打开或创建当天日记，支持切换月份、跳转到今天与本周周报。
 */
@ComponentV2
export struct CalendarSheet {
  @Param vm: VaultViewModel = new VaultViewModel();
  @Event onClose: () => void = (): void => {};
  @Event onNoteMutated: () => void = (): void => {};

  @Local year: number = 2026;
  @Local month: number = 1;
  @Local days: CalendarDay[] = [];
  private loadSeq: number = 0;

  aboutToAppear(): void {
    const now: Date = new Date();
    this.year = now.getFullYear();
    this.month = now.getMonth() + 1;
    this.loadCalendar();
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
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(18)
            .fontColor([$r('app.color.design_text_primary')])
            .width(32)
            .height(32)
            .borderRadius(16)
            .backgroundColor($r('app.color.design_elevated'))
            .onClick(() => {
              this.shiftMonth(-1);
            })
          Text(`${this.year}年${this.month}月`)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_text_primary'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(18)
            .fontColor([$r('app.color.design_text_primary')])
            .width(32)
            .height(32)
            .borderRadius(16)
            .backgroundColor($r('app.color.design_elevated'))
            .onClick(() => {
              this.shiftMonth(1);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row() {
          Text('一').fontSize(11).fontColor($r('app.color.design_text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
          Text('二').fontSize(11).fontColor($r('app.color.design_text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
          Text('三').fontSize(11).fontColor($r('app.color.design_text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
          Text('四').fontSize(11).fontColor($r('app.color.design_text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
          Text('五').fontSize(11).fontColor($r('app.color.design_text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
          Text('六').fontSize(11).fontColor($r('app.color.design_text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
          Text('日').fontSize(11).fontColor($r('app.color.design_text_secondary')).layoutWeight(1).textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({ top: 10, bottom: 4 })

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
            .height(36)
            .fontSize(14)
            .backgroundColor($r('app.color.design_elevated'))
            .fontColor($r('app.color.design_text_primary'))
            .layoutWeight(1)
            .onClick(() => {
              this.goToday();
            })
          Button($r('app.string.calendar_weekly'))
            .type(ButtonType.Capsule)
            .height(36)
            .fontSize(14)
            .backgroundColor($r('app.color.design_accent'))
            .fontColor($r('app.color.design_on_accent'))
            .layoutWeight(1)
            .margin({ left: 12 })
            .onClick(() => {
              this.openWeekly();
            })
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('88%')
      .constraintSize({ maxWidth: 420, maxHeight: 560 })
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

  /** 单个日期格子。 */
  @Builder
  dayCell(cell: CalendarDay) {
    Column() {
      Text(cell.day > 0 ? `${cell.day}` : '')
        .fontSize(13)
        .fontWeight(cell.today ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(cell.today ? $r('app.color.design_accent') : $r('app.color.design_text_primary'))
      if (cell.hasNote) {
        Row()
          .width(5)
          .height(5)
          .borderRadius(3)
          .backgroundColor($r('app.color.design_accent'))
          .margin({ top: 2 })
      }
      if (cell.openTasks > 0) {
        Text(`${cell.openTasks}`)
          .fontSize(9)
          .fontColor($r('app.color.design_on_accent'))
          .width(14)
          .height(14)
          .borderRadius(7)
          .textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.design_danger'))
          .margin({ top: 1 })
      }
    }
    .width('100%')
    .height(46)
    .justifyContent(FlexAlign.Center)
    .borderRadius(10)
    .backgroundColor(cell.today ? $r('app.color.design_accent_weak') : Color.Transparent)
    .onClick(() => {
      if (cell.date.length > 0) {
        this.openDaily(cell.date);
      }
    })
  }

  /** 加载当前月份的日历数据。 */
  private loadCalendar(): void {
    const seq: number = ++this.loadSeq;
    this.vm.calendarMonth(this.year, this.month).then((days: CalendarDay[]): void => {
      if (seq !== this.loadSeq) {
        return;
      }
      this.days = days;
    });
  }

  /** 切换月份。 */
  private shiftMonth(delta: number): void {
    let year: number = this.year;
    let month: number = this.month + delta;
    if (month < 1) {
      month = 12;
      year--;
    }
    if (month > 12) {
      month = 1;
      year++;
    }
    this.year = year;
    this.month = month;
    this.loadCalendar();
  }

  /** 跳转到今天。 */
  private goToday(): void {
    const now: Date = new Date();
    this.year = now.getFullYear();
    this.month = now.getMonth() + 1;
    this.loadCalendar();
  }

  /** 打开指定日期的日记。 */
  private openDaily(date: string): void {
    this.onClose();
    this.vm.openDailyNoteByDate(date).then((): void => {
      this.onNoteMutated();
    });
  }

  /** 打开本周周报。 */
  private openWeekly(): void {
    this.onClose();
    this.vm.openWeeklyNote().then((): void => {
      this.onNoteMutated();
    });
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
