/**
 * 空状态占位组件（鸿蒙风格：图标 + 标题 + 描述）。
 */
@ComponentV2
export struct EmptyState {
  @Param title: ResourceStr = '';
  @Param description: ResourceStr = '';
  @Param icon: Resource | undefined = undefined;
  @Param iconColor: ResourceColor = $r('sys.color.ohos_id_color_text_secondary');

  build() {
    Column() {
      if (this.icon !== undefined) {
        SymbolGlyph(this.icon)
          .fontSize(56)
          .fontColor([this.iconColor])
          .margin({ bottom: 16 })
      }
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
      Text(this.description)
        .fontSize(14)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }
}
