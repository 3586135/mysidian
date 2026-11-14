import { VaultViewModel } from '../../viewmodel/VaultViewModel';

/** 模板显示名：去掉路径前缀与 .md 扩展名。 */
function templateDisplayName(path: string): string {
  const index: number = path.lastIndexOf('/');
  const name: string = index >= 0 ? path.substring(index + 1) : path;
  return name.endsWith('.md') ? name.substring(0, name.length - 3) : name;
}

/**
 * Material 3 模板选择浮层：套用模板创建笔记（以时间戳命名）。
 */
@ComponentV2
export struct TemplateSheet {
  @Param vm: VaultViewModel = new VaultViewModel();
  @Event onClose: () => void = (): void => {};
  @Event onNoteMutated: () => void = (): void => {};

  /** 可用模板列表（沙箱相对路径）。 */
  @Local templateList: string[] = [];

  aboutToAppear(): void {
    this.vm.listTemplates().then((list: string[]): void => {
      this.templateList = list;
    });
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
        Text($r('app.string.template_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_text_primary'))
          .width('100%')
          .margin({ bottom: 10 })

        if (this.templateList.length === 0) {
          Text($r('app.string.template_empty'))
            .fontSize(13)
            .fontColor($r('app.color.design_text_secondary'))
        } else {
          Scroll() {
            Column() {
              ForEach(this.templateList, (item: string, index: number) => {
                this.templateRow(item, index)
              }, (item: string, index: number): string => `tpl_${item}`)
            }
            .width('100%')
          }
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .constraintSize({ maxHeight: 320 })
        }

        Row() {
          Button($r('app.string.dialog_cancel'))
            .type(ButtonType.Capsule)
            .height(40)
            .fontSize(16)
            .backgroundColor($r('app.color.design_elevated'))
            .fontColor($r('app.color.design_text_primary'))
            .layoutWeight(1)
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('88%')
      .constraintSize({ maxWidth: 460 })
      .padding(20)
      .borderRadius(28)
      .backgroundColor($r('app.color.design_surface_solid'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .shadow({ radius: 32, color: $r('app.color.design_shadow'), offsetY: 10 })
      .transition(TransitionEffect.scale({ x: 0.92, y: 0.92 })
        .combine(TransitionEffect.opacity(0))
        .animation({ duration: 220, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
  }

  /** 模板条目。 */
  @Builder
  templateRow(item: string, index: number) {
    Row() {
      SymbolGlyph($r('sys.symbol.doc_plaintext'))
        .fontSize(15)
        .fontColor([$r('app.color.design_text_secondary')])
        .width(20)
      Text(templateDisplayName(item))
        .fontSize(15)
        .fontColor($r('app.color.design_text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(42)
    .padding({ left: 6, right: 6 })
    .borderRadius(12)
    .onClick(() => {
      this.applyTemplate(item);
    })
  }

  /** 套用模板创建笔记（时间戳命名）。 */
  private applyTemplate(path: string): void {
    this.onClose();
    const now: Date = new Date();
    const pad = (v: number): string => v < 10 ? `0${v}` : `${v}`;
    const stamp: string = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}` +
      `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
    this.vm.createNoteWithTemplate(path, `未命名-${stamp}`).then((): void => {
      this.toast($r('app.string.msg_template_applied'));
      this.onNoteMutated();
    });
  }

  /** 轻提示（使用 UIContext 的 PromptAction，避免全局 promptAction 的弃用告警）。 */
  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }
}
