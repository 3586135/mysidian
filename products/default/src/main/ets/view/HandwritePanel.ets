import { image } from '@kit.ImageKit';

/**
 * 手写速记面板：ArkUI Canvas 采集笔迹，导出为 PNG 附件。
 *
 * 触摸事件直接驱动 Canvas 绘制（支持手指与手写笔），
 * 导出时用 ImageData 重建 PixelMap 并打包成 PNG。
 */
@ComponentV2
export struct HandwritePanel {
  @Event onSave: (data: ArrayBuffer) => void = (data: ArrayBuffer): void => {};
  @Event onClose: () => void = (): void => {};
  @Local strokeCount: number = 0;
  @Local saving: boolean = false;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private drawing: boolean = false;
  private lastX: number = 0;
  private lastY: number = 0;
  /** 画布实际像素尺寸：onReady 时从渲染上下文读取，替换固定的 320x420。 */
  private canvasWidth: number = 320;
  private canvasHeight: number = 420;

  build() {
    Column() {
      Row() {
        Text($r('app.string.handwrite_clear'))
          .fontSize(14)
          .fontColor($r('app.color.hm_text_secondary'))
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => {
            this.clearCanvas();
          })
        Blank()
        Text(this.saving ? $r('app.string.handwrite_saving') : $r('app.string.handwrite_save'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hm_accent'))
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => {
            this.exportImage();
          })
        Text($r('app.string.dialog_cancel'))
          .fontSize(14)
          .fontColor($r('app.color.hm_text_secondary'))
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .margin({ left: 4 })
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 12, right: 12, top: 8 })

      Canvas(this.context)
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(Color.White)
        .borderRadius(12)
        .onReady((): void => {
          // 记录画布实际尺寸：清空与导出都必须覆盖整块画布，而非固定的 320x420。
          this.canvasWidth = this.context.width;
          this.canvasHeight = this.context.height;
          this.drawBackground();
        })
        .onTouch((event: TouchEvent): void => {
          this.handleTouch(event);
        })

      Text($r('app.string.handwrite_title'))
        .fontSize(12)
        .fontColor($r('app.color.hm_text_secondary'))
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, bottom: 12 })
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
