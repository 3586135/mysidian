import { describe, it, expect } from '@ohos/hypium';
import { MdDocument, OutlineEntry } from '@ohos/domain';
import { MarkdownParser } from '@ohos/markdown';
import { IndexPipeline, VaultManager } from '@ohos/vault';

export default function externalOpenTest() {
  describe('ExternalMarkdownOpenTest', () => {
    it('extracts file name from encoded external uri and strips query', 0, () => {
      const encoded: string = 'content://com.provider/docs/%E6%B5%8B%E8%AF%95%E7%AC%94%E8%AE%B0.md?mime=text/markdown';
      expect(VaultManager.extractUriFileName(encoded)).assertEqual('测试笔记.md');
      expect(VaultManager.extractUriFileName('/sdcard/Documents/readme.markdown')).assertEqual('readme.markdown');
      expect(VaultManager.extractUriFileName('   ')).assertEqual('外部笔记.md');
    });

    it('collects in-memory outline and deduplicated tags for external readonly preview', 0, () => {
      const md: string = '---\nauthor: tester\ntags:\n  - 外部打开\n---\n# 一级标题\n正文包含 #HarmonyOS #Markdown #外部打开\n## 二级清单\n- [ ] 任务包含 #待办\n';
      const doc: MdDocument = MarkdownParser.parse(md);
      const outline: OutlineEntry[] = IndexPipeline.collectOutline(doc);
      expect(outline.length).assertEqual(2);
      expect(outline[0].level).assertEqual(1);
      expect(outline[0].text).assertEqual('一级标题');
      expect(outline[1].level).assertEqual(2);
      expect(outline[1].text).assertEqual('二级清单');

      const tags: string[] = IndexPipeline.collectTags(doc);
      expect(tags.includes('外部打开')).assertTrue();
      expect(tags.includes('harmonyos')).assertTrue();
      expect(tags.includes('markdown')).assertTrue();
      expect(tags.includes('待办')).assertTrue();
    });
  });
}
