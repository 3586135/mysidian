import { GraphData, GraphNode } from '@ohos/domain';

/** 一次布局的结构统计（供图谱页展示洞见）。 */
export class GraphLayoutStats {
  /** 链接群簇数（≥2 篇互链的连通分量）。 */
  clusters: number = 0;
  /** 未链接笔记数（孤立节点）。 */
  orphans: number = 0;
  /** 最高连接度。 */
  maxDegree: number = 0;
  /** 最活跃笔记标题。 */
  hubTitle: string = '';

  /** 超宽标签截断（二分搜索最大可容纳字符数，追加省略号）。 */
  public static clipLabel(ctx: CanvasRenderingContext2D, text: string, maxWidth: number): string {
    if (text.length === 0) {
      return text;
    }
    if (ctx.measureText(text).width <= maxWidth) {
      return text;
    }
    let lo: number = 1;
    let hi: number = text.length - 1;
    while (lo < hi) {
      const mid: number = Math.floor((lo + hi + 1) / 2);
      if (ctx.measureText(text.substring(0, mid)).width + 10 <= maxWidth) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return `${text.substring(0, lo)}…`;
  }
}

/**
 * 关系图谱布局（「星图」式分簇布局）。
 *
 * 性能策略（对齐 Obsidian 的思路：布局计算必须远小于一帧，且绝不阻塞 UI）：
 * - 真实笔记库高度稀疏：多数笔记没有双向链接，少量笔记互链成小簇。
 *   先做连通分量分解，只对 ≥2 节点的簇跑力导向模拟；
 *   孤立笔记不参与模拟，收纳到底部「未链接」网格区。
 *   复杂度从 O(n²·迭代) 骤降为 Σ O(kᵢ²)，720 节点库实际只需模拟几十个节点。
 * - 大簇（>GRID_THRESHOLD 节点）斥力用空间网格近似（只算 3×3 邻近格），
 *   避免 O(k²) 全对计算（等价于 Barnes-Hut 的网格版简化）。
 * - 簇内边端点用局部下标数组，避免迭代内字符串查找。
 *
 * 结构策略（用户真正需要的图谱：结构可读，而非物理玩具）：
 * - 每个连通分量是一个「知识星座」，簇间货架式装箱，绝不重叠。
 * - 枢纽节点（连接度高）半径更大，随缩放分级披露标签。
 * - 孤立笔记收纳为底部网格区，内容缺口一目了然。
 */
export class GraphLayout {
  private static readonly REPULSION: number = 3400;
  private static readonly SPRING: number = 0.05;
  private static readonly DAMPING: number = 0.85;
  private static readonly GRAVITY: number = 0.012;
  /** 簇内节点数超过该值后，斥力改用空间网格近似。 */
  private static readonly GRID_THRESHOLD: number = 150;
  /** 网格近似斥力的格子尺寸（vp）与截断半径系数。 */
  private static readonly GRID_CELL: number = 46;
  private static readonly GRID_CUTOFF: number = 2.4;
  /** 画布边距与簇间距（vp）。 */
  private static readonly MARGIN: number = 18;
  private static readonly SHELF_GAP: number = 20;
  /** 小图放大上限：几篇笔记的小簇也要撑满画布，避免缩成一角。 */
  private static readonly MAX_UPSCALE: number = 1.9;

  /**
   * 计算布局坐标（原地写入 graph.nodes 的 x / y / radius）。
   *
   * @param graph 图谱数据
   * @param width 画布宽（vp）
   * @param height 画布高（vp）
   * @return 结构统计（群簇数 / 未链接数 / 枢纽）
   */
  public static compute(graph: GraphData, width: number, height: number): GraphLayoutStats {
    const stats: GraphLayoutStats = new GraphLayoutStats();
    const count: number = graph.nodes.length;
    if (count === 0 || width <= 0 || height <= 0) {
      return stats;
    }
    const nodes: GraphNode[] = graph.nodes;

    // 路径 → 下标
    const indexByPath: Map<string, number> = new Map<string, number>();
    for (let i = 0; i < count; i++) {
      indexByPath.set(nodes[i].path, i);
    }
    // 度数与边下标（下标化，迭代内不再查字符串）
    const degree: number[] = new Array<number>(count).fill(0);
    const edgeFrom: number[] = [];
    const edgeTo: number[] = [];
    for (const edge of graph.edges) {
      const a: number | undefined = indexByPath.get(edge.from);
      const b: number | undefined = indexByPath.get(edge.to);
      if (a === undefined || b === undefined || a === b) {
        continue;
      }
      edgeFrom.push(a);
      edgeTo.push(b);
      degree[a] += 1;
      degree[b] += 1;
    }
    for (let i = 0; i < count; i++) {
      if (degree[i] > stats.maxDegree) {
        stats.maxDegree = degree[i];
        stats.hubTitle = nodes[i].title;
      }
    }
    // 节点半径：基础 + 枢纽加成（连接越多越显眼）
    const huge: boolean = count > 400;
    const large: boolean = count > 120;
    const base: number = huge ? 4.5 : (large ? 7 : 12);
    for (let i = 0; i < count; i++) {
      const node: GraphNode = nodes[i];
      let radius: number = base * (1 + Math.min(degree[i], 12) * 0.09);
      if (node.root) {
        radius *= large ? 1.4 : 1.6;
      }
      node.radius = radius;
    }

    // 连通分量分解（Union-Find，迭代式路径压缩）
    const parent: number[] = new Array<number>(count);
    for (let i = 0; i < count; i++) {
      parent[i] = i;
    }
    for (let e = 0; e < edgeFrom.length; e++) {
      const ra: number = GraphLayout.findRoot(parent, edgeFrom[e]);
      const rb: number = GraphLayout.findRoot(parent, edgeTo[e]);
      if (ra !== rb) {
        parent[rb] = ra;
      }
    }
    const memberOf: Map<number, number[]> = new Map<number, number[]>();
    for (let i = 0; i < count; i++) {
      const root: number = GraphLayout.findRoot(parent, i);
      const bucket: number[] | undefined = memberOf.get(root);
      if (bucket === undefined) {
        memberOf.set(root, [i]);
      } else {
        bucket.push(i);
      }
    }
    const components: number[][] = [];
    const orphans: number[] = [];
    memberOf.forEach((members: number[]) => {
      if (members.length >= 2) {
        components.push(members);
      } else {
        orphans.push(members[0]);
      }
    });
    stats.clusters = components.length;
    stats.orphans = orphans.length;

    // 孤立笔记收纳到底部「未链接」网格区（零模拟成本）
    let clusterBottom: number = height;
    if (orphans.length > 0) {
      const cell: number = Math.max(14, base * 3.2);
      const cols: number = Math.max(1, Math.floor((width - GraphLayout.MARGIN * 2) / cell));
      const rows: number = Math.ceil(orphans.length / cols);
      const gridWidth: number = cols * cell;
      const startX: number = (width - gridWidth) / 2;
      const stripTop: number = height - rows * cell - GraphLayout.MARGIN;
      for (let k = 0; k < orphans.length; k++) {
        const node: GraphNode = nodes[orphans[k]];
        node.x = startX + (k % cols) * cell + cell / 2;
        node.y = stripTop + Math.floor(k / cols) * cell + cell / 2;
      }
      clusterBottom = stripTop - 12;
    }

    if (components.length > 0) {
      // 全局下标 → 簇序号 / 簇内局部下标
      const compIdOf: number[] = new Array<number>(count).fill(-1);
      const localPosOf: number[] = new Array<number>(count).fill(-1);
      for (let c = 0; c < components.length; c++) {
        const members: number[] = components[c];
        for (let m = 0; m < members.length; m++) {
          compIdOf[members[m]] = c;
          localPosOf[members[m]] = m;
        }
      }
      // 边按簇分桶（局部下标对）
      const localEdgesFrom: number[][] = [];
      const localEdgesTo: number[][] = [];
      for (let c = 0; c < components.length; c++) {
        localEdgesFrom.push([]);
        localEdgesTo.push([]);
      }
      for (let e = 0; e < edgeFrom.length; e++) {
        const cid: number = compIdOf[edgeFrom[e]];
        if (cid < 0) {
          continue;
        }
        localEdgesFrom[cid].push(localPosOf[edgeFrom[e]]);
        localEdgesTo[cid].push(localPosOf[edgeTo[e]]);
      }
      // 各簇局部力导向（以原点为中心）
      for (let c = 0; c < components.length; c++) {
        GraphLayout.layoutComponent(nodes, components[c], localEdgesFrom[c], localEdgesTo[c], base);
      }
      // 簇间货架式装箱（高度降序、逐行摆放、绝不重叠）
      GraphLayout.packComponents(nodes, components, width, clusterBottom);
    }

    // 最终钳制到画布内
    for (let i = 0; i < count; i++) {
      const node: GraphNode = nodes[i];
      node.x = Math.max(node.radius + 2, Math.min(width - node.radius - 2, node.x));
      node.y = Math.max(node.radius + 2, Math.min(height - node.radius - 2, node.y));
    }
    return stats;
  }

  /** Union-Find 查根（迭代式路径压缩）。 */
  private static findRoot(parent: number[], a: number): number {
    let root: number = a;
    while (parent[root] !== root) {
      root = parent[root];
    }
    while (parent[a] !== root) {
      const next: number = parent[a];
      parent[a] = root;
      a = next;
    }
    return root;
  }

  /**
   * 单个连通分量的力导向布局（局部坐标，以原点为中心）。
   * 小簇精确两两斥力；大簇（>GRID_THRESHOLD）空间网格近似。
   */
  private static layoutComponent(nodes: GraphNode[], members: number[],
    localEdgesFrom: number[], localEdgesTo: number[], base: number): void {
    const k: number = members.length;
    const vx: number[] = new Array<number>(k).fill(0);
    const vy: number[] = new Array<number>(k).fill(0);
    // 初始：圆周分布
    const r0: number = Math.max(26, Math.sqrt(k) * base * 2.4);
    for (let i = 0; i < k; i++) {
      const node: GraphNode = nodes[members[i]];
      const angle: number = (Math.PI * 2 * i) / k;
      node.x = r0 * Math.cos(angle);
      node.y = r0 * Math.sin(angle);
    }
    const useGrid: boolean = k > GraphLayout.GRID_THRESHOLD;
    const iterations: number = k <= 40 ? 110 : (useGrid ? 80 : 90);
    const rest: number = Math.max(34, Math.min(84, base * 7));
    for (let step = 0; step < iterations; step++) {
      if (useGrid) {
        GraphLayout.gridRepulsion(nodes, members, vx, vy);
      } else {
        // 精确两两斥力
        for (let i = 0; i < k; i++) {
          const a: GraphNode = nodes[members[i]];
          for (let j = i + 1; j < k; j++) {
            const b: GraphNode = nodes[members[j]];
            let dx: number = a.x - b.x;
            let dy: number = a.y - b.y;
            let d2: number = dx * dx + dy * dy;
            if (d2 < 1) {
              dx = (i - j) * 0.5 + 0.1;
              dy = 0.1;
              d2 = dx * dx + dy * dy;
            }
            const d: number = Math.sqrt(d2);
            const f: number = GraphLayout.REPULSION / d2;
            const fx: number = (dx / d) * f;
            const fy: number = (dy / d) * f;
            vx[i] += fx;
            vy[i] += fy;
            vx[j] -= fx;
            vy[j] -= fy;
          }
        }
      }
      // 弹簧（簇内连线）
      for (let e = 0; e < localEdgesFrom.length; e++) {
        const ia: number = localEdgesFrom[e];
        const ib: number = localEdgesTo[e];
        const a: GraphNode = nodes[members[ia]];
        const b: GraphNode = nodes[members[ib]];
        const dx: number = b.x - a.x;
        const dy: number = b.y - a.y;
        const d: number = Math.max(1, Math.sqrt(dx * dx + dy * dy));
        const f: number = (d - rest) * GraphLayout.SPRING;
        const fx: number = (dx / d) * f;
        const fy: number = (dy / d) * f;
        vx[ia] += fx;
        vy[ia] += fy;
        vx[ib] -= fx;
        vy[ib] -= fy;
      }
      // 向心 + 阻尼 + 积分
      for (let i = 0; i < k; i++) {
        const node: GraphNode = nodes[members[i]];
        vx[i] -= node.x * GraphLayout.GRAVITY;
        vy[i] -= node.y * GraphLayout.GRAVITY;
        vx[i] *= GraphLayout.DAMPING;
        vy[i] *= GraphLayout.DAMPING;
        node.x += vx[i];
        node.y += vy[i];
      }
    }
  }

  /** 大簇斥力：空间网格近似，只与 3×3 邻近格内的节点互斥（截断距离外不施力）。 */
  private static gridRepulsion(nodes: GraphNode[], members: number[],
    vx: number[], vy: number[]): void {
    const k: number = members.length;
    const cell: number = GraphLayout.GRID_CELL;
    const cutoff2: number = (cell * GraphLayout.GRID_CUTOFF) * (cell * GraphLayout.GRID_CUTOFF);
    const buckets: Map<number, number[]> = new Map<number, number[]>();
    for (let i = 0; i < k; i++) {
      const node: GraphNode = nodes[members[i]];
      const key: number = GraphLayout.gridKey(node.x, node.y, cell);
      const bucket: number[] | undefined = buckets.get(key);
      if (bucket === undefined) {
        buckets.set(key, [i]);
      } else {
        bucket.push(i);
      }
    }
    for (let i = 0; i < k; i++) {
      const a: GraphNode = nodes[members[i]];
      const cx: number = Math.floor(a.x / cell);
      const cy: number = Math.floor(a.y / cell);
      for (let ox = -1; ox <= 1; ox++) {
        for (let oy = -1; oy <= 1; oy++) {
          const bucket: number[] | undefined = buckets.get(
            (cx + ox + 4096) * 8192 + (cy + oy + 4096));
          if (bucket === undefined) {
            continue;
          }
          for (const j of bucket) {
            if (j === i) {
              continue;
            }
            const b: GraphNode = nodes[members[j]];
            let dx: number = a.x - b.x;
            let dy: number = a.y - b.y;
            const d2: number = dx * dx + dy * dy;
            if (d2 >= cutoff2) {
              continue;
            }
            if (d2 < 1) {
              dx = (i - j) * 0.5 + 0.1;
              dy = 0.1;
            }
            const d: number = Math.max(0.01, Math.sqrt(dx * dx + dy * dy));
            const f: number = GraphLayout.REPULSION / (d * d);
            vx[i] += (dx / d) * f;
            vy[i] += (dy / d) * f;
          }
        }
      }
    }
  }

  /** 空间网格键（数值哈希，避免热循环内拼字符串）。 */
  private static gridKey(x: number, y: number, cell: number): number {
    return (Math.floor(x / cell) + 4096) * 8192 + (Math.floor(y / cell) + 4096);
  }

  /**
   * 簇间装箱：各簇缩放到适配画布（过大缩小、过小放大至上限），
   * 按包围盒高度降序做货架式逐行摆放；溢出时整体等比压缩兜底。
   */
  private static packComponents(nodes: GraphNode[], components: number[][],
    width: number, clusterBottom: number): void {
    const targetW: number = width - GraphLayout.MARGIN * 2;
    const availH: number = clusterBottom - GraphLayout.MARGIN;
    if (targetW <= 0 || availH <= 0) {
      return;
    }
    // 各簇包围盒
    const boxes: number[][] = [];
    for (let c = 0; c < components.length; c++) {
      boxes.push(GraphLayout.boundingBox(nodes, components[c]));
    }
    const order: number[] = [];
    for (let c = 0; c < components.length; c++) {
      order.push(c);
    }
    order.sort((a: number, b: number): number => (boxes[b][3] - boxes[b][1]) - (boxes[a][3] - boxes[a][1]));
    // 货架游标
    let cursorX: number = 0;
    let cursorY: number = 0;
    let rowH: number = 0;
    for (const c of order) {
      const members: number[] = components[c];
      let box: number[] = boxes[c];
      let w: number = Math.max(1, box[2] - box[0]);
      let h: number = Math.max(1, box[3] - box[1]);
      // 适配缩放：过大缩小到画布内；过小放大撑满（上限 MAX_UPSCALE）
      let s: number = Math.min(targetW / w, availH / h);
      if (s > GraphLayout.MAX_UPSCALE) {
        s = GraphLayout.MAX_UPSCALE;
      }
      if (s !== 1) {
        const cx: number = (box[0] + box[2]) / 2;
        const cy: number = (box[1] + box[3]) / 2;
        for (const m of members) {
          const node: GraphNode = nodes[m];
          node.x = cx + (node.x - cx) * s;
          node.y = cy + (node.y - cy) * s;
          // 半径随缩放同步收缩，避免位置压缩后圆点互相重叠堆叠
          node.radius = Math.max(2.2, node.radius * s);
        }
        w *= s;
        h *= s;
        box = [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2];
      }
      // 换行判断
      if (cursorX > 0 && cursorX + w > targetW) {
        cursorX = 0;
        cursorY += rowH + GraphLayout.SHELF_GAP;
        rowH = 0;
      }
      // 平移到货架槽位
      const dx: number = GraphLayout.MARGIN + cursorX - box[0];
      const dy: number = GraphLayout.MARGIN + cursorY - box[1];
      for (const m of members) {
        const node: GraphNode = nodes[m];
        node.x += dx;
        node.y += dy;
      }
      cursorX += w + GraphLayout.SHELF_GAP;
      if (h > rowH) {
        rowH = h;
      }
    }
    // 整体校验：所有簇节点合并包围盒，溢出等比压缩，否则水平/垂直居中
    const allMembers: number[] = [];
    for (const members of components) {
      for (const m of members) {
        allMembers.push(m);
      }
    }
    const total: number[] = GraphLayout.boundingBox(nodes, allMembers);
    const bw: number = Math.max(1, total[2] - total[0]);
    const bh: number = Math.max(1, total[3] - total[1]);
    if (bw > targetW || bh > availH) {
      const s2: number = Math.min(targetW / bw, availH / bh);
      const cx: number = (total[0] + total[2]) / 2;
      const cy: number = (total[1] + total[3]) / 2;
      for (const m of allMembers) {
        const node: GraphNode = nodes[m];
        node.x = cx + (node.x - cx) * s2;
        node.y = cy + (node.y - cy) * s2;
      }
    }
    // 重算包围盒并居中到簇区域
    const finalBox: number[] = GraphLayout.boundingBox(nodes, allMembers);
    const fw: number = Math.max(1, finalBox[2] - finalBox[0]);
    const fh: number = Math.max(1, finalBox[3] - finalBox[1]);
    const tx: number = GraphLayout.MARGIN + (targetW - fw) / 2 - finalBox[0];
    const ty: number = GraphLayout.MARGIN + (availH - fh) / 2 - finalBox[1];
    if (Math.abs(tx) > 0.5 || Math.abs(ty) > 0.5) {
      for (const m of allMembers) {
        const node: GraphNode = nodes[m];
        node.x += tx;
        node.y += ty;
      }
    }
  }

  /** 一组节点的包围盒 [minX, minY, maxX, maxY]。 */
  private static boundingBox(nodes: GraphNode[], members: number[]): number[] {
    let minX: number = Number.MAX_VALUE;
    let minY: number = Number.MAX_VALUE;
    let maxX: number = -Number.MAX_VALUE;
    let maxY: number = -Number.MAX_VALUE;
    for (const m of members) {
      const node: GraphNode = nodes[m];
      const r: number = node.radius;
      if (node.x - r < minX) {
        minX = node.x - r;
      }
      if (node.y - r < minY) {
        minY = node.y - r;
      }
      if (node.x + r > maxX) {
        maxX = node.x + r;
      }
      if (node.y + r > maxY) {
        maxY = node.y + r;
      }
    }
    return [minX, minY, maxX, maxY];
  }
}
