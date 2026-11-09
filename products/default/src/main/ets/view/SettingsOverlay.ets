/**
 * 应用设置浮层：鸿蒙风格设置卡片，系统 Slider 调节正文字号。
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
      .backgroundColor($r('app.color.hm_mask'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .onClick(() => {
        this.onClose();
      })

      Column() {
        Row() {
          Text($r('app.string.settings_title'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.hm_text_primary'))
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([$r('app.color.hm_text_secondary')])
            .padding(6)
            .borderRadius(14)
            .backgroundColor($r('app.color.hm_hover_bg'))
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 10 })

        Scroll() {
          Column() {
            Text($r('app.string.settings_appearance'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.hm_text_secondary'))
              .width('100%')
              .margin({ top: 4, bottom: 8 })
            Row() {
              Text($r('app.string.settings_font_size'))
                .fontSize(15)
                .fontColor($r('app.color.hm_text_primary'))
                .layoutWeight(1)
              Text(`${this.fontSize}`)
                .fontSize(14)
                .fontColor($r('app.color.hm_accent'))
            }
            .width('100%')
            Slider({
              value: this.fontSize,
              min: 14,
              max: 22,
              step: 1,
              style: SliderStyle.OutSet
            })
              .width('100%')
              .blockColor($r('app.color.hm_accent'))
              .selectedColor($r('app.color.hm_accent'))
              .trackColor($r('app.color.hm_divider'))
              .showTips(true, this.fontSize.toString())
              .onChange((value: number, mode: SliderChangeMode) => {
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  this.onFontSizeChange(Math.round(value));
                }
              })

            Text($r('app.string.settings_maintenance'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.hm_text_secondary'))
              .width('100%')
              .margin({ top: 16, bottom: 8 })

            this.actionRow($r('sys.symbol.arrow_clockwise'), $r('app.string.settings_reindex'), (): void => {
              this.onReindex();
            })
            this.actionRow($r('sys.symbol.doc_zipper'), $r('app.string.action_export_vault'), (): void => {
              this.onExport();
            })

            Text($r('app.string.settings_about'))
              .fontSize(12)
              .fontColor($r('app.color.hm_text_secondary'))
              .width('100%')
              .margin({ top: 20 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, bottom: 20 })
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('88%')
      .height('66%')
      .borderRadius(24)
      .backgroundColor($r('app.color.hm_card_bg'))
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  actionRow(icon: Resource, label: ResourceStr, action: () => void) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(17)
        .fontColor([$r('app.color.hm_accent')])
        .width(24)
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.hm_text_primary'))
        .layoutWeight(1)
        .margin({ left: 12 })
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13)
        .fontColor([$r('app.color.hm_text_secondary')])
    }
    .width('100%')
    .height(44)
    .padding({ left: 10, right: 10 })
    .borderRadius(10)
    .backgroundColor($r('app.color.hm_hover_bg'))
    .margin({ top: 4, bottom: 4 })
    .onClick(() => {
      action();
    })
  }
}
