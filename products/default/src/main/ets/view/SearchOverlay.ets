import { SearchHit, TagRef } from '@ohos/domain';

/**
 * 全文搜索浮层：鸿蒙风格居中模态，模糊蒙层 + 圆角卡片。
 * 支持三种搜索模式：全文 / 标签 / 属性（frontmatter）。
 */
@ComponentV2
export struct SearchOverlay {
  @Param hits: SearchHit[] = [];
  @Param keyword: string = '';
  @Param busy: boolean = false;
  @Param searchMode: number = 0;
  @Param tagChips: TagRef[] = [];
  @Param activeTag: string = '';
  @Event onKeywordChange: (value: string) => void = (value: string): void => {};
  @Event onModeChange: (mode: number) => void = (mode: number): void => {};
  @Event onSelectTag: (tag: string) => void = (tag: string): void => {};
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
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([$r('app.color.hm_accent')])
          TextInput({
            placeholder: this.placeholderText(),
            text: this.keyword
          })
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .padding({ left: 8, right: 8 })
            .height(44)
            .fontSize(16)
            .placeholderColor($r('app.color.hm_text_secondary'))
            .fontColor($r('app.color.hm_text_primary'))
            .caretColor($r('app.color.hm_accent'))
            .onChange((value: string) => {
              this.onKeywordChange(value);
            })
        }
        .width('100%')
        .padding({ left: 14, right: 14 })
        .borderRadius({ topLeft: 24, topRight: 24 })
        .backgroundColor($r('app.color.hm_input_bg'))

        Row({ space: 6 }) {
          this.modeChip(0, $r('app.string.search_mode_all'))
          this.modeChip(1, $r('app.string.search_mode_tag'))
          this.modeChip(2, $r('app.string.search_mode_prop'))
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 8, bottom: 6 })

        Divider()
          .color($r('app.color.hm_divider'))

        if (this.searchMode === 1) {
          this.tagModeBody()
        } else if (this.hits.length === 0) {
          Column() {
            Text(this.busy ? $r('app.string.search_loading') : $r('app.string.search_empty'))
              .fontSize(14)
              .fontColor($r('app.color.hm_text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          this.hitList()
        }
      }
      .width('90%')
      .height('72%')
      .borderRadius(24)
      .backgroundColor($r('app.color.hm_card_bg'))
      .alignItems(HorizontalAlign.Start)
      .transition(TransitionEffect.scale({ x: 0.94, y: 0.94 })
        .combine(TransitionEffect.opacity(0))
        .animation({ duration: 220, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
    .transition(TransitionEffect.opacity(0)
      .animation({ duration: 220, curve: Curve.Friction }))
  }

  @Builder
  modeChip(mode: number, label: Resource) {
    Text(label)
      .fontSize(12)
      .fontColor(this.searchMode === mode ? Color.White : $r('app.color.hm_text_secondary'))
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .borderRadius(14)
      .backgroundColor(this.searchMode === mode ? $r('app.color.hm_accent')
        : $r('app.color.hm_hover_bg'))
      .onClick(() => {
        this.onModeChange(mode);
      })
  }

  /** 标签模式主体：标签候选 chips + 选中标签后的笔记列表。 */
  @Builder
  tagModeBody() {
    Column() {
      Scroll() {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.tagChips, (ref: TagRef, index: number) => {
            Text(`#${ref.tag} (${ref.count})`)
              .fontSize(12)
              .fontColor(this.activeTag === ref.tag ? Color.White : $r('app.color.hm_accent'))
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(12)
              .backgroundColor(this.activeTag === ref.tag ? $r('app.color.hm_accent')
                : $r('app.color.hm_accent_weak'))
              .margin({ right: 6, top: 6 })
              .onClick(() => {
                this.onSelectTag(ref.tag);
              })
          }, (ref: TagRef, index: number): string => `tag_${ref.tag}`)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 4 })
      }
      .width('100%')
      .height(this.activeTag.length > 0 ? '30%' : '100%')
      .align(Alignment.Top)

      if (this.activeTag.length > 0) {
        Divider()
          .color($r('app.color.hm_divider'))

        if (this.hits.length === 0) {
          Column() {
            Text(this.busy ? $r('app.string.search_loading') : $r('app.string.search_empty'))
              .fontSize(14)
              .fontColor($r('app.color.hm_text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          this.hitList()
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  hitList() {
    List() {
      ForEach(this.hits, (hit: SearchHit, index: number) => {
        ListItem() {
          Column() {
            Text(hit.title)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.hm_text_primary'))
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(hit.snippet.length > 0 ? hit.snippet : hit.path)
              .fontSize(12)
              .fontColor($r('app.color.hm_text_secondary'))
              .width('100%')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(8)
          .onClick(() => {
            this.onOpenNote(hit.path);
          })
        }
      }, (hit: SearchHit, index: number): string => `hit_${hit.path}_${index}`)
    }
    .layoutWeight(1)
    .width('100%')
    .padding(6)
  }

  private placeholderText(): Resource {
    if (this.searchMode === 1) {
      return $r('app.string.search_tag_placeholder');
    }
    if (this.searchMode === 2) {
      return $r('app.string.search_prop_placeholder');
    }
    return $r('app.string.search_placeholder');
  }
}
