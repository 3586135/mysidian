import { VaultViewModel } from '../../viewmodel/VaultViewModel';

/**
 * Material 3 快速闪念浮层：一句话速记，保存后追加到当天日记。
 */
@ComponentV2
export struct QuickNoteSheet {
  @Param vm: VaultViewModel = new VaultViewModel();
  @Event onClose: () => void = (): void => {};
  @Event onNoteMutated: () => void = (): void => {};

  @Local noteText: string = '';

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
        Text($r('app.string.share_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.design_text_primary'))
          .width('100%')
          .margin({ bottom: 12 })

        TextArea({
          placeholder: $r('app.string.share_hint'),
          text: this.noteText
        })
          .width('100%')
          .height(120)
          .fontSize(15)
          .padding(14)
          .borderRadius(16)
          .backgroundColor($r('app.color.design_elevated'))
          .placeholderColor($r('app.color.design_text_secondary'))
          .fontColor($r('app.color.design_text_primary'))
          .caretColor($r('app.color.design_accent'))
          .onChange((value: string): void => {
            this.noteText = value;
          })

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
          Button($r('app.string.share_save'))
            .type(ButtonType.Capsule)
            .height(40)
            .fontSize(16)
            .backgroundColor($r('app.color.design_accent'))
            .fontColor($r('app.color.design_on_accent'))
            .layoutWeight(1)
            .margin({ left: 12 })
            .onClick(() => {
              this.saveQuickNote();
            })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('88%')
      .constraintSize({ maxWidth: 420 })
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

  /** 保存快速闪念到当天日记。 */
  private saveQuickNote(): void {
    const text: string = this.noteText.trim();
    this.onClose();
    if (text.length === 0) {
      return;
    }
    this.vm.appendQuickNote(text).then((ok: boolean): void => {
      if (ok) {
        this.toast($r('app.string.msg_share_saved'));
        this.onNoteMutated();
      }
    });
  }

  /** 轻提示（使用 UIContext 的 PromptAction，避免全局 promptAction 的弃用告警）。 */
  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }
}
