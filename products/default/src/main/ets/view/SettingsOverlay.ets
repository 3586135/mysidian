/**
 * 应用设置浮层：正文字号、数据维护与关于信息。
 */
@ComponentV2
export struct SettingsOverlay {
  @Param fontSize: number = 16;
  @Event onFontSizeChange: (size: number) => void = (size: number): void => {};
  @Event onReindex: () => void = (): void => {};
  @Event onExport: () => void = (): void => {};
  @Event onClose: () => void = (): void => {};

  build() {
    Stack() {
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      .opacity(0.5)
      .onClick(() => {
        this.onClose();
      })

      Column() {
        Row() {
          Text($r('app.string.settings_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .layoutWeight(1)
          Button($r('app.string.dialog_cancel'))
            .type(ButtonType.Normal)
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 10 })

        Column() {
          Text($r('app.string.settings_font_size'))
            .fontSize(13)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .width('100%')
            .margin({ top: 8, bottom: 8 })
          Row() {
            this.sizeButton($r('app.string.settings_font_small'), 14)
            this.sizeButton($r('app.string.settings_font_medium'), 16)
            this.sizeButton($r('app.string.settings_font_large'), 18)
          }
          .width('100%')

          Button($r('app.string.settings_reindex'))
            .type(ButtonType.Normal)
            .width('100%')
            .margin({ top: 16, bottom: 8 })
            .onClick(() => {
              this.onReindex();
            })

          Button($r('app.string.action_export_vault'))
            .type(ButtonType.Normal)
            .width('100%')
            .margin({ top: 8, bottom: 8 })
            .onClick(() => {
              this.onExport();
            })

          Text($r('app.string.settings_about'))
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .width('100%')
            .margin({ top: 16 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, bottom: 20 })
      }
      .width('88%')
      .height('60%')
      .borderRadius(14)
      .backgroundColor($r('sys.color.ohos_id_color_background'))
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  sizeButton(label: ResourceStr, size: number) {
    Button(label)
      .type(ButtonType.Normal)
      .layoutWeight(1)
      .margin({ right: 8 })
      .backgroundColor(this.fontSize === size ?
        $r('sys.color.ohos_id_color_emphasize') : $r('sys.color.ohos_id_color_component_activated'))
      .onClick(() => {
        this.onFontSizeChange(size);
      })
  }
}
