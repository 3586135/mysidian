import { RecentNoteItem } from '../../viewmodel/VaultViewModel';
import {
  formatNoteRelativeTime,
  isDailyNotePath,
  ItemLongPressModifier,
  noteCoverColor,
  noteFolderBadge,
  noteTintBg,
  noteTintFg,
  noteTintPill,
  noteTitleFromPath
} from './NoteActionHelper';

/**
 * 卡片右侧「更多操作」三点按钮（独立 @ComponentV2，适配 Repeat.virtualScroll 组件复用时的响应式着色）。
 */
@ComponentV2
struct CardMoreDotsButton {
  @Param tintColor: Resource = $r('app.color.design_text_secondary');
  @Param compact: boolean = false;
  @Event onTap: () => void = (): void => {};

  build() {
    Stack() {
      Row({ space: this.compact ? 2.2 : 2.8 }) {
        Circle({ width: this.compact ? 2.6 : 3.2, height: this.compact ? 2.6 : 3.2 }).fill(this.tintColor)
        Circle({ width: this.compact ? 2.6 : 3.2, height: this.compact ? 2.6 : 3.2 }).fill(this.tintColor)
        Circle({ width: this.compact ? 2.6 : 3.2, height: this.compact ? 2.6 : 3.2 }).fill(this.tintColor)
      }
      .opacity(0.78)
    }
    .width(this.compact ? 26 : 34)
    .height(this.compact ? 24 : 34)
    .borderRadius(this.compact ? 8 : 10)
    .accessibilityText($r('app.string.note_more_actions'))
    .onClick(() => {
      this.onTap();
    })
  }
}

function resolveTimelinePrimaryBadge(item: RecentNoteItem, fallbackIdx: number): string {
  if (item.title.length >= 10 && item.title.charAt(4) === '-' && item.title.charAt(7) === '-') {
    return item.title.substring(8, 10);
  }
  if (item.openedAt > 0) {
    const d: Date = new Date(item.openedAt);
    const day: number = d.getDate();
    return day < 10 ? `0${day}` : `${day}`;
  }
  if (item.title.length >= 2 && item.title.charAt(0) >= '0' && item.title.charAt(0) <= '9' &&
    item.title.charAt(1) >= '0' && item.title.charAt(1) <= '9') {
    return item.title.substring(0, 2);
  }
  const seq: number = fallbackIdx + 1;
  return seq < 10 ? `0${seq}` : `${seq}`;
}

function resolveTimelineSecondaryBadge(item: RecentNoteItem): ResourceStr {
  if (item.title.length >= 10 && item.title.charAt(4) === '-' && item.title.charAt(7) === '-') {
    const monthNum: number = Number.parseInt(item.title.substring(5, 7));
    if (!Number.isNaN(monthNum) && monthNum >= 1 && monthNum <= 12) {
      return $r('app.string.timeline_month_fmt', monthNum);
    }
  }
  if (item.openedAt > 0) {
    const d: Date = new Date(item.openedAt);
    return $r('app.string.timeline_month_fmt', d.getMonth() + 1);
  }
  return $r('app.string.more_stat_notes');
}

function createNoteLongPressModifier(
  resolvePath: () => string,
  onLongPress: (path: string, isDir: boolean) => void,
  onLongPressEnd: () => void
): ItemLongPressModifier {
  return new ItemLongPressModifier(
    '',
    false,
    (targetPath: string, isDir: boolean): void => {
      onLongPress(targetPath, isDir);
    },
    (): void => {
      onLongPressEnd();
    },
    (): void => {
      onLongPressEnd();
    },
    resolvePath
  );
}

/** 首页素雅笔记卡片（@ComponentV2 封装以支持 Repeat.virtualScroll 复用刷新）。 */
@ComponentV2
export struct HomeRecentNoteCard {
  @Param item: RecentNoteItem = new RecentNoteItem();
  @Param bookmarked: boolean = false;
  @Event onOpen: (path: string) => void = (_path: string): void => {};
  @Event onMore: (path: string) => void = (_path: string): void => {};
  @Event onLongPress: (path: string, isDir: boolean) => void = (_p: string, _d: boolean): void => {};
  @Event onLongPressEnd: () => void = (): void => {};

  private longPressMod: ItemLongPressModifier = createNoteLongPressModifier(
    (): string => this.item.path,
    (targetPath: string, isDir: boolean): void => { this.onLongPress(targetPath, isDir); },
    (): void => { this.onLongPressEnd(); }
  );

  build() {
    Row({ space: 12 }) {
      Stack() {
        SymbolGlyph(isDailyNotePath(this.item.path) ? $r('sys.symbol.calendar') : $r('sys.symbol.doc_plaintext'))
          .fontSize(18)
          .fontColor([noteTintFg(this.item.path)])
      }
      .width(38)
      .height(42)
      .borderRadius(11)
      .backgroundColor(noteTintPill(this.item.path))

      Column({ space: 5 }) {
        Row({ space: 6 }) {
          Text(this.item.title)
            .fontSize(15.5)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_text_primary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.bookmarked) {
            SymbolGlyph($r('sys.symbol.star_fill'))
              .fontSize(12)
              .fontColor([$r('app.color.design_accent')])
          }
          if (this.item.openedAt > 0) {
            Text(formatNoteRelativeTime(this.item.openedAt))
              .fontSize(11.5)
              .fontColor(noteTintFg(this.item.path))
          }
        }
        .width('100%')

        Row({ space: 6 }) {
          Text(noteFolderBadge(this.item.path))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(noteTintFg(this.item.path))
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .borderRadius(7)
            .backgroundColor(noteTintPill(this.item.path))
            .maxLines(1)
          Text(this.item.path)
            .fontSize(11.5)
            .fontColor($r('app.color.design_text_secondary'))
            .opacity(0.85)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      CardMoreDotsButton({
        tintColor: noteTintFg(this.item.path),
        compact: false,
        onTap: (): void => {
          this.onMore(this.item.path);
        }
      })
    }
    .width('100%')
    .padding({ left: 12, right: 10, top: 12, bottom: 12 })
    .borderRadius(16)
    .backgroundColor(noteTintBg(this.item.path))
    .border({ width: 0.8, color: noteTintPill(this.item.path) })
    .gestureModifier(this.longPressMod)
    .onClick(() => {
      this.onOpen(this.item.path);
    })
  }
}

/** 首页收藏笔记卡片（@ComponentV2 封装，支持虚拟滚动正确刷新）。 */
@ComponentV2
export struct HomeBookmarkNoteCard {
  @Param item: RecentNoteItem = new RecentNoteItem();
  @Event onOpen: (path: string) => void = (_path: string): void => {};
  @Event onToggleBookmark: (path: string) => void = (_path: string): void => {};
  @Event onMore: (path: string) => void = (_path: string): void => {};
  @Event onLongPress: (path: string, isDir: boolean) => void = (_p: string, _d: boolean): void => {};
  @Event onLongPressEnd: () => void = (): void => {};

  private longPressMod: ItemLongPressModifier = createNoteLongPressModifier(
    (): string => this.item.path,
    (targetPath: string, isDir: boolean): void => { this.onLongPress(targetPath, isDir); },
    (): void => { this.onLongPressEnd(); }
  );

  build() {
    Row({ space: 12 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.star_fill'))
          .fontSize(16)
          .fontColor([$r('app.color.design_accent')])
      }
      .width(36)
      .height(36)
      .borderRadius(10)
      .backgroundColor(noteTintPill(this.item.path))
      .onClick(() => {
        this.onToggleBookmark(this.item.path);
      })

      Column({ space: 4 }) {
        Text(noteTitleFromPath(this.item.path))
          .fontSize(15.5)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 6 }) {
          Text(noteFolderBadge(this.item.path))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(noteTintFg(this.item.path))
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .borderRadius(7)
            .backgroundColor(noteTintPill(this.item.path))
            .maxLines(1)
          Text(this.item.path)
            .fontSize(11.5)
            .fontColor($r('app.color.design_text_secondary'))
            .opacity(0.85)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      CardMoreDotsButton({
        tintColor: noteTintFg(this.item.path),
        compact: false,
        onTap: (): void => {
          this.onMore(this.item.path);
        }
      })
    }
    .width('100%')
    .padding({ left: 12, right: 10, top: 12, bottom: 12 })
    .borderRadius(16)
    .backgroundColor(noteTintBg(this.item.path))
    .border({ width: 0.8, color: noteTintPill(this.item.path) })
    .gestureModifier(this.longPressMod)
    .onClick(() => {
      this.onOpen(this.item.path);
    })
  }
}

/** 时间线流单行笔记卡片（@ComponentV2 封装，支持 Repeat.virtualScroll 复用刷新）。 */
@ComponentV2
export struct HomeTimelineNoteRow {
  @Param item: RecentNoteItem = new RecentNoteItem();
  @Param index: number = 0;
  @Param bookmarked: boolean = false;
  @Event onOpen: (path: string) => void = (_path: string): void => {};
  @Event onToggleBookmark: (path: string) => void = (_path: string): void => {};
  @Event onMore: (path: string) => void = (_path: string): void => {};
  @Event onLongPress: (path: string, isDir: boolean) => void = (_p: string, _d: boolean): void => {};
  @Event onLongPressEnd: () => void = (): void => {};

  private longPressMod: ItemLongPressModifier = createNoteLongPressModifier(
    (): string => this.item.path,
    (targetPath: string, isDir: boolean): void => { this.onLongPress(targetPath, isDir); },
    (): void => { this.onLongPressEnd(); }
  );

  build() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(resolveTimelinePrimaryBadge(this.item, this.index))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.design_text_primary'))
        Text(resolveTimelineSecondaryBadge(this.item))
          .fontSize(11)
          .fontColor($r('app.color.design_text_secondary'))
      }
      .width(44)
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 4 })

      Column({ space: 10 }) {
        Row({ space: 10 }) {
          Column() {
            Text(this.item.title.length > 0 ?
              this.item.title.substring(0, Math.min(2, this.item.title.length)) : 'MD')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.design_cover_text'))
              .maxLines(1)
          }
          .width(36)
          .height(42)
          .borderRadius(8)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(noteCoverColor(this.item.path))
          .border({ width: 1, color: $r('app.color.design_stroke') })

          Column({ space: 4 }) {
            Text(this.item.title)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.design_text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(noteFolderBadge(this.item.path))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(noteTintFg(this.item.path))
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(8)
              .backgroundColor(noteTintPill(this.item.path))
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Row({ space: 2 }) {
            Stack() {
              SymbolGlyph(this.bookmarked ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
                .fontSize(16)
                .fontColor([this.bookmarked ?
                  $r('app.color.design_accent') : noteTintFg(this.item.path)])
            }
            .width(32)
            .height(32)
            .onClick(() => {
              this.onToggleBookmark(this.item.path);
            })

            CardMoreDotsButton({
              tintColor: noteTintFg(this.item.path),
              compact: false,
              onTap: (): void => {
                this.onMore(this.item.path);
              }
            })
          }
        }
        .width('100%')

        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(13)
            .fontColor([noteTintFg(this.item.path)])
          Text(this.item.path)
            .fontSize(12)
            .fontColor($r('app.color.design_text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.item.openedAt > 0) {
            Text(formatNoteRelativeTime(this.item.openedAt))
              .fontSize(11)
              .fontColor(noteTintFg(this.item.path))
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .padding(14)
      .borderRadius(18)
      .backgroundColor(noteTintBg(this.item.path))
      .border({ width: 0.8, color: noteTintPill(this.item.path) })
      .gestureModifier(this.longPressMod)
      .onClick(() => {
        this.onOpen(this.item.path);
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}

/** 书架宫格模式莫兰迪便签封面卡（@ComponentV2 封装，支持 Repeat.virtualScroll 复用刷新）。 */
@ComponentV2
export struct HomeBookCoverCard {
  @Param item: RecentNoteItem = new RecentNoteItem();
  @Param coverHeight: number = 130;
  @Param bookmarked: boolean = false;
  @Event onOpen: (path: string) => void = (_path: string): void => {};
  @Event onToggleBookmark: (path: string) => void = (_path: string): void => {};
  @Event onMore: (path: string) => void = (_path: string): void => {};
  @Event onLongPress: (path: string, isDir: boolean) => void = (_p: string, _d: boolean): void => {};
  @Event onLongPressEnd: () => void = (): void => {};

  private longPressMod: ItemLongPressModifier = createNoteLongPressModifier(
    (): string => this.item.path,
    (targetPath: string, isDir: boolean): void => { this.onLongPress(targetPath, isDir); },
    (): void => { this.onLongPressEnd(); }
  );

  build() {
    Column({ space: 6 }) {
      Column() {
        Column() {
          Row() {
            Blank()
            Stack() {
              SymbolGlyph(this.bookmarked ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
                .fontSize(12)
                .fontColor([$r('app.color.design_cover_text')])
                .opacity(this.bookmarked ? 1.0 : 0.72)
            }
            .width(22)
            .height(22)
            .alignContent(Alignment.Center)
            .onClick(() => {
              this.onToggleBookmark(this.item.path);
            })
          }
          .width('100%')

          Text(this.item.title)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_cover_text'))
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .lineHeight(16)
            .width('100%')
            .margin({ top: 4 })

          Row()
            .width(18)
            .height(1)
            .backgroundColor($r('app.color.design_cover_text'))
            .opacity(0.65)
            .margin({ top: 6 })

          Blank()

          Text(noteFolderBadge(this.item.path))
            .fontSize(9)
            .fontColor($r('app.color.design_cover_text'))
            .opacity(0.85)
            .maxLines(1)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 7, right: 7, top: 5, bottom: 7 })
        .borderRadius(6)
        .border({ width: 1, color: $r('app.color.design_cover_text') })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height(this.coverHeight)
      .padding(6)
      .borderRadius(10)
      .backgroundColor(noteCoverColor(this.item.path))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .shadow({ radius: 10, color: $r('app.color.design_shadow'), offsetY: 3 })

      Text(this.item.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.design_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row({ space: 4 }) {
        Text(this.item.openedAt > 0 ? formatNoteRelativeTime(this.item.openedAt) : this.item.path)
          .fontSize(11)
          .fontColor($r('app.color.design_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        CardMoreDotsButton({
          tintColor: $r('app.color.design_text_secondary'),
          compact: true,
          onTap: (): void => {
            this.onMore(this.item.path);
          }
        })
      }
      .width('100%')
      .height(24)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .gestureModifier(this.longPressMod)
    .onClick(() => {
      this.onOpen(this.item.path);
    })
  }
}

/** 书架宫格首行 2:1 最近编辑笔记精选大卡（@ComponentV2 封装）。 */
@ComponentV2
export struct HomeFeaturedSpreadCard {
  @Param item: RecentNoteItem = new RecentNoteItem();
  @Param bookmarked: boolean = false;
  @Event onOpen: (path: string) => void = (_path: string): void => {};
  @Event onToggleBookmark: (path: string) => void = (_path: string): void => {};
  @Event onMore: (path: string) => void = (_path: string): void => {};
  @Event onLongPress: (path: string, isDir: boolean) => void = (_p: string, _d: boolean): void => {};
  @Event onLongPressEnd: () => void = (): void => {};

  private longPressMod: ItemLongPressModifier = createNoteLongPressModifier(
    (): string => this.item.path,
    (targetPath: string, isDir: boolean): void => { this.onLongPress(targetPath, isDir); },
    (): void => { this.onLongPressEnd(); }
  );

  build() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Text($r('app.string.files_featured_badge'))
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.design_accent'))
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .borderRadius(6)
              .backgroundColor($r('app.color.design_accent_weak'))
            Text(noteFolderBadge(this.item.path))
              .fontSize(10)
              .fontColor($r('app.color.design_cover_text'))
              .opacity(0.65)
              .maxLines(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.item.title)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.design_cover_text'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .lineHeight(20)
            .width('100%')

          Blank()

          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.doc_plaintext'))
              .fontSize(11)
              .fontColor([$r('app.color.design_cover_text')])
              .opacity(0.7)
            Text(this.item.path)
              .fontSize(10)
              .fontColor($r('app.color.design_cover_text'))
              .opacity(0.7)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 10 })
        .alignItems(HorizontalAlign.Start)

        Stack() {
          SymbolGlyph(this.bookmarked ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
            .fontSize(14)
            .fontColor([this.bookmarked ?
              $r('app.color.design_accent') : $r('app.color.design_cover_text')])
        }
        .width(28)
        .height(28)
        .margin({ top: 4, right: 4 })
        .onClick(() => {
          this.onToggleBookmark(this.item.path);
        })
      }
      .width('100%')
      .height(124)
      .borderRadius(12)
      .backgroundColor($r('app.color.design_cover_ink'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .shadow({ radius: 12, color: $r('app.color.design_shadow'), offsetY: 4 })

      Text(this.item.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.design_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row({ space: 4 }) {
        Text(this.item.openedAt > 0 ? formatNoteRelativeTime(this.item.openedAt) : noteFolderBadge(this.item.path))
          .fontSize(11)
          .fontColor($r('app.color.design_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        CardMoreDotsButton({
          tintColor: $r('app.color.design_text_secondary'),
          compact: true,
          onTap: (): void => {
            this.onMore(this.item.path);
          }
        })
      }
      .width('100%')
      .height(24)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .gestureModifier(this.longPressMod)
    .onClick(() => {
      this.onOpen(this.item.path);
    })
  }
}
