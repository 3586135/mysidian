/**
 * Mermaid 流程图解析与分层布局（原生实现，不依赖 mermaid.js）。
 *
 * 支持的语法子集：
 * - `graph TD` / `flowchart LR` 声明方向
 * - `A[文本]`、`A(文本)`、`A{文本}`、`A((文本))` 节点定义
 * - `A --> B`、`A -->|标签| B`、`A --- B` 连线
 * - `%%` 开头的注释行忽略
 */
export class FlowNode {
  /** 节点标识。 */
  id: string = '';
  /** 显示文本。 */
  label: string = '';
  /** 布局位置（vp）。 */
  x: number = 0;
  y: number = 0;
  /** 节点尺寸（vp）。 */
  nodeWidth: number = 0;
  nodeHeight: number = 0;
  /** 是否为判定节点（花括号 / 圆角）。 */
  decision: boolean = false;
  /** 是否为当前笔记（根节点高亮）。 */
  root: boolean = false;
}

/** 流程图连线。 */
export class FlowEdge {
  from: string = '';
  to: string = '';
  label: string = '';
}

/** 解析后的流程图。 */
export class FlowGraph {
  nodes: FlowNode[] = [];
  edges: FlowEdge[] = [];
  /** 画布宽高（vp）。 */
  graphWidth: number = 0;
  graphHeight: number = 0;
  /** 是否解析成功。 */
  valid: boolean = false;
  /** 布局方向：TD / TB / LR / RL / BT。 */
  direction: string = 'TD';
  /** 是否为横向布局。 */
  horizontal: boolean = false;
}

/**
 * Mermaid 流程图解析器。
 */
export class MermaidFlow {
  private static readonly NODE_HEIGHT: number = 44;
  private static readonly MIN_NODE_WIDTH: number = 72;
  private static readonly LAYER_GAP: number = 96;
  private static readonly NODE_GAP: number = 28;

  /**
   * 解析 Mermaid 源码并计算布局。
   */
  public static parse(source: string): FlowGraph {
    const graph: FlowGraph = new FlowGraph();
    const lines: string[] = source.split('\n');
    let direction: string = 'TD';
    let started: boolean = false;
    const order: string[] = [];
    const labels: Record<string, string> = {};
    const decisions: Record<string, boolean> = {};

    for (let index = 0; index < lines.length; index++) {
      const raw: string = lines[index].trim();
      if (raw.length === 0 || raw.startsWith('%%')) {
        continue;
      }
      const header: RegExpExecArray | null = /^(graph|flowchart)\s+(TD|TB|LR|RL|BT)/i.exec(raw);
      if (header !== null) {
        direction = header[2].toUpperCase();
        started = true;
        continue;
      }
      // 捕获组：1=起点标识 2=起点形状 3=连线标签 4=终点标识 5=终点形状
      const edge: RegExpExecArray | null =
        /^([A-Za-z0-9_]+)(\[[^\]]*\]|\([^\)]*\)|\{[^\}]*\}|\(\([^\)]*\)\))?\s*-->\s*(?:\|([^|]*)\|\s*)?([A-Za-z0-9_]+)(\[[^\]]*\]|\([^\)]*\)|\{[^\}]*\}|\(\([^\)]*\)\))?$/
          .exec(raw);
      if (edge !== null) {
        started = true;
        const from: string = edge[1];
        const to: string = edge[4];
        const fromShape: string = edge[2] === undefined ? '' : edge[2];
        const toShape: string = edge[5] === undefined ? '' : edge[5];
        const edgeLabel: string = edge[3] === undefined ? '' : edge[3].trim();
        MermaidFlow.touch(order, labels, decisions, from);
        MermaidFlow.touch(order, labels, decisions, to);
        MermaidFlow.applyShape(labels, decisions, from, fromShape);
        MermaidFlow.applyShape(labels, decisions, to, toShape);
        const flowEdge: FlowEdge = new FlowEdge();
        flowEdge.from = from;
        flowEdge.to = to;
        flowEdge.label = edgeLabel;
        graph.edges.push(flowEdge);
        continue;
      }
      const single: RegExpExecArray | null =
        /^([A-Za-z0-9_]+)\s*(\[[^\]]*\]|\([^\)]*\)|\{[^\}]*\}|\(\([^\)]*\)\))$/.exec(raw);
      if (single !== null) {
        started = true;
        const id: string = single[1];
        MermaidFlow.touch(order, labels, decisions, id);
        const shape: string = single[2];
        const label: string = MermaidFlow.labelOf(shape);
        if (label.length > 0) {
          labels[id] = label;
        }
        decisions[id] = shape.startsWith('{') || shape.startsWith('((');
      }
    }

    if (!started || graph.edges.length === 0) {
      return graph;
    }

    // 节点列表与尺寸
    for (const id of order) {
      if (id.length === 0) {
        continue;
      }
      const node: FlowNode = new FlowNode();
      node.id = id;
      const label: string = labels[id] === undefined ? id : labels[id];
      node.label = label;
      node.decision = decisions[id] === true;
      node.nodeWidth = Math.max(MermaidFlow.MIN_NODE_WIDTH,
        Math.min(220, label.length * 14 + 28));
      node.nodeHeight = MermaidFlow.NODE_HEIGHT;
      graph.nodes.push(node);
    }

    MermaidFlow.layout(graph, direction);
    graph.direction = direction;
    graph.horizontal = direction === 'LR' || direction === 'RL';
    graph.valid = true;
    return graph;
  }

  /** 注册节点（保持首次出现顺序）。 */
  private static touch(order: string[], labels: Record<string, string>,
    decisions: Record<string, boolean>, id: string): void {
    if (id.length === 0) {
      return;
    }
    if (!order.includes(id)) {
      order.push(id);
      labels[id] = id;
      decisions[id] = false;
    }
  }

  /** 应用节点形状：写入显示文本与判定标记。 */
  private static applyShape(labels: Record<string, string>, decisions: Record<string, boolean>,
    id: string, shape: string): void {
    if (shape.length === 0) {
      return;
    }
    const label: string = MermaidFlow.labelOf(shape);
    if (label.length > 0) {
      labels[id] = label;
    }
    decisions[id] = shape.startsWith('{') || shape.startsWith('((');
  }

  /** 提取节点形状中的显示文本。 */
  private static labelOf(shape: string): string {
    const open: number = shape.indexOf('[');
    const open2: number = shape.indexOf('(');
    const open3: number = shape.indexOf('{');
    let start: number = -1;
    let end: number = shape.length;
    if (open >= 0 && (open2 < 0 || open < open2)) {
      start = open + 1;
      end = shape.lastIndexOf(']');
    } else if (open3 >= 0 && (open2 < 0 || open3 < open2)) {
      start = open3 + 1;
      end = shape.lastIndexOf('}');
    } else if (open2 >= 0) {
      start = open2 + 1;
      end = shape.lastIndexOf(')');
    }
    if (start < 0 || end <= start) {
      return '';
    }
    return shape.substring(start, end).trim();
  }

  /** 分层布局：按最长路径求层级，层内按出现顺序排列。 */
  private static layout(graph: FlowGraph, direction: string): void {
    const depthMap: Record<string, number> = {};
    for (const node of graph.nodes) {
      depthMap[node.id] = 0;
    }
    // 迭代松弛：最多 nodeCount 轮，确保最长路径层级正确。
    const rounds: number = Math.min(graph.nodes.length, 64);
    for (let round = 0; round < rounds; round++) {
      let changed: boolean = false;
      for (const edge of graph.edges) {
        const fromDepth: number = depthMap[edge.from];
        const toDepth: number = depthMap[edge.to];
        if (toDepth < fromDepth + 1) {
          depthMap[edge.to] = fromDepth + 1;
          changed = true;
        }
      }
      if (!changed) {
        break;
      }
    }

    const layers: number = MermaidFlow.maxDepth(depthMap) + 1;
    const counts: number[] = new Array<number>(layers).fill(0);
    const horizontal: boolean = direction === 'LR' || direction === 'RL';

    // 计算每层最宽节点，用于对齐。
    const layerWidth: number[] = new Array<number>(layers).fill(0);
    for (const node of graph.nodes) {
      const depth: number = depthMap[node.id];
      if (node.nodeWidth > layerWidth[depth]) {
        layerWidth[depth] = node.nodeWidth;
      }
    }

    const offsets: number[] = new Array<number>(layers).fill(0);
    let acc: number = 0;
    for (let depth = 0; depth < layers; depth++) {
      offsets[depth] = acc;
      acc += layerWidth[depth] + MermaidFlow.LAYER_GAP;
    }
    const totalWidth: number = Math.max(0, acc - MermaidFlow.LAYER_GAP);

    let maxHeight: number = 0;
    for (const node of graph.nodes) {
      const depth: number = depthMap[node.id];
      const index: number = counts[depth];
      counts[depth] = index + 1;
      const along: number = index * (MermaidFlow.NODE_HEIGHT + MermaidFlow.NODE_GAP);
      if (horizontal) {
        node.x = offsets[depth] + (layerWidth[depth] - node.nodeWidth) / 2;
        node.y = along;
      } else {
        node.x = along;
        node.y = offsets[depth] + (layerWidth[depth] - node.nodeHeight) / 2;
      }
      const nodeBottom: number = node.y + node.nodeHeight;
      if (nodeBottom > maxHeight) {
        maxHeight = nodeBottom;
      }
    }

    // TD 方向：层沿 y 轴，层内沿 x 轴；上面按 along 计算的是层内偏移，
    // 这里统一转换为层偏移（沿层方向）与层内偏移（垂直层方向）。
    if (!horizontal) {
      const layerOffsets: number[] = new Array<number>(layers).fill(0);
      let layerAcc: number = 0;
      for (let depth = 0; depth < layers; depth++) {
        layerOffsets[depth] = layerAcc;
        layerAcc += layerWidth[depth] + MermaidFlow.LAYER_GAP;
      }
      const counters: number[] = new Array<number>(layers).fill(0);
      for (const node of graph.nodes) {
        const depth: number = depthMap[node.id];
        const index: number = counters[depth];
        counters[depth] = index + 1;
        node.y = layerOffsets[depth] + (layerWidth[depth] - node.nodeHeight) / 2;
        node.x = index * (MermaidFlow.NODE_HEIGHT + MermaidFlow.NODE_GAP);
      }
      let bottom: number = 0;
      let right: number = 0;
      for (const node of graph.nodes) {
        if (node.y + node.nodeHeight > bottom) {
          bottom = node.y + node.nodeHeight;
        }
        if (node.x + node.nodeWidth > right) {
          right = node.x + node.nodeWidth;
        }
      }
      graph.graphWidth = right + 24;
      graph.graphHeight = bottom + 24;
      return;
    }

    let bottom: number = 0;
    let right: number = 0;
    for (const node of graph.nodes) {
      if (node.y + node.nodeHeight > bottom) {
        bottom = node.y + node.nodeHeight;
      }
      if (node.x + node.nodeWidth > right) {
        right = node.x + node.nodeWidth;
      }
    }
    graph.graphWidth = right + 24;
    graph.graphHeight = bottom + 24;
  }

  /** 最大层级。 */
  private static maxDepth(depthMap: Record<string, number>): number {
    let max: number = 0;
    const keys: string[] = Object.keys(depthMap);
    for (const key of keys) {
      if (depthMap[key] > max) {
        max = depthMap[key];
      }
    }
    return max;
  }
}
