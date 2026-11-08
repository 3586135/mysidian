import { describe, it, expect } from '@ohos/hypium';
import { FuzzyMatcher } from '../main/ets/manager/FuzzyMatcher';
import { Tokenizer } from '../main/ets/indexer/Tokenizer';

export default function vaultUtilTest() {
  describe('VaultUtilTest', () => {
    it('tokenizesMixedText', 0, () => {
      const tokens: string[] = Tokenizer.tokenize('中文abc123');
      expect(tokens.length).assertEqual(3);
      expect(tokens[0]).assertEqual('中文');
      expect(tokens[1]).assertEqual('文');
      expect(tokens[2]).assertEqual('abc123');
    });

    it('buildsMatchExpression', 0, () => {
      expect(Tokenizer.buildMatchExpression('note')).assertEqual('note*');
      expect(Tokenizer.buildMatchExpression('my note')).assertEqual('my note*');
      expect(Tokenizer.buildMatchExpression('   ')).assertEqual('');
    });

    it('buildsTerms', 0, () => {
      expect(Tokenizer.buildTerms('Hello World')).assertEqual('hello world');
    });

    it('matchesSubstring', 0, () => {
      expect(FuzzyMatcher.score('note', 'My Note') > 0).assertTrue();
      expect(FuzzyMatcher.score('note', 'Notes') > 0).assertTrue();
    });

    it('rejectsNonMatch', 0, () => {
      expect(FuzzyMatcher.score('xyz', 'abc')).assertEqual(-1);
    });

    it('prefersPrefix', 0, () => {
      const prefix: number = FuzzyMatcher.score('note', 'Note.md');
      const middle: number = FuzzyMatcher.score('note', 'My Note.md');
      expect(prefix > middle).assertTrue();
    });
  });
}
