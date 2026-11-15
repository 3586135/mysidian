import { describe, it, expect } from '@ohos/hypium';
import { FindReplaceUtils } from '../main/ets/viewmodel/FindReplaceUtils';

export default function findReplaceTest() {
  describe('FindReplaceUtilsTest', () => {
    it('findsAllNonOverlappingMatches', 0, () => {
      expect(FindReplaceUtils.findAll('aaaa', 'aa').join(',')).assertEqual('0,2');
      expect(FindReplaceUtils.findAll('abcabc', 'bc').join(',')).assertEqual('1,4');
    });

    it('ignoresCaseByDefault', 0, () => {
      expect(FindReplaceUtils.findAll('Foo foo FOO', 'foo').length).assertEqual(3);
      expect(FindReplaceUtils.findAll('Foo foo FOO', 'foo', true).length).assertEqual(1);
    });

    it('findsChineseKeyword', 0, () => {
      expect(FindReplaceUtils.findAll('欢迎使用，欢迎回来', '欢迎').join(',')).assertEqual('0,5');
    });

    it('returnsEmptyForBlankKeyword', 0, () => {
      expect(FindReplaceUtils.findAll('abc', '').length).assertEqual(0);
      expect(FindReplaceUtils.findAll('', 'a').length).assertEqual(0);
    });

    it('cyclesThroughMatches', 0, () => {
      expect(FindReplaceUtils.cycle(-1, 3, 1)).assertEqual(0);
      expect(FindReplaceUtils.cycle(-1, 3, -1)).assertEqual(2);
      expect(FindReplaceUtils.cycle(2, 3, 1)).assertEqual(0);
      expect(FindReplaceUtils.cycle(0, 3, -1)).assertEqual(2);
      expect(FindReplaceUtils.cycle(0, 0, 1)).assertEqual(-1);
    });

    it('replacesSingleMatch', 0, () => {
      expect(FindReplaceUtils.replaceAt('a-b-c', 1, 1, '+')).assertEqual('a+b-c');
      expect(FindReplaceUtils.replaceAt('abc', 9, 1, 'x')).assertEqual('abc');
    });

    it('replacesAllMatches', 0, () => {
      expect(FindReplaceUtils.replaceAll('a-b-c', '-', '--')).assertEqual('a--b--c');
      expect(FindReplaceUtils.replaceAll('Foo foo', 'foo', 'x')).assertEqual('x x');
      expect(FindReplaceUtils.replaceAll('abc', 'z', 'x')).assertEqual('abc');
    });
  });
}
