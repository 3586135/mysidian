/**
 * 图片全屏预览浮层：支持双指捏合缩放（1x ~ 5x）、放大后单指拖拽平移、
 * 双击在 1x / 2.5x 之间切换，点遮罩或右上角关闭按钮退出。
 */
@ComponentV2
export struct ImagePreviewOverlay {
  @Param uri: string = '';
  @Event onClose: () => void = (): void => {};

  @Local scaleValue: number = 1;
  @Local offsetX: number = 0;
  @Local offsetY: number = 0;

  private pinchBaseScale: number = 1;
  private panBaseX: number = 0;
  private panBaseY: number = 0;

  private static readonly MIN_SCALE: number = 1;
  private static readonly MAX_SCALE: number = 5;
  private static readonly DOUBLE_TAP_SCALE: number = 2.5;

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.design_dim'))
      .backgroundBlurStyle(BlurStyle.Regular)
      .onClick(() => {
        this.onClose();
      })

      Column() {
        Image(this.uri)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .scale({ x: this.scaleValue, y: this.scaleValue })
          .translate({ x: this.offsetX, y: this.offsetY })
          .gesture(
            GestureGroup(GestureMode.Parallel,
              PinchGesture({ fingers: 2 })
                .onActionStart(() => {
                  this.pinchBaseScale = this.scaleValue;
                })
                .onActionUpdate((event: GestureEvent) => {
                  const next: number = Math.min(ImagePreviewOverlay.MAX_SCALE,
                    Math.max(ImagePreviewOverlay.MIN_SCALE, this.pinchBaseScale * event.scale));
                  this.scaleValue = next;
                  if (next <= ImagePreviewOverlay.MIN_SCALE) {
                    this.offsetX = 0;
                    this.offsetY = 0;
                  }
                }),
              PanGesture({ fingers: 1 })
                .onActionStart(() => {
                  this.panBaseX = this.offsetX;
                  this.panBaseY = this.offsetY;
                })
                .onActionUpdate((event: GestureEvent) => {
                  if (this.scaleValue <= ImagePreviewOverlay.MIN_SCALE) {
                    return;
                  }
                  this.offsetX = this.panBaseX + event.offsetX;
                  this.offsetY = this.panBaseY + event.offsetY;
                }),
              TapGesture({ count: 2 })
                .onAction(() => {
                  this.getUIContext().animateTo({ duration: 200, curve: Curve.Friction }, () => {
                    if (this.scaleValue > ImagePreviewOverlay.MIN_SCALE) {
                      this.scaleValue = ImagePreviewOverlay.MIN_SCALE;
                      this.offsetX = 0;
                      this.offsetY = 0;
                    } else {
                      this.scaleValue = ImagePreviewOverlay.DOUBLE_TAP_SCALE;
                    }
                  });
                })
            )
          )
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)

      Row() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([$r('app.color.design_text_primary')])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.design_surface_solid'))
      .border({ width: 1, color: $r('app.color.design_stroke') })
      .margin({ top: 48, right: 20 })
      .accessibilityText($r('app.string.find_close'))
      .onClick(() => {
        this.onClose();
      })
    }
    .width('100%')
    .height('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.Friction }))
  }
}
