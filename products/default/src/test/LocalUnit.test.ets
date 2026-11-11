import { describe, it, expect } from '@ohos/hypium';
import { CompletionCandidate, EditorTextUtils, ListContinuation } from '../main/ets/viewmodel/EditorTextUtils';

export default function editorTextUtilsTest() {
  describe('EditorTextUtilsTest', () => {
    it('continuesUnorderedList', 0, () => {
      const result: ListContinuation | null =
        EditorTextUtils.computeListContinuation('- item', '- item\n', 6);
      expect(result !== null).assertTrue();
      if (result !== null) {
        expect(result.endList).assertFalse();
        expect(result.insertText).assertEqual('- ');
        expect(result.deleteFrom).assertEqual(7);
      }
    });

    it('continuesOrderedListWithNextOrdinal', 0, () => {
      const result: ListContinuation | null =
        EditorTextUtils.computeListContinuation('1. item', '1. item\n', 7);
      expect(result !== null).assertTrue();
      if (result !== null) {
        expect(result.insertText).assertEqual('2. ');
      }
    });

    it('continuesTaskList', 0, () => {
      const result: ListContinuation | null =
        EditorTextUtils.computeListContinuation('- [ ] todo', '- [ ] todo\n', 10);
      expect(result !== null).assertTrue();
      if (result !== null) {
        expect(result.insertText).assertEqual('- [ ] ');
      }
    });

    it('endsListOnEmptyItem', 0, () => {
      const result: ListContinuation | null =
        EditorTextUtils.computeListContinuation('text\n- ', 'text\n- \n', 7);
      expect(result !== null).assertTrue();
      if (result !== null) {
        expect(result.endList).assertTrue();
        expect(result.deleteFrom).assertEqual(5);
        expect(result.deleteTo).assertEqual(8);
      }
    });

    it('ignoresPlainParagraph', 0, () => {
      const result: ListContinuation | null =
        EditorTextUtils.computeListContinuation('普通文本', '普通文本\n', 4);
      expect(result === null).assertTrue();
    });

    it('ignoresMultiCharacterChange', 0, () => {
      const result: ListContinuation | null =
        EditorTextUtils.computeListContinuation('- item', '- itemabc', 9);
      expect(result === null).assertTrue();
    });

    it('ignoresNonNewlineInsertion', 0, () => {
      const result: ListContinuation | null =
        EditorTextUtils.computeListContinuation('- item', '- itemx', 7);
      expect(result === null).assertTrue();
    });

    it('findsWikiCompletionCandidates', 0, () => {
      const titles: string[] = ['笔记甲', '笔记乙', '其他'];
      const candidates: CompletionCandidate[] =
        EditorTextUtils.getWikiCompletionCandidates('见 [[笔记', 5, titles);
      expect(candidates.length).assertEqual(2);
      expect(candidates[0].title).assertEqual('笔记甲');
      // 候选项整体替换已输入的查询串，因此插入文本是完整标题 + 右括号。
      expect(candidates[0].insertText).assertEqual('笔记甲]]');
      expect(candidates[0].replaceFrom).assertEqual(3);
    });

    it('returnsNoCandidatesOutsideWikiLink', 0, () => {
      const titles: string[] = ['笔记甲'];
      const candidates: CompletionCandidate[] =
        EditorTextUtils.getWikiCompletionCandidates('普通文本', 4, titles);
      expect(candidates.length).assertEqual(0);
    });

    it('returnsNoCandidatesForClosedLink', 0, () => {
      const titles: string[] = ['笔记甲'];
      const candidates: CompletionCandidate[] =
        EditorTextUtils.getWikiCompletionCandidates('[[笔记甲]]', 8, titles);
      expect(candidates.length).assertEqual(0);
    });

    it('limitsCandidateCount', 0, () => {
      const titles: string[] = ['a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7', 'a8', 'a9', 'a10'];
      const candidates: CompletionCandidate[] =
        EditorTextUtils.getWikiCompletionCandidates('[[a', 3, titles);
      expect(candidates.length).assertEqual(8);
    });

    it('matchesContainsAfterPrefix', 0, () => {
      const titles: string[] = ['2026-读书笔记', '读书笔记'];
      const candidates: CompletionCandidate[] =
        EditorTextUtils.getWikiCompletionCandidates('[[读书', 4, titles);
      expect(candidates.length).assertEqual(2);
      // 前缀命中排在前面。
      expect(candidates[0].title).assertEqual('读书笔记');
      expect(candidates[0].insertText).assertEqual('读书笔记]]');
      // 包含命中排在后面，补全时整体替换已输入的查询串。
      expect(candidates[1].title).assertEqual('2026-读书笔记');
      expect(candidates[1].insertText).assertEqual('2026-读书笔记]]');
      expect(candidates[1].replaceFrom).assertEqual(2);
    });

    it('findsTagCompletionCandidates', 0, () => {
      const tags: string[] = ['语法', '示例'];
      const candidates: CompletionCandidate[] =
        EditorTextUtils.getTagCompletionCandidates('正文 #语', 5, tags);
      expect(candidates.length).assertEqual(1);
      expect(candidates[0].title).assertEqual('语法');
      expect(candidates[0].insertText).assertEqual('语法');
      expect(candidates[0].replaceFrom).assertEqual(3);
    });

    it('returnsNoTagCandidatesWithoutHash', 0, () => {
      const tags: string[] = ['语法'];
      const candidates: CompletionCandidate[] =
        EditorTextUtils.getTagCompletionCandidates('普通文本', 4, tags);
      expect(candidates.length).assertEqual(0);
    });
  });
}
