import { GraphData, GraphEdge, GraphNode } from '@ohos/domain';

/**
 * 关系图谱力导向布局（原生实现）。
 *
 * 采用经典的「斥力 + 弹簧 + 向心力」模型：
 * - 每对节点之间施加平方反比斥力
 * - 每条连线施加弹簧力把两端拉近
 * - 每个节点受到指向中心的引力，避免图形散开
 */
export class GraphLayout {
  private static readonly ITERATIONS: number = 260;
  private static readonly REPULSION: number = 5200;
  private static readonly SPRING: number = 0.035;
  private static readonly CENTER_PULL: number = 0.012;
  private static readonly DAMPING: number = 0.86;
  private static readonly MIN_DISTANCE: number = 46;

  /**
   * 计算布局坐标（原地写入 graph.nodes 的 x / y）。
   *
   * @param graph 图谱数据
   * @param width 画布宽（vp）
   * @param height 画布高（vp）
   */
  public static compute(graph: GraphData, width: number, height: number): void {
    const count: number = graph.nodes.length;
    if (count === 0) {
      return;
    }
    const centerX: number = width / 2;
    const centerY: number = height / 2;
    // 初始位置：按索引均匀分布在圆周上。
    const radius: number = Math.min(width, height) * 0.32;
    for (let index = 0; index < count; index++) {
      const node: GraphNode = graph.nodes[index];
      const angle: number = (Math.PI * 2 * index) / count;
      node.x = centerX + radius * Math.cos(angle);
      node.y = centerY + radius * Math.sin(angle);
      node.radius = node.root ? 22 : 14;
    }

    const vx: number[] = new Array<number>(count).fill(0);
    const vy: number[] = new Array<number>(count).fill(0);

    for (let step = 0; step < GraphLayout.ITERATIONS; step++) {
      // 斥力
      for (let i = 0; i < count; i++) {
        for (let j = i + 1; j < count; j++) {
          const a: GraphNode = graph.nodes[i];
          const b: GraphNode = graph.nodes[j];
          let dx: number = a.x - b.x;
          let dy: number = a.y - b.y;
          let distanceSquared: number = dx * dx + dy * dy;
          if (distanceSquared < 1) {
            dx = (i - j) * 0.5 + 0.1;
            dy = 0.1;
            distanceSquared = dx * dx + dy * dy;
          }
          const distance: number = Math.sqrt(distanceSquared);
          const force: number = GraphLayout.REPULSION / distanceSquared;
          const fx: number = (dx / distance) * force;
          const fy: number = (dy / distance) * force;
          vx[i] += fx;
          vy[i] += fy;
          vx[j] -= fx;
          vy[j] -= fy;
        }
      }
      // 弹簧
      for (const edge of graph.edges) {
        const fromIndex: number = GraphLayout.indexOf(graph, edge.from);
        const toIndex: number = GraphLayout.indexOf(graph, edge.to);
        if (fromIndex < 0 || toIndex < 0) {
          continue;
        }
        const a: GraphNode = graph.nodes[fromIndex];
        const b: GraphNode = graph.nodes[toIndex];
        const dx: number = b.x - a.x;
        const dy: number = b.y - a.y;
        const distance: number = Math.max(1, Math.sqrt(dx * dx + dy * dy));
        const force: number = (distance - 96) * GraphLayout.SPRING;
        const fx: number = (dx / distance) * force;
        const fy: number = (dy / distance) * force;
        vx[fromIndex] += fx;
        vy[fromIndex] += fy;
        vx[toIndex] -= fx;
        vy[toIndex] -= fy;
      }
      // 向心力 + 阻尼 + 位置更新
      for (let index = 0; index < count; index++) {
        const node: GraphNode = graph.nodes[index];
        vx[index] += (centerX - node.x) * GraphLayout.CENTER_PULL;
        vy[index] += (centerY - node.y) * GraphLayout.CENTER_PULL;
        vx[index] *= GraphLayout.DAMPING;
        vy[index] *= GraphLayout.DAMPING;
        node.x += vx[index];
        node.y += vy[index];
      }
    }

    // 归一化到画布内
    for (const node of graph.nodes) {
      node.x = Math.max(node.radius + 2, Math.min(width - node.radius - 2, node.x));
      node.y = Math.max(node.radius + 2, Math.min(height - node.radius - 2, node.y));
    }
  }

  /** 查找节点下标。 */
  private static indexOf(graph: GraphData, path: string): number {
    for (let index = 0; index < graph.nodes.length; index++) {
      if (graph.nodes[index].path === path) {
        return index;
      }
    }
    return -1;
  }
}
