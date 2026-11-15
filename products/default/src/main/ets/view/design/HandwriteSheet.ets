import { image } from '@kit.ImageKit';

/**
 * Material 3 手写速记浮层：ArkUI Canvas 采集笔迹（手指 / 手写笔），
 * 导出为 PNG 附件（ImageData 重建 PixelMap 后打包），经 onSave 上抛宿主插入笔记。
 */
@ComponentV2
export struct HandwriteSheet {
  @Event onSave: (data: ArrayBuffer) => void = (data: ArrayBuffer): void => {};
  @Event onClose: () => void = (): void => {};

  @Local saving: boolean = false;
  private strokeCount: number = 0;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private drawing: boolean = false;
  private lastX: number = 0;
  private lastY: number = 0;
  /** 画布实际像素尺寸：onReady 时从渲染上下文读取。 */
  private canvasWidth: number = 320;
  private canvasHeight: number = 420;

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
        Row() {
          Text($r('app.string.handwrite_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_text_primary'))
            .layoutWeight(1)
          Text($r('app.string.handwrite_clear'))
            .fontSize(14)
            .fontColor($r('app.color.design_text_secondary'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor($r('app.color.design_elevated'))
            .onClick(() => {
              this.clearCanvas();
            })
          Text(this.saving ? $r('app.string.handwrite_saving') : $r('app.string.handwrite_save'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.design_accent'))
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor($r('app.color.design_accent_weak'))
            .margin({ left: 10 })
            .onClick(() => {
              this.exportImage();
            })
          Stack() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(16)
              .fontColor([$r('app.color.design_text_secondary')])
          }
          .width(32)
          .height(32)
          .borderRadius(16)
          .backgroundColor($r('app.color.design_elevated'))
          .alignContent(Alignment.Center)
          .margin({ left: 8 })
          .onClick(() => {
            this.onClose();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 12 })

        Canvas(this.context)
          .width('100%')
          .layoutWeight(1)
          .backgroundColor(Color.White)
          .borderRadius(16)
          .border({ width: 1, color: $r('app.color.design_stroke') })
          .onReady((): void => {
            // 记录画布实际尺寸：清空与导出都必须覆盖整块画布。
            this.canvasWidth = this.context.width;
            this.canvasHeight = this.context.height;
            this.drawBackground();
          })
          .onTouch((event: TouchEvent): void => {
            this.handleTouch(event);
          })
      }
      .width('90%')
      .constraintSize({ maxWidth: 520 })
      .height('62%')
      .padding(16)
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

  /** 触摸绘制笔迹。 */
  private handleTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      const point = event.touches.length > 0 ? event.touches[0] : null;
      if (point === null) {
        return;
      }
      this.drawing = true;
      this.lastX = point.x;
      this.lastY = point.y;
      this.strokeCount++;
      this.context.beginPath();
      this.context.moveTo(this.lastX, this.lastY);
      return;
    }
    if (event.type === TouchType.Move && this.drawing) {
      const point = event.touches.length > 0 ? event.touches[0] : null;
      if (point === null) {
        return;
      }
      this.context.lineTo(point.x, point.y);
      this.context.strokeStyle = '#1b1b1b';
      this.context.lineWidth = 3;
      this.context.lineCap = 'round';
      this.context.stroke();
      this.lastX = point.x;
      this.lastY = point.y;
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.drawing = false;
    }
  }

  /** 清空画布：按实际尺寸清除并重绘网格背景。 */
  private clearCanvas(): void {
    this.context.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
    this.drawBackground();
    this.strokeCount = 0;
  }

  /** 绘制浅色网格背景（白板观感）。 */
  private drawBackground(): void {
    this.context.fillStyle = '#ffffff';
    this.context.fillRect(0, 0, this.canvasWidth, this.canvasHeight);
    this.context.strokeStyle = '#e6e6e6';
    this.context.lineWidth = 1;
    for (let x = 0; x < this.canvasWidth; x += 32) {
      this.context.beginPath();
      this.context.moveTo(x, 0);
      this.context.lineTo(x, this.canvasHeight);
      this.context.stroke();
    }
    for (let y = 0; y < this.canvasHeight; y += 32) {
      this.context.beginPath();
      this.context.moveTo(0, y);
      this.context.lineTo(this.canvasWidth, y);
      this.context.stroke();
    }
  }

  /** 导出当前画布为 PNG 数据。 */
  private exportImage(): void {
    if (this.saving || this.strokeCount === 0) {
      return;
    }
    this.saving = true;
    try {
      const width: number = Math.floor(this.canvasWidth);
      const height: number = Math.floor(this.canvasHeight);
      const data: ImageData = this.context.getImageData(0, 0, width, height);
      const buffer: ArrayBuffer = data.data.buffer.slice(data.data.byteOffset,
        data.data.byteOffset + data.data.byteLength);
      image.createPixelMap(buffer, {
        size: { width: width, height: height },
        srcPixelFormat: image.PixelMapFormat.RGBA_8888
      }).then((pixelMap: image.PixelMap): Promise<ArrayBuffer> => {
        const packer: image.ImagePacker = image.createImagePacker();
        return packer.packing(pixelMap, { format: 'image/png', quality: 100 });
      }).then((packed: ArrayBuffer): void => {
        this.saving = false;
        this.onSave(packed);
      }).catch(() => {
        this.saving = false;
      });
    } catch (error) {
      this.saving = false;
    }
  }
}
