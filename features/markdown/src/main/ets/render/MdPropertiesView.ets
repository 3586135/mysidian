import { MdFrontmatter, MdProperty, MdPropType } from '@ohos/domain';

/**
 * Frontmatter 属性块：阅读态正文顶部以卡片形式展示 YAML 属性。
 * tags/tag 属性渲染为可点击芯片（跳转标签检索），其余按键类型展示；
 * 嵌套 map 以原文等宽字体保留展示。
 */
@ComponentV2
export struct MdPropertiesView {
  @Param frontmatter: MdFrontmatter = new MdFrontmatter();
  @Param fontSize: number = 16;
  @Event onOpenTag: (tag: string) => void = (tag: string): void => {};

  build() {
    Column() {
      ForEach(this.frontmatter.properties, (property: MdProperty, index: number) => {
        this.propertyRow(property)
      }, (property: MdProperty, index: number): string => `prop_${index}_${property.key}_${property.value}`)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8, bottom: 10 })
    .borderRadius(14)
    .backgroundColor($r('app.color.md_card_bg'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  propertyRow(property: MdProperty) {
    Row() {
      Text(property.key)
        .fontSize(this.fontSize - 1)
        .fontColor($r('app.color.md_text_secondary'))
        .width(92)
        .copyOption(CopyOptions.LocalDevice)
      if (this.isTagProperty(property)) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.tagTokens(property), (token: string, index: number) => {
            this.tagChip(token)
          }, (token: string, index: number): string => `tag_${index}_${token}`)
        }
        .layoutWeight(1)
      } else if (property.type === MdPropType.LIST) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(property.listValue, (item: string, index: number) => {
            this.listChip(item)
          }, (item: string, index: number): string => `item_${index}_${item}`)
        }
        .layoutWeight(1)
      } else if (property.type === MdPropType.MAP) {
        Text(property.rawBlock)
          .fontSize(this.fontSize - 2)
          .fontColor($r('app.color.md_text_secondary'))
          .fontFamily('monospace')
          .layoutWeight(1)
          .maxLines(8)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .copyOption(CopyOptions.LocalDevice)
      } else if (property.value.length > 0) {
        Text(property.value)
          .fontSize(this.fontSize - 1)
          .fontColor($r('app.color.md_text_primary'))
          .layoutWeight(1)
          .copyOption(CopyOptions.LocalDevice)
      } else {
        Text('—')
          .fontSize(this.fontSize - 1)
          .fontColor($r('app.color.md_text_secondary'))
          .layoutWeight(1)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 5, bottom: 5 })
  }

  /** 标签芯片：去 # 展示，点击跳转标签检索。 */
  @Builder
  tagChip(token: string) {
    Text(this.stripHash(token))
      .fontSize(this.fontSize - 2)
      .fontColor($r('app.color.md_accent'))
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(9)
      .backgroundColor($r('app.color.md_accent_weak'))
      .margin({ right: 6, bottom: 4 })
      .onClick(() => {
        this.onOpenTag(this.stripHash(token));
      })
  }

  /** 普通列表值芯片。 */
  @Builder
  listChip(item: string) {
    Text(item.length > 0 ? item : '—')
      .fontSize(this.fontSize - 2)
      .fontColor($r('app.color.md_text_primary'))
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(9)
      .backgroundColor($r('app.color.md_chip_bg'))
      .margin({ right: 6, bottom: 4 })
  }

  private isTagProperty(property: MdProperty): boolean {
    const key: string = property.key.toLowerCase();
    return key === 'tags' || key === 'tag';
  }

  /** 标签属性取值：列表或标量统一拍平，并按空白/逗号/# 分词（与 FrontmatterParser 一致）。 */
  private tagTokens(property: MdProperty): string[] {
    const sources: string[] = property.type === MdPropType.LIST
      ? property.listValue
      : (property.value.length > 0 ? [property.value] : []);
    const tokens: string[] = [];
    for (const source of sources) {
      for (const part of source.split(/[\s,，#]+/)) {
        if (part.length > 0) {
          tokens.push(part);
        }
      }
    }
    return tokens;
  }

  private stripHash(token: string): string {
    const trimmed: string = token.trim();
    return trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  }
}
