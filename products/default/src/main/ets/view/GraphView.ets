import { GraphData, GraphNode } from '@ohos/domain';
import { GraphLayout } from '../viewmodel/GraphLayout';

/**
 * 局部关系图谱：ArkUI Canvas 绘制节点与连线，力导向布局。
 *
 * 连线与节点圆点用 Canvas 绘制（中性色，深浅色模式都可读），
 * 节点标题用 ArkUI Text 叠加渲染，保证字体与主题跟随系统。
 */
@ComponentV2
export struct GraphView {
  @Param graph: GraphData = new GraphData();
  @Param canvasWidth: number = 280;
  @Param canvasHeight: number = 240;
  @Event onOpenNode: (path: string) => void = (path: string): void => {};
  @Local ready: boolean = false;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  aboutToAppear(): void {
    this.relayout();
  }

  @Monitor('graph')
  onGraphChange(): void {
    this.relayout();
  }

  build() {
    Stack() {
      Canvas(this.context)
        .width(this.canvasWidth)
        .height(this.canvasHeight)
        .onReady((): void => {
          this.draw();
        })
        .onClick((event: ClickEvent): void => {
          this.handleCanvasClick(event);
        })
      ForEach(this.graph.nodes, (node: GraphNode) => {
        Text(node.title)
          .fontSize(10)
          .fontWeight(node.root ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(node.root ? $r('app.color.hm_accent') : $r('app.color.hm_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(72)
          .textAlign(TextAlign.Center)
          .position({ x: node.x - 36, y: node.y + node.radius + 2 })
          .onClick(() => {
            this.onOpenNode(node.path);
          })
      }, (node: GraphNode): string => `gn_${node.path}`)
    }
    .width(this.canvasWidth)
    .height(this.canvasHeight)
  }

  /** 重新计算布局。 */
  private relayout(): void {
    GraphLayout.compute(this.graph, this.canvasWidth, this.canvasHeight);
    this.ready = true;
    this.draw();
  }

  /** 绘制连线与节点。 */
  private draw(): void {
    const ctx: CanvasRenderingContext2D = this.context;
    ctx.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
    ctx.lineWidth = 1.2;
    ctx.strokeStyle = 'rgba(128,128,128,0.45)';
    for (const edge of this.graph.edges) {
      const from: GraphNode | undefined = this.findNode(edge.from);
      const to: GraphNode | undefined = this.findNode(edge.to);
      if (from === undefined || to === undefined) {
        continue;
      }
      ctx.beginPath();
      ctx.moveTo(from.x, from.y);
      ctx.lineTo(to.x, to.y);
      ctx.stroke();
    }
    for (const node of this.graph.nodes) {
      ctx.beginPath();
      ctx.arc(node.x, node.y, node.radius, 0, Math.PI * 2);
      if (node.root) {
        ctx.fillStyle = 'rgba(0,150,255,0.85)';
      } else {
        ctx.fillStyle = 'rgba(128,128,128,0.45)';
      }
      ctx.fill();
      ctx.strokeStyle = 'rgba(128,128,128,0.7)';
      ctx.stroke();
    }
  }

  /** 点击画布：命中最近的节点则打开。 */
  private handleCanvasClick(event: ClickEvent): void {
    const x: number = event.x;
    const y: number = event.y;
    let best: GraphNode | null = null;
    let bestDistance: number = 1e9;
    for (const node of this.graph.nodes) {
      const dx: number = node.x - x;
      const dy: number = node.y - y;
      const distance: number = dx * dx + dy * dy;
      if (distance < bestDistance && distance <= 900) {
        bestDistance = distance;
        best = node;
      }
    }
    if (best !== null) {
      this.onOpenNode(best.path);
    }
  }

  /** 按路径查找节点。 */
  private findNode(path: string): GraphNode | undefined {
    for (const node of this.graph.nodes) {
      if (node.path === path) {
        return node;
      }
    }
    return undefined;
  }
}
