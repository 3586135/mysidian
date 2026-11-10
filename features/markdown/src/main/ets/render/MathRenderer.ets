/**
 * 轻量 LaTeX → HTML 渲染器（原生实现，不依赖 KaTeX 运行时）。
 *
 * 覆盖 Obsidian 笔记中常见的构造：分数、上下标、根号、希腊字母、
 * 常用运算符与 \text{} 文本。渲染结果交给 MdWebFallback（关闭脚本）显示。
 *
 * 实现要点：先对原始文本做 HTML 转义，再展开命令与上下标，
 * 因此生成的标签不会被二次转义，用户内容也不会破坏结构。
 */
export class MathRenderer {
  /** 数学公式的附加样式（注入 MdWebFallback）。 */
  public static readonly CSS: string =
    '.frac{display:inline-block;vertical-align:middle;text-align:center;margin:0 2px;}' +
    '.frac .num{display:block;border-bottom:1px solid currentColor;padding:0 4px;}' +
    '.frac .den{display:block;padding:0 4px;}' +
    '.sqrt .radic{border-top:1px solid currentColor;padding:0 2px;}' +
    '.mtext{font-family:sans-serif;font-style:normal;}';

  /** 希腊字母与常用符号表。 */
  private static readonly SYMBOLS: Record<string, string> = {
    'alpha': 'α', 'beta': 'β', 'gamma': 'γ', 'delta': 'δ', 'epsilon': 'ε',
    'zeta': 'ζ', 'eta': 'η', 'theta': 'θ', 'iota': 'ι', 'kappa': 'κ',
    'lambda': 'λ', 'mu': 'μ', 'nu': 'ν', 'xi': 'ξ', 'pi': 'π',
    'rho': 'ρ', 'sigma': 'σ', 'tau': 'τ', 'upsilon': 'υ', 'phi': 'φ',
    'chi': 'χ', 'psi': 'ψ', 'omega': 'ω',
    'Gamma': 'Γ', 'Delta': 'Δ', 'Theta': 'Θ', 'Lambda': 'Λ', 'Xi': 'Ξ',
    'Pi': 'Π', 'Sigma': 'Σ', 'Upsilon': 'Υ', 'Phi': 'Φ', 'Psi': 'Ψ',
    'Omega': 'Ω',
    'times': '×', 'div': '÷', 'pm': '±', 'mp': '∓', 'cdot': '·',
    'leq': '≤', 'geq': '≥', 'neq': '≠', 'approx': '≈', 'equiv': '≡',
    'infty': '∞', 'partial': '∂', 'nabla': '∇', 'sum': '∑', 'prod': '∏',
    'int': '∫', 'rightarrow': '→', 'leftarrow': '←',
    'Rightarrow': '⇒', 'Leftarrow': '⇐', 'leftrightarrow': '↔',
    'in': '∈', 'notin': '∉', 'subset': '⊂', 'supset': '⊃',
    'cup': '∪', 'cap': '∩', 'forall': '∀', 'exists': '∃',
    'ldots': '…', 'cdots': '⋯', 'angle': '∠', 'perp': '⊥', 'parallel': '∥',
    'circ': '∘', 'oplus': '⊕', 'otimes': '⊗'
  };

  /** Unicode 上标映射。 */
  private static readonly SUPER_MAP: Record<string, string> = {
    '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
    '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
    '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾',
    'n': 'ⁿ', 'i': 'ⁱ', 'a': 'ᵃ', 'b': 'ᵇ', 'c': 'ᶜ',
    'd': 'ᵈ', 'e': 'ᵉ', 'f': 'ᶠ', 'g': 'ᵍ', 'h': 'ʰ',
    'j': 'ʲ', 'k': 'ᵏ', 'l': 'ˡ', 'm': 'ᵐ', 'o': 'ᵒ',
    'p': 'ᵖ', 'r': 'ʳ', 's': 'ˢ', 't': 'ᵗ', 'u': 'ᵘ',
    'v': 'ᵛ', 'w': 'ʷ', 'x': 'ˣ', 'y': 'ʸ', 'z': 'ᶻ', 'T': 'ᵀ'
  };

  /** Unicode 下标映射。 */
  private static readonly SUB_MAP: Record<string, string> = {
    '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
    '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
    '+': '₊', '-': '₋', '=': '₌', '(': '₍', ')': '₎',
    'a': 'ₐ', 'e': 'ₑ', 'h': 'ₕ', 'i': 'ᵢ', 'j': 'ⱼ',
    'k': 'ₖ', 'l': 'ₗ', 'm': 'ₘ', 'n': 'ₙ', 'o': 'ₒ',
    'p': 'ₚ', 'r': 'ᵣ', 's': 'ₛ', 't': 'ₜ', 'u': 'ᵤ',
    'v': 'ᵥ', 'x': 'ₓ'
  };

  /** 把 LaTeX 片段渲染为 HTML。 */
  public static toHtml(latex: string): string {
    const trimmed: string = latex.trim();
    if (trimmed.length === 0) {
      return '';
    }
    return MathRenderer.render(MathRenderer.escapeHtml(trimmed), 0);
  }

  /**
   * 把 LaTeX 片段转换为纯文本近似（Unicode 上下标）。
   *
   * 用于原生 ArkUI 渲染：避免依赖 Web 引擎，深浅色模式下都可读。
   */
  public static toPlain(latex: string): string {
    const trimmed: string = latex.trim();
    if (trimmed.length === 0) {
      return '';
    }
    return MathRenderer.plain(trimmed, 0);
  }

  /** 纯文本渲染过程（输入为原始 LaTeX，不做 HTML 转义）。 */
  private static plain(text: string, depth: number): string {
    let out: string = '';
    let index: number = 0;
    const guard: number = 12;
    while (index < text.length) {
      if (depth > guard) {
        out += text.substring(index);
        break;
      }
      const ch: string = text.charAt(index);
      if (ch === '\\') {
        const command: CommandChunk = MathRenderer.readCommand(text, index);
        if (command.name.length > 0) {
          out += MathRenderer.plainCommand(command, text, depth);
          index = command.next;
          continue;
        }
        out += ch;
        index++;
        continue;
      }
      if (ch === '^' || ch === '_') {
        const script: ScriptChunk = MathRenderer.readScriptPlain(text, index, ch);
        out += script.text;
        index = script.next;
        continue;
      }
      if (ch === '{' || ch === '}') {
        index++;
        continue;
      }
      out += ch;
      index++;
    }
    return out;
  }

  /** 纯文本模式下的命令展开。 */
  private static plainCommand(command: CommandChunk, text: string, depth: number): string {
    const name: string = command.name;
    if (command.escaped) {
      if (name === '\\') {
        return '\n';
      }
      const escapedSymbol: string = MathRenderer.SYMBOLS[name];
      return escapedSymbol === undefined ? name : escapedSymbol;
    }
    if (name === 'frac' || name === 'dfrac' || name === 'tfrac') {
      const numerator: ScriptChunk = MathRenderer.readGroup(text, command.next);
      const denominator: ScriptChunk = MathRenderer.readGroup(text, numerator.next);
      return `(${MathRenderer.plain(numerator.body, depth + 1)})` +
        `/(${MathRenderer.plain(denominator.body, depth + 1)})`;
    }
    if (name === 'sqrt') {
      const radicand: ScriptChunk = MathRenderer.readGroup(text, command.next);
      return `√(${MathRenderer.plain(radicand.body, depth + 1)})`;
    }
    if (name === 'text' || name === 'mathrm' || name === 'operatorname') {
      const group: ScriptChunk = MathRenderer.readGroup(text, command.next);
      return group.body;
    }
    if (name === 'left' || name === 'right') {
      return '';
    }
    if (name === 'newline') {
      return '\n';
    }
    if (name === ',' || name === ';' || name === '!' || name === ' ') {
      return ' ';
    }
    const symbol: string = MathRenderer.SYMBOLS[name];
    if (symbol !== undefined) {
      return symbol;
    }
    return name;
  }

  /** 读取上标 / 下标并转成 Unicode 字符。 */
  private static readScriptPlain(text: string, start: number, marker: string): ScriptChunk {
    const chunk: ScriptChunk = new ScriptChunk();
    let index: number = start + 1;
    let body: string = '';
    if (index < text.length && text.charAt(index) === '{') {
      const group: ScriptChunk = MathRenderer.readGroup(text, index);
      body = group.body;
      index = group.next;
    } else if (index < text.length) {
      body = text.charAt(index);
      index++;
    }
    chunk.text = marker === '^' ? MathRenderer.toSuper(body) : MathRenderer.toSub(body);
    chunk.next = index;
    return chunk;
  }

  /** 转换为 Unicode 上标（无对应字符时保留原字符）。 */
  public static toSuper(text: string): string {
    let out: string = '';
    for (let index = 0; index < text.length; index++) {
      const ch: string = text.charAt(index);
      const mapped: string = MathRenderer.SUPER_MAP[ch];
      out += mapped === undefined ? ch : mapped;
    }
    return out;
  }

  /** 转换为 Unicode 下标（无对应字符时保留原字符）。 */
  public static toSub(text: string): string {
    let out: string = '';
    for (let index = 0; index < text.length; index++) {
      const ch: string = text.charAt(index);
      const mapped: string = MathRenderer.SUB_MAP[ch];
      out += mapped === undefined ? ch : mapped;
    }
    return out;
  }

  /** 渲染过程：命令与上下标递归展开（输入已转义）。 */
  private static render(text: string, depth: number): string {
    let html: string = '';
    let index: number = 0;
    const guard: number = 12;
    while (index < text.length) {
      if (depth > guard) {
        html += text.substring(index);
        break;
      }
      const ch: string = text.charAt(index);
      if (ch === '\\') {
        const command: CommandChunk = MathRenderer.readCommand(text, index);
        if (command.name.length > 0) {
          html += MathRenderer.applyCommand(command, text, depth);
          index = command.next;
          continue;
        }
        html += ch;
        index++;
        continue;
      }
      if (ch === '^' || ch === '_') {
        const script: ScriptChunk = MathRenderer.readScript(text, index, ch);
        html += script.html;
        index = script.next;
        continue;
      }
      html += ch;
      index++;
    }
    return html;
  }

  /** 读取一个反斜杠命令。 */
  private static readCommand(text: string, start: number): CommandChunk {
    const chunk: CommandChunk = new CommandChunk();
    let index: number = start + 1;
    let name: string = '';
    while (index < text.length && /[a-zA-Z]/.test(text.charAt(index))) {
      name += text.charAt(index);
      index++;
    }
    if (name.length === 0) {
      // 转义字符：\{ \} \, \; \% \& \# \$ \_
      if (index < text.length) {
        chunk.name = text.charAt(index);
        chunk.next = index + 1;
        chunk.escaped = true;
      } else {
        chunk.next = start + 1;
      }
      return chunk;
    }
    chunk.name = name;
    chunk.next = index;
    return chunk;
  }

  /** 应用命令。 */
  private static applyCommand(command: CommandChunk, text: string, depth: number): string {
    if (command.escaped) {
      const symbol: string = MathRenderer.SYMBOLS[command.name];
      if (symbol !== undefined) {
        return symbol;
      }
      return command.name;
    }
    const name: string = command.name;
    if (name === 'frac' || name === 'dfrac' || name === 'tfrac') {
      const numerator: ScriptChunk = MathRenderer.readGroup(text, command.next);
      const denominator: ScriptChunk = MathRenderer.readGroup(text, numerator.next);
      return `<span class="frac"><span class="num">${MathRenderer.render(numerator.body, depth + 1)}` +
        `</span><span class="den">${MathRenderer.render(denominator.body, depth + 1)}</span></span>`;
    }
    if (name === 'sqrt') {
      const radicand: ScriptChunk = MathRenderer.readGroup(text, command.next);
      return `<span class="sqrt">√<span class="radic">${MathRenderer.render(radicand.body, depth + 1)}</span></span>`;
    }
    if (name === 'text' || name === 'mathrm' || name === 'operatorname') {
      const group: ScriptChunk = MathRenderer.readGroup(text, command.next);
      return `<span class="mtext">${group.body}</span>`;
    }
    if (name === 'left' || name === 'right') {
      // 括号修饰符：丢弃修饰符本身，内部内容照常渲染。
      return '';
    }
    const symbol: string = MathRenderer.SYMBOLS[name];
    if (symbol !== undefined) {
      return symbol;
    }
    return name;
  }

  /** 读取上标 / 下标。 */
  private static readScript(text: string, start: number, marker: string): ScriptChunk {
    const chunk: ScriptChunk = new ScriptChunk();
    let index: number = start + 1;
    let body: string = '';
    if (index < text.length && text.charAt(index) === '{') {
      const group: ScriptChunk = MathRenderer.readGroup(text, index);
      body = group.body;
      index = group.next;
    } else if (index < text.length) {
      body = text.charAt(index);
      index++;
    }
    const tag: string = marker === '^' ? 'sup' : 'sub';
    chunk.html = `<${tag}>${MathRenderer.render(body, 0)}</${tag}>`;
    chunk.next = index;
    return chunk;
  }

  /** 读取 {...} 分组内容。 */
  private static readGroup(text: string, start: number): ScriptChunk {
    const chunk: ScriptChunk = new ScriptChunk();
    let index: number = start;
    if (index >= text.length || text.charAt(index) !== '{') {
      chunk.next = start;
      return chunk;
    }
    index++;
    let depth: number = 1;
    let body: string = '';
    while (index < text.length) {
      const ch: string = text.charAt(index);
      if (ch === '{') {
        depth++;
      } else if (ch === '}') {
        depth--;
        if (depth === 0) {
          index++;
          break;
        }
      }
      body += ch;
      index++;
    }
    chunk.body = body;
    chunk.next = index;
    return chunk;
  }

  /** HTML 转义。 */
  public static escapeHtml(text: string): string {
    let result: string = text;
    result = result.split('&').join('&amp;');
    result = result.split('<').join('&lt;');
    result = result.split('>').join('&gt;');
    return result;
  }
}

/** 命令解析结果。 */
class CommandChunk {
  name: string = '';
  next: number = 0;
  escaped: boolean = false;
}

/** 上下标 / 分组解析结果。 */
class ScriptChunk {
  body: string = '';
  html: string = '';
  text: string = '';
  next: number = 0;
}
