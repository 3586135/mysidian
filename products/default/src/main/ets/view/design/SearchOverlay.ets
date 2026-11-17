import { SearchHit, TagRef } from '@ohos/domain';
import { VaultViewModel } from '../../viewmodel/VaultViewModel';
import { SearchViewModel, TagSortMode } from '../../viewmodel/SearchViewModel';

/**
 * Material 3 全文搜索浮层：支持全文 / 标签 / 属性（frontmatter）三种模式。
 * 数据与检索逻辑归 SearchViewModel；打开时重置为全文模式并展示初始结果。
 */
@ComponentV2
export struct SearchOverlay {
  @Param vm: VaultViewModel = new VaultViewModel();
  @Param searchVm: SearchViewModel = new SearchViewModel();
  @Event onOpenNote: (path: string) => void = (path: string): void => {};
  @Event onClose: () => void = (): void => {};

  /** 搜索输入防抖句柄。 */
  private debounceId: number = -1;
  private static readonly DEBOUNCE_MS: number = 250;

  aboutToAppear(): void {
    this.searchVm.search(this.vm.currentVault.id, '');
  }

  aboutToDisappear(): void {
    if (this.debounceId >= 0) {
      clearTimeout(this.debounceId);
      this.debounceId = -1;
    }
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
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([$r('app.color.design_accent')])
          TextInput({
            placeholder: this.placeholderText(),
            text: this.searchVm.keyword
          })
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .padding({ left: 0, right: 8 })
            .height(44)
            .fontSize(16)
            .placeholderColor($r('app.color.design_text_secondary'))
            .placeholderFont({ size: 15 })
            .fontColor($r('app.color.design_text_primary'))
            .caretColor($r('app.color.design_accent'))
            .onChange((value: string) => {
              this.onKeywordChange(value);
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .borderRadius({ topLeft: 24, topRight: 24 })
        .backgroundColor($r('app.color.design_elevated'))

        Row({ space: 8 }) {
          this.modeChip(0, $r('app.string.search_mode_all'))
          this.modeChip(1, $r('app.string.search_mode_tag'))
          this.modeChip(2, $r('app.string.search_mode_prop'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 8 })

        Divider()
          .color($r('app.color.design_divider'))

        if (this.searchVm.searchMode === 1) {
          this.tagModeBody()
        } else if (this.searchVm.hits.length === 0) {
          Column() {
            Text(this.searchVm.busy ? $r('app.string.search_loading') : $r('app.string.search_empty'))
              .fontSize(14)
              .fontColor($r('app.color.design_text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          this.hitList()
        }
      }
      .width('90%')
      .height('68%')
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
  }

  /** 模式 chip（全文 / 标签 / 属性）。 */
  @Builder
  modeChip(mode: number, label: Resource) {
    Text(label)
      .fontSize(12)
      .fontWeight(this.searchVm.searchMode === mode ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.searchVm.searchMode === mode ? $r('app.color.design_text_primary')
        : $r('app.color.design_text_secondary'))
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.searchVm.searchMode === mode ? $r('app.color.design_elevated')
        : Color.Transparent)
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .onClick(() => {
        this.switchMode(mode);
      })
  }

  /** 标签模式主体：多行平铺标签面板 + 选中标签后的笔记列表，整体上下滑动。 */
  @Builder
  tagModeBody() {
    Scroll() {
      Column({ space: 10 }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.hash'))
            .fontSize(14)
            .fontColor([$r('app.color.design_accent')])
          Text($r('app.string.search_tags_all_header', this.searchVm.tagChips.length))
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.design_text_primary'))
            .layoutWeight(1)
          Row({ space: 4 }) {
            this.tagSortChip(TagSortMode.COUNT_DESC, $r('app.string.search_tags_sort_count'))
            this.tagSortChip(TagSortMode.NAME_ASC, $r('app.string.search_tags_sort_name'))
          }
          if (this.searchVm.activeTag.length > 0) {
            Row({ space: 4 }) {
              Text($r('app.string.search_tags_clear_filter', this.searchVm.activeTag))
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.design_accent'))
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(10)
                .fontColor([$r('app.color.design_accent')])
            }
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(10)
            .backgroundColor($r('app.color.design_accent_weak'))
            .onClick(() => {
              this.selectTag(this.searchVm.activeTag);
            })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10 })

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.searchVm.tagChips, (ref: TagRef) => {
            Text(`#${ref.tag} (${ref.count})`)
              .fontSize(12)
              .fontWeight(this.searchVm.activeTag === ref.tag ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.searchVm.activeTag === ref.tag ? $r('app.color.design_on_accent')
                : $r('app.color.design_accent'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(14)
              .backgroundColor(this.searchVm.activeTag === ref.tag ?
                $r('app.color.design_accent') : $r('app.color.design_accent_weak'))
              .margin({ right: 8, bottom: 8 })
              .onClick(() => {
                this.selectTag(ref.tag);
              })
          }, (ref: TagRef): string =>
            `tag_${this.searchVm.tagSortMode}_${ref.tag}_${ref.count}_${this.searchVm.activeTag === ref.tag}`)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        if (this.searchVm.activeTag.length > 0) {
          Divider()
            .color($r('app.color.design_divider'))
            .margin({ left: 16, right: 16 })

          if (this.searchVm.hits.length === 0) {
            Text(this.searchVm.busy ? $r('app.string.search_loading') : $r('app.string.search_empty'))
              .fontSize(14)
              .fontColor($r('app.color.design_text_secondary'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 16, bottom: 16 })
          } else {
            Column({ space: 4 }) {
              ForEach(this.searchVm.hits, (hit: SearchHit) => {
                Column() {
                  Text(hit.title)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.design_text_primary'))
                    .width('100%')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(hit.snippet.length > 0 ? hit.snippet : hit.path)
                    .fontSize(12)
                    .fontColor($r('app.color.design_text_secondary'))
                    .width('100%')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 2 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                .borderRadius(14)
                .onClick(() => {
                  this.onOpenNote(hit.path);
                })
              }, (hit: SearchHit): string => `tag_hit_${hit.path}`)
            }
            .width('100%')
            .padding({ left: 6, right: 6, bottom: 10 })
          }
        }
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  /** 命中列表。 */
  @Builder
  hitList() {
    List() {
      ForEach(this.searchVm.hits, (hit: SearchHit) => {
        ListItem() {
          Column() {
            Text(hit.title)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.design_text_primary'))
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(hit.snippet.length > 0 ? hit.snippet : hit.path)
              .fontSize(12)
              .fontColor($r('app.color.design_text_secondary'))
              .width('100%')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius(14)
          .onClick(() => {
            this.onOpenNote(hit.path);
          })
        }
      }, (hit: SearchHit): string => `hit_${hit.path}`)
    }
    .layoutWeight(1)
    .width('100%')
    .padding(6)
  }

  /** 搜索框占位文案（按模式）。 */
  private placeholderText(): Resource {
    if (this.searchVm.searchMode === 1) {
      return $r('app.string.search_tag_placeholder');
    }
    if (this.searchVm.searchMode === 2) {
      return $r('app.string.search_prop_placeholder');
    }
    return $r('app.string.search_placeholder');
  }

  /** 搜索输入防抖。 */
  private onKeywordChange(value: string): void {
    if (this.debounceId >= 0) {
      clearTimeout(this.debounceId);
    }
    this.debounceId = setTimeout((): void => {
      this.searchVm.search(this.vm.currentVault.id, value);
    }, SearchOverlay.DEBOUNCE_MS);
  }

  /** 切换搜索模式（0 全文 / 1 标签 / 2 属性）。 */
  private switchMode(mode: number): void {
    if (this.debounceId >= 0) {
      clearTimeout(this.debounceId);
      this.debounceId = -1;
    }
    this.searchVm.setMode(this.vm.currentVault.id, mode);
  }

  /** 选中一个标签，展示该标签下的笔记。 */
  private selectTag(tag: string): void {
    this.searchVm.selectTag(this.vm.currentVault.id, tag);
  }

  /** 标签排序切换胶囊。 */
  @Builder
  tagSortChip(mode: number, label: Resource) {
    Text(label)
      .fontSize(11)
      .fontWeight(this.searchVm.tagSortMode === mode ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.searchVm.tagSortMode === mode ?
        $r('app.color.design_surface_solid') : $r('app.color.design_text_secondary'))
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(10)
      .backgroundColor(this.searchVm.tagSortMode === mode ?
        $r('app.color.design_text_primary') : $r('app.color.design_elevated'))
      .onClick(() => {
        this.searchVm.setTagSortMode(mode);
      })
  }
}
