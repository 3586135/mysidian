import { BacklinkItem, MdProperty, OutlineEntry } from '@ohos/domain';

/**
 * 笔记信息面板：自定义页签栏承载 大纲 / 反链 / 标签 / 属性。
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
  @Event onOutlineClick: (entry: OutlineEntry) => void = (entry: OutlineEntry): void => {};
  private tabsController: TabsController = new TabsController();

  build() {
    Column() {
      Row() {
        this.tabButton(0, $r('app.string.tab_outline'))
        this.tabButton(1, $r('app.string.tab_backlinks'))
        this.tabButton(2, $r('app.string.tab_tags'))
        this.tabButton(3, $r('app.string.tab_props'))
      }
      .width('100%')
      .height(48)

      Tabs({ index: this.currentTab, controller: this.tabsController }) {
        TabContent() {
          this.outlineView()
        }
        TabContent() {
          this.backlinksView()
        }
        TabContent() {
          this.tagsView()
        }
        TabContent() {
          this.propertiesView()
        }
      }
      .barHeight(0)
      .scrollable(true)
      .width('100%')
      .layoutWeight(1)
      .onChange((index: number) => {
        this.onTabChange(index);
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  tabButton(index: number, label: Resource) {
    Column({ space: 3 }) {
      Text(label)
        .fontSize(15)
        .fontWeight(this.currentTab === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentTab === index ? $r('app.color.hm_accent')
          : $r('app.color.hm_text_secondary'))
        .maxLines(1)
      Column()
        .width(18)
        .height(2)
        .borderRadius(1)
        .backgroundColor(this.currentTab === index ? $r('app.color.hm_accent')
          : Color.Transparent)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.tabsController.changeIndex(index);
    })
  }

  @Builder
  outlineView() {
    Scroll() {
      Column() {
        if (this.outlineEntries.length === 0) {
          Text($r('app.string.empty_outline'))
            .fontSize(13)
            .fontColor($r('app.color.hm_text_secondary'))
        } else {
          ForEach(this.outlineEntries, (entry: OutlineEntry, index: number) => {
            Text(entry.text)
              .fontSize(14)
              .fontColor($r('app.color.hm_text_primary'))
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 8 + (entry.level - 1) * 12, top: 6, bottom: 6 })
              .borderRadius(6)
              .onClick(() => {
                this.onOutlineClick(entry);
              })
          }, (entry: OutlineEntry, index: number): string => `outline_${index}`)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  backlinksView() {
    Scroll() {
      Column() {
        if (this.backlinks.length === 0) {
          Text($r('app.string.empty_backlinks'))
            .fontSize(13)
            .fontColor($r('app.color.hm_text_secondary'))
        } else {
          ForEach(this.backlinks, (item: BacklinkItem, index: number) => {
            Column() {
              Text(item.sourceTitle)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.hm_accent'))
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(item.context)
                .fontSize(12)
                .fontColor($r('app.color.hm_text_secondary'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .margin({ top: 2 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(10)
            .borderRadius(10)
            .backgroundColor($r('app.color.hm_hover_bg'))
            .margin({ top: 6 })
            .onClick(() => {
              this.onOpenNote(item.sourcePath);
            })
          }, (item: BacklinkItem, index: number): string => `backlink_${index}`)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  tagsView() {
    Scroll() {
      Column() {
        if (this.tags.length === 0) {
          Text($r('app.string.empty_tags'))
            .fontSize(13)
            .fontColor($r('app.color.hm_text_secondary'))
        } else {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.tags, (tag: string, index: number) => {
              Text(`#${tag}`)
                .fontSize(13)
                .fontColor($r('app.color.hm_accent'))
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .borderRadius(10)
                .backgroundColor($r('app.color.hm_accent_weak'))
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
      .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  propertiesView() {
    Scroll() {
      Column() {
        if (this.properties.length === 0) {
          Text($r('app.string.empty_props'))
            .fontSize(13)
            .fontColor($r('app.color.hm_text_secondary'))
        } else {
          ForEach(this.properties, (property: MdProperty, index: number) => {
            Row() {
              Text(property.key)
                .fontSize(13)
                .fontColor($r('app.color.hm_text_secondary'))
                .width('38%')
              Text(this.propertyValue(property))
                .fontSize(13)
                .fontColor($r('app.color.hm_text_primary'))
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 6, bottom: 6 })
          }, (property: MdProperty, index: number): string => `prop_${index}`)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .height('100%')
  }

  private propertyValue(property: MdProperty): string {
    if (property.listValue.length > 0) {
      return property.listValue.join(', ');
    }
    return property.value;
  }
}
