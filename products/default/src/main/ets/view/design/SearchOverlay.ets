import { SearchHit, TagRef } from '@ohos/domain';
import { VaultViewModel } from '../../viewmodel/VaultViewModel';
import { SearchViewModel } from '../../viewmodel/SearchViewModel';

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

  /** 标签模式主体：标签候选 chips + 选中标签后的笔记列表。 */
  @Builder
  tagModeBody() {
    Column() {
      Scroll() {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.searchVm.tagChips, (ref: TagRef) => {
            Text(`#${ref.tag} (${ref.count})`)
              .fontSize(12)
              .fontWeight(this.searchVm.activeTag === ref.tag ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.searchVm.activeTag === ref.tag ? Color.White
                : $r('app.color.design_accent'))
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .borderRadius(14)
              .backgroundColor(this.searchVm.activeTag === ref.tag ?
                $r('app.color.design_accent') : $r('app.color.design_accent_weak'))
              .margin({ right: 6, top: 6 })
              .onClick(() => {
                this.selectTag(ref.tag);
              })
          }, (ref: TagRef): string => `tag_${ref.tag}`)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 6 })
      }
      .width('100%')
      .height(this.searchVm.activeTag.length > 0 ? '30%' : '100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)

      if (this.searchVm.activeTag.length > 0) {
        Divider()
          .color($r('app.color.design_divider'))

        if (this.searchVm.hits.length === 0) {
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
    }
    .width('100%')
    .layoutWeight(1)
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
}
