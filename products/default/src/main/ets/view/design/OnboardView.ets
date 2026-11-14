/**
 * Material 3 无仓库引导视图：欢迎区（偏上）+ 三入口操作卡片
 * （新建仓库 / 导入仓库 / WebDAV 同步）。
 */
@ComponentV2
export struct OnboardView {
  /** WebDAV 是否已配置（影响同步入口描述文案）。 */
  @Param syncConfigured: boolean = false;
  @Event onRequestExit: () => void = (): void => {};
  @Event onCreateVault: () => void = (): void => {};
  @Event onImportVault: () => void = (): void => {};
  @Event onOpenSync: () => void = (): void => {};

  build() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([$r('app.color.design_text_primary')])
          .width(40)
          .height(40)
          .onClick(() => {
            this.onRequestExit();
          })
        Text($r('app.string.app_title'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.design_text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      Blank()
        .layoutWeight(1)

      Column() {
        Column() {
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(48)
            .fontColor([$r('app.color.design_accent')])
        }
        .width(96)
        .height(96)
        .borderRadius(28)
        .backgroundColor($r('app.color.design_elevated'))
        .justifyContent(FlexAlign.Center)

        Text($r('app.string.welcome_title'))
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.design_text_primary'))
          .margin({ top: 24 })
        Text($r('app.string.welcome_desc'))
          .fontSize(14)
          .fontColor($r('app.color.design_text_secondary'))
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)

      Blank()
        .layoutWeight(1.4)

      Column() {
        this.onboardRow($r('sys.symbol.square_and_pencil'), $r('app.string.onboard_create_title'),
          $r('app.string.onboard_create_desc'), 0)
        Divider()
          .color($r('app.color.design_divider'))
        this.onboardRow($r('sys.symbol.folder'), $r('app.string.onboard_import_title'),
          $r('app.string.onboard_import_desc'), 1)
        Divider()
          .color($r('app.color.design_divider'))
        this.onboardRow($r('sys.symbol.arrow_clockwise'), $r('app.string.onboard_sync_title'),
          this.syncConfigured ? $r('app.string.onboard_sync_done')
            : $r('app.string.onboard_sync_desc'), 2)
      }
      .width('100%')
      .constraintSize({ maxWidth: 420 })
      .padding(6)
      .borderRadius(20)
      .backgroundColor($r('app.color.design_surface_solid'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .shadow({ radius: 24, color: $r('app.color.design_shadow'), offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .backgroundColor($r('app.color.design_bg'))
  }

  /** 引导操作行。action：0 新建仓库 / 1 导入仓库 / 2 WebDAV 同步。 */
  @Builder
  onboardRow(icon: Resource, title: ResourceStr, desc: ResourceStr, action: number) {
    Row() {
      Column() {
        SymbolGlyph(icon)
          .fontSize(22)
          .fontColor([$r('app.color.design_accent')])
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor($r('app.color.design_elevated'))
      .justifyContent(FlexAlign.Center)

      Column() {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_text_primary'))
          .maxLines(1)
        Text(desc)
          .fontSize(12)
          .fontColor($r('app.color.design_text_secondary'))
          .maxLines(2)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12, right: 8 })

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('app.color.design_text_secondary')])
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 10, right: 14 })
    .borderRadius(16)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (action === 0) {
        this.onCreateVault();
      } else if (action === 1) {
        this.onImportVault();
      } else {
        this.onOpenSync();
      }
    })
  }
}
