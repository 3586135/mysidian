@Entry
@ComponentV2
struct Index {
  build() {
    Column() {
      Text('mysidian')
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
