import { BacklinkItem, MdProperty, OutlineEntry } from '@ohos/domain';

/**
 * 笔记信息面板：大纲 / 反向链接 / 标签 / 属性。
 */
@ComponentV2
export struct NoteInfoPanel {
  @Param outlineEntries: OutlineEntry[] = [];
  @Param backlinks: BacklinkItem[] = [];
  @Param tags: string[] = [];
  @Param properties: MdProperty[] = [];
  @Param currentTab: number = 0;
  @Event onTabChange: (index: number) => void = (index: number): void => {};
  @Event onOpenNote: (path: string) => void = (path: string): void => {};
  @Event onOpenTag: (tag: string) => void = (tag: string): void => {};

  build() {
    Column() {
      Row() {
        this.tabItem($r('app.string.tab_outline'), 0)
        this.tabItem($r('app.string.tab_backlinks'), 1)
        this.tabItem($r('app.string.tab_tags'), 2)
        this.tabItem($r('app.string.tab_props'), 3)
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })
      Divider()
        .color($r('sys.color.ohos_id_color_text_secondary'))
      Scroll() {
        Column() {
          if (this.currentTab === 0) {
            this.outlineView()
          } else if (this.currentTab === 1) {
            this.backlinksView()
          } else if (this.currentTab === 2) {
            this.tagsView()
          } else {
            this.propertiesView()
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  tabItem(title: ResourceStr, index: number) {
    Text(title)
      .fontSize(14)
      .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.currentTab === index ?
        $r('sys.color.ohos_id_color_emphasize') : $r('sys.color.ohos_id_color_text_secondary'))
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .onClick(() => {
        this.onTabChange(index);
      })
  }

  @Builder
  outlineView() {
    Column() {
      if (this.outlineEntries.length === 0) {
        Text($r('app.string.empty_outline'))
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      } else {
        ForEach(this.outlineEntries, (entry: OutlineEntry, index: number) => {
          Text(entry.text)
            .fontSize(14)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .width('100%')
            .padding({ left: 8 + (entry.level - 1) * 12, top: 4, bottom: 4 })
        }, (entry: OutlineEntry, index: number): string => `outline_${index}`)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  backlinksView() {
    Column() {
      if (this.backlinks.length === 0) {
        Text($r('app.string.empty_backlinks'))
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      } else {
        ForEach(this.backlinks, (item: BacklinkItem, index: number) => {
          Column() {
            Text(item.sourceTitle)
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_emphasize'))
              .width('100%')
            Text(item.context)
              .fontSize(12)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ top: 6, bottom: 6 })
          .onClick(() => {
            this.onOpenNote(item.sourcePath);
          })
        }, (item: BacklinkItem, index: number): string => `backlink_${index}`)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  tagsView() {
    Column() {
      if (this.tags.length === 0) {
        Text($r('app.string.empty_tags'))
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.tags, (tag: string, index: number) => {
            Text(`#${tag}`)
              .fontSize(13)
              .fontColor($r('sys.color.ohos_id_color_emphasize'))
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(10)
              .backgroundColor($r('sys.color.ohos_id_color_component_activated'))
              .margin({ right: 6, top: 6 })
              .onClick(() => {
                this.onOpenTag(tag);
              })
          }, (tag: string, index: number): string => `tag_${index}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  propertiesView() {
    Column() {
      if (this.properties.length === 0) {
        Text($r('app.string.empty_props'))
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      } else {
        ForEach(this.properties, (property: MdProperty, index: number) => {
          Row() {
            Text(property.key)
              .fontSize(13)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width('35%')
            Text(this.propertyValue(property))
              .fontSize(13)
              .fontColor($r('sys.color.ohos_id_color_text_primary'))
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
        }, (property: MdProperty, index: number): string => `prop_${index}`)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private propertyValue(property: MdProperty): string {
    if (property.listValue.length > 0) {
      return property.listValue.join(', ');
    }
    return property.value;
  }
}
