import { FlowEdge, FlowGraph, FlowNode, MermaidFlow } from './MermaidFlow';

/**
 * Mermaid 流程图原生渲染器。
 *
 * 连线与节点边框用 ArkUI Canvas 绘制（中性色，深浅色模式下都可读），
 * 节点文本用 ArkUI Text 叠加渲染，保证字体与主题跟随系统。
 */
@ComponentV2
export struct MdMermaidView {
  @Param source: string = '';
  /** 根节点标识（通常为当前笔记名），会高亮显示。 */
  @Param rootNodeId: string = '';
  @Local graph: FlowGraph = new FlowGraph();
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  aboutToAppear(): void {
    // 解析异常时降级为展示源码，避免因非法图表导致应用崩溃。
    try {
      this.graph = MermaidFlow.parse(this.source);
    } catch (error) {
      this.graph = new FlowGraph();
    }
    for (const node of this.graph.nodes) {
      node.root = node.id === this.rootNodeId;
    }
  }

  build() {
    Column() {
      if (this.graph.valid) {
        Stack() {
          Canvas(this.context)
            .width(this.graph.graphWidth)
            .height(this.graph.graphHeight)
            .onReady((): void => {
              this.drawGraph();
            })
          ForEach(this.graph.nodes, (node: FlowNode) => {
            Text(node.label)
              .fontSize(12)
              .fontWeight(node.root ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(node.root ? $r('app.color.hm_accent') : $r('app.color.hm_text_primary'))
              .textAlign(TextAlign.Center)
              .width(node.nodeWidth - 14)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .position({ x: node.x + 7, y: node.y + (node.nodeHeight - 32) / 2 })
          }, (node: FlowNode): string => `mn_${node.id}`)
        }
        .width(this.graph.graphWidth)
        .height(this.graph.graphHeight)
      } else {
        Text(this.source)
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor($r('app.color.hm_text_secondary'))
          .width('100%')
          .padding(10)
          .borderRadius(8)
          .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 6, bottom: 6 })
  }

  /** 绘制连线与节点边框。 */
  private drawGraph(): void {
    const ctx: CanvasRenderingContext2D = this.context;
    ctx.clearRect(0, 0, this.graph.graphWidth, this.graph.graphHeight);
    ctx.lineWidth = 1.6;
    ctx.strokeStyle = 'rgba(128,128,128,0.65)';
    ctx.fillStyle = 'rgba(128,128,128,0.12)';

    for (const edge of this.graph.edges) {
      const from: FlowNode | undefined = this.findNode(edge.from);
      const to: FlowNode | undefined = this.findNode(edge.to);
      if (from === undefined || to === undefined) {
        continue;
      }
      this.drawEdge(ctx, from, to);
    }

    for (const node of this.graph.nodes) {
      ctx.beginPath();
      ctx.roundRect(node.x, node.y, node.nodeWidth, node.nodeHeight, 10);
      ctx.fill();
      ctx.stroke();
    }
  }

  /** 绘制一条连线（横向或纵向）。 */
  private drawEdge(ctx: CanvasRenderingContext2D, from: FlowNode, to: FlowNode): void {
    let x1: number = 0;
    let y1: number = 0;
    let x2: number = 0;
    let y2: number = 0;
    if (this.graph.horizontal) {
      x1 = from.x + from.nodeWidth;
      y1 = from.y + from.nodeHeight / 2;
      x2 = to.x;
      y2 = to.y + to.nodeHeight / 2;
    } else {
      x1 = from.x + from.nodeWidth / 2;
      y1 = from.y + from.nodeHeight;
      x2 = to.x + to.nodeWidth / 2;
      y2 = to.y;
    }
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.lineTo(x2, y2);
    ctx.stroke();

    // 箭头
    const angle: number = Math.atan2(y2 - y1, x2 - x1);
    const size: number = 8;
    ctx.beginPath();
    ctx.moveTo(x2, y2);
    ctx.lineTo(x2 - size * Math.cos(angle - Math.PI / 6), y2 - size * Math.sin(angle - Math.PI / 6));
    ctx.lineTo(x2 - size * Math.cos(angle + Math.PI / 6), y2 - size * Math.sin(angle + Math.PI / 6));
    ctx.closePath();
    ctx.fill();
  }

  /** 按标识查找节点。 */
  private findNode(id: string): FlowNode | undefined {
    for (const node of this.graph.nodes) {
      if (node.id === id) {
        return node;
      }
    }
    return undefined;
  }
}
