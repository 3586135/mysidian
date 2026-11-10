/**
 * 桌面服务卡片页面。
 *
 * 说明：当前 SDK 的 ArkUI 卡片体系在卡片页中禁用了 @StorageLink/@StorageProp
 * （需配合 FormComponent 宿主，而本 SDK 未提供），因此卡片页采用静态提示视图；
 * 真实数据（今日日记摘要 + 未完成任务）由 FormExtensionAbility 通过
 * formProvider.updateForm 发布，由系统在卡片数据通道中承载。
 */
@Entry
@Component
struct FormCard {
  build() {
    Column() {
      Row() {
        Text('MySidian')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1b1b1b')
          .layoutWeight(1)
        Text('速记')
          .fontSize(9)
          .fontColor('#8a8a8a')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('今日日记与待办任务已同步到桌面卡片')
        .fontSize(11)
        .fontColor('#4a4a4a')
        .maxLines(2)
        .width('100%')
        .margin({ top: 6 })

      Text('打开应用可查看完整内容')
        .fontSize(10)
        .fontColor('#8a8a8a')
        .width('100%')
        .margin({ top: 4 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(10)
    .backgroundColor('#f5f5f5')
  }
}
