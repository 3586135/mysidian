import { describe, it, expect } from '@ohos/hypium';
import { FuzzyMatcher } from '../main/ets/manager/FuzzyMatcher';
import { Tokenizer } from '../main/ets/indexer/Tokenizer';
import { LinkRewriter } from '../main/ets/manager/LinkRewriter';
import { AttachmentResolver } from '../main/ets/manager/AttachmentResolver';

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

    it('rewritesPlainWikiLink', 0, () => {
      expect(LinkRewriter.rewriteWikiLinks('见 [[旧名]] 结束', '旧名', '新名'))
        .assertEqual('见 [[新名]] 结束');
    });

    it('rewritesWikiLinkWithAlias', 0, () => {
      expect(LinkRewriter.rewriteWikiLinks('[[旧名|显示名]]', '旧名', '新名'))
        .assertEqual('[[新名|显示名]]');
    });

    it('rewritesWikiLinkWithAnchor', 0, () => {
      expect(LinkRewriter.rewriteWikiLinks('[[旧名#小节]]', '旧名', '新名'))
        .assertEqual('[[新名#小节]]');
    });

    it('keepsUnrelatedLinks', 0, () => {
      expect(LinkRewriter.rewriteWikiLinks('[[旧名后缀]] 与 [[别的]]', '旧名', '新名'))
        .assertEqual('[[旧名后缀]] 与 [[别的]]');
    });

    it('keepsTextWithoutLinks', 0, () => {
      expect(LinkRewriter.rewriteWikiLinks('普通正文 旧名', '旧名', '新名'))
        .assertEqual('普通正文 旧名');
    });

    it('rewritesCaseInsensitively', 0, () => {
      expect(LinkRewriter.rewriteWikiLinks('[[oldname]]', 'OldName', '新名'))
        .assertEqual('[[新名]]');
    });

    it('escapesRegexMetaCharacters', 0, () => {
      expect(LinkRewriter.rewriteWikiLinks('[[a.b*c]]', 'a.b*c', 'ok'))
        .assertEqual('[[ok]]');
    });

    it('resolvesAttachmentByRelativePath', 0, () => {
      const files: string[] = ['attachments/a.png', 'b.md'];
      expect(AttachmentResolver.resolve('attachments/a.png', 'b.md', files))
        .assertEqual('attachments/a.png');
    });

    it('resolvesAttachmentByBaseName', 0, () => {
      const files: string[] = ['attachments/a.png', 'b.md'];
      expect(AttachmentResolver.resolve('a.png', 'b.md', files))
        .assertEqual('attachments/a.png');
    });

    it('resolvesAttachmentRelativeToNoteDirectory', 0, () => {
      const files: string[] = ['sub/a.png', 'b.md'];
      expect(AttachmentResolver.resolve('a.png', 'sub/b.md', files))
        .assertEqual('sub/a.png');
    });

    it('returnsEmptyForMissingAttachment', 0, () => {
      const files: string[] = ['b.md'];
      expect(AttachmentResolver.resolve('missing.png', 'b.md', files)).assertEqual('');
    });
  });
}
