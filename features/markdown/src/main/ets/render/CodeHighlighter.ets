/** 代码语法着色 Token 类型。 */
export enum CodeTokenKind {
  PLAIN = 'plain',
  KEYWORD = 'keyword',
  STRING = 'string',
  COMMENT = 'comment',
  NUMBER = 'number',
  TYPE = 'type'
}

/** 代码语法着色切分片段。 */
export class CodeToken {
  kind: CodeTokenKind = CodeTokenKind.PLAIN;
  text: string = '';

  constructor(kind: CodeTokenKind = CodeTokenKind.PLAIN, text: string = '') {
    this.kind = kind;
    this.text = text;
  }
}

/**
 * 纯 ArkTS 轻量级多语言代码语法分词器。
 * 支持 ArkTS / TS / JS / Python / Java / Kotlin / C / C++ / Go / Rust / SQL / Shell / JSON / YAML，
 * 相邻普通字符自动合并，控制 Span 数量以保证长代码块流畅渲染。
 */
export class CodeHighlighter {
  private static readonly KEYWORDS: Set<string> = new Set<string>([
    'abstract', 'and', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch', 'class',
    'const', 'continue', 'def', 'default', 'del', 'delete', 'do', 'else', 'elif', 'enum',
    'except', 'export', 'extends', 'false', 'finally', 'fn', 'for', 'from', 'fun', 'func',
    'function', 'global', 'if', 'impl', 'implements', 'import', 'in', 'interface', 'is',
    'lambda', 'let', 'loop', 'match', 'module', 'mut', 'namespace', 'new', 'nil', 'none',
    'None', 'nonlocal', 'not', 'null', 'of', 'or', 'override', 'package', 'pass', 'private',
    'protected', 'pub', 'public', 'raise', 'readonly', 'return', 'self', 'static', 'struct',
    'super', 'switch', 'then', 'this', 'throw', 'throws', 'trait', 'true', 'True', 'False',
    'try', 'type', 'typeof', 'undefined', 'use', 'val', 'var', 'void', 'where', 'while',
    'with', 'yield',
    'SELECT', 'FROM', 'WHERE', 'JOIN', 'LEFT', 'RIGHT', 'INNER', 'ON', 'GROUP', 'BY', 'ORDER',
    'ASC', 'DESC', 'LIMIT', 'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET', 'DELETE', 'CREATE',
    'TABLE', 'ALTER', 'DROP', 'AND', 'OR', 'NOT', 'IN', 'IS', 'NULL', 'AS', 'DISTINCT', 'COUNT'
  ]);

  private static readonly BUILTIN_TYPES: Set<string> = new Set<string>([
    'string', 'number', 'boolean', 'bigint', 'symbol', 'object', 'never', 'int', 'float',
    'double', 'char', 'byte', 'short', 'long', 'usize', 'isize', 'u8', 'u16', 'u32', 'u64',
    'i8', 'i16', 'i32', 'i64', 'f32', 'f64', 'bool', 'str', 'list', 'dict', 'tuple', 'set',
    'Map', 'Set', 'Array', 'Promise', 'Record', 'Date', 'RegExp', 'Error', 'Resource',
    'ResourceStr', 'ResourceColor'
  ]);

  /** 将源码按语法切分为着色片段列表。 */
  public static tokenize(code: string, lang: string = ''): CodeToken[] {
    if (code.length === 0) {
      return [];
    }
    const lowerLang: string = lang.trim().toLowerCase();
    const hashComment: boolean = lowerLang === 'py' || lowerLang === 'python' ||
      lowerLang === 'sh' || lowerLang === 'bash' || lowerLang === 'shell' ||
      lowerLang === 'zsh' || lowerLang === 'yaml' || lowerLang === 'yml' ||
      lowerLang === 'ruby' || lowerLang === 'rb';
    const sqlComment: boolean = lowerLang === 'sql';

    const tokens: CodeToken[] = [];
    let plainBuffer: string = '';
    const flushPlain = (): void => {
      if (plainBuffer.length > 0) {
        tokens.push(new CodeToken(CodeTokenKind.PLAIN, plainBuffer));
        plainBuffer = '';
      }
    };

    let i: number = 0;
    const len: number = code.length;
    while (i < len) {
      const ch: string = code.charAt(i);
      const next: string = i + 1 < len ? code.charAt(i + 1) : '';

      // 1. 单行注释 // 或 -- 或 #
      if ((ch === '/' && next === '/') || (sqlComment && ch === '-' && next === '-') ||
        (hashComment && ch === '#')) {
        flushPlain();
        let end: number = code.indexOf('\n', i);
        if (end < 0) {
          end = len;
        }
        tokens.push(new CodeToken(CodeTokenKind.COMMENT, code.substring(i, end)));
        i = end;
        continue;
      }

      // 2. 块注释 /* ... */
      if (ch === '/' && next === '*') {
        flushPlain();
        let end: number = code.indexOf('*/', i + 2);
        if (end < 0) {
          end = len;
        } else {
          end += 2;
        }
        tokens.push(new CodeToken(CodeTokenKind.COMMENT, code.substring(i, end)));
        i = end;
        continue;
      }

      // 3. 字符串字面量 "..." / '...' / `...`
      if (ch === '"' || ch === '\'' || ch === '`') {
        flushPlain();
        const quote: string = ch;
        let j: number = i + 1;
        while (j < len) {
          const c: string = code.charAt(j);
          if (c === '\\') {
            j += 2;
            continue;
          }
          if (c === quote) {
            j++;
            break;
          }
          if (quote !== '`' && c === '\n') {
            break;
          }
          j++;
        }
        tokens.push(new CodeToken(CodeTokenKind.STRING, code.substring(i, j)));
        i = j;
        continue;
      }

      // 4. 装饰器 / 注解 @ComponentV2, @Local 等
      if (ch === '@' && i + 1 < len && CodeHighlighter.isIdentStart(code.charAt(i + 1))) {
        flushPlain();
        let j: number = i + 1;
        while (j < len && CodeHighlighter.isIdentPart(code.charAt(j))) {
          j++;
        }
        tokens.push(new CodeToken(CodeTokenKind.KEYWORD, code.substring(i, j)));
        i = j;
        continue;
      }

      // 5. 数字字面量
      if (CodeHighlighter.isDigit(ch) &&
        (i === 0 || !CodeHighlighter.isIdentPart(code.charAt(i - 1)))) {
        flushPlain();
        let j: number = i;
        if (ch === '0' && (next === 'x' || next === 'X')) {
          j += 2;
          while (j < len && CodeHighlighter.isHexDigit(code.charAt(j))) {
            j++;
          }
        } else {
          while (j < len && (CodeHighlighter.isDigit(code.charAt(j)) || code.charAt(j) === '.')) {
            j++;
          }
        }
        tokens.push(new CodeToken(CodeTokenKind.NUMBER, code.substring(i, j)));
        i = j;
        continue;
      }

      // 6. 标识符 / 关键字 / 类型
      if (CodeHighlighter.isIdentStart(ch)) {
        let j: number = i + 1;
        while (j < len && CodeHighlighter.isIdentPart(code.charAt(j))) {
          j++;
        }
        const word: string = code.substring(i, j);
        if (CodeHighlighter.KEYWORDS.has(word)) {
          flushPlain();
          tokens.push(new CodeToken(CodeTokenKind.KEYWORD, word));
        } else if (CodeHighlighter.BUILTIN_TYPES.has(word) ||
          (ch >= 'A' && ch <= 'Z' && word.length > 1)) {
          flushPlain();
          tokens.push(new CodeToken(CodeTokenKind.TYPE, word));
        } else {
          plainBuffer += word;
        }
        i = j;
        continue;
      }

      plainBuffer += ch;
      i++;
    }
    flushPlain();
    return tokens;
  }

  private static isIdentStart(ch: string): boolean {
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch === '_';
  }

  private static isIdentPart(ch: string): boolean {
    return CodeHighlighter.isIdentStart(ch) || CodeHighlighter.isDigit(ch);
  }

  private static isDigit(ch: string): boolean {
    return ch >= '0' && ch <= '9';
  }

  private static isHexDigit(ch: string): boolean {
    return CodeHighlighter.isDigit(ch) || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F');
  }
}
