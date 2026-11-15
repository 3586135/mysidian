import { describe, it, expect } from '@ohos/hypium';
import { CodeHighlighter, CodeToken, CodeTokenKind } from '@ohos/markdown';

export default function codeHighlighterTest() {
  describe('CodeHighlighterTest', () => {
    it('tokenizes ArkTS decorator, keyword, type, number, and string', 0, () => {
      const code: string = '@Local count: number = 42;\nconst title: string = "hello";';
      const tokens: CodeToken[] = CodeHighlighter.tokenize(code, 'arkts');
      const kinds: string[] = tokens.map((t: CodeToken): string => `${t.kind}:${t.text}`);
      expect(kinds.includes(`${CodeTokenKind.KEYWORD}:@Local`)).assertTrue();
      expect(kinds.includes(`${CodeTokenKind.TYPE}:number`)).assertTrue();
      expect(kinds.includes(`${CodeTokenKind.NUMBER}:42`)).assertTrue();
      expect(kinds.includes(`${CodeTokenKind.KEYWORD}:const`)).assertTrue();
      expect(kinds.includes(`${CodeTokenKind.STRING}:"hello"`)).assertTrue();
    });

    it('tokenizes single-line and block comments', 0, () => {
      const code: string = '// line comment\n/* block */ return true;';
      const tokens: CodeToken[] = CodeHighlighter.tokenize(code, 'ts');
      expect(tokens[0].kind).assertEqual(CodeTokenKind.COMMENT);
      expect(tokens[0].text).assertEqual('// line comment');
      expect(tokens[2].kind).assertEqual(CodeTokenKind.COMMENT);
      expect(tokens[2].text).assertEqual('/* block */');
    });

    it('tokenizes Python hash comments and def keyword', 0, () => {
      const code: string = '# py comment\ndef calc(x):\n  return 0x10';
      const tokens: CodeToken[] = CodeHighlighter.tokenize(code, 'python');
      expect(tokens[0].kind).assertEqual(CodeTokenKind.COMMENT);
      const hasDef: boolean = tokens.some(
        (t: CodeToken): boolean => t.kind === CodeTokenKind.KEYWORD && t.text === 'def');
      const hasHex: boolean = tokens.some(
        (t: CodeToken): boolean => t.kind === CodeTokenKind.NUMBER && t.text === '0x10');
      expect(hasDef).assertTrue();
      expect(hasHex).assertTrue();
    });

    it('preserves exact source text when re-concatenated', 0, () => {
      const code: string = 'export class Demo {\n  // test\n  public run(): Promise<void> {}\n}';
      const tokens: CodeToken[] = CodeHighlighter.tokenize(code, 'ets');
      const joined: string = tokens.map((t: CodeToken): string => t.text).join('');
      expect(joined).assertEqual(code);
    });
  });
}
