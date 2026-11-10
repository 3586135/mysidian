import { describe, it, expect } from '@ohos/hypium';
import { MdBlockType, MdInlineType, MdListItem } from '@ohos/domain';
import { MarkdownParser } from '../main/ets/parser/MarkdownParser';
import { DataViewQuery } from '../main/ets/parser/DataViewQuery';
import { TaskMetadata } from '../main/ets/parser/TaskMetadata';
import { MdInlineFlattener } from '../main/ets/render/MdInlineFlattener';
import { MermaidFlow } from '../main/ets/render/MermaidFlow';
import { MathRenderer } from '../main/ets/render/MathRenderer';

export default function markdownParserTest() {
  describe('MarkdownParserTest', () => {
    it('parsesHeading', 0, () => {
      const document = MarkdownParser.parse('# Title\n\ntext');
      expect(document.blocks.length).assertEqual(2);
      expect(document.blocks[0].type).assertEqual(MdBlockType.HEADING);
      expect(document.blocks[0].level).assertEqual(1);
      expect(document.blocks[0].inlines[0].text).assertEqual('Title');
      expect(document.title).assertEqual('Title');
    });

    it('parsesParagraphAndEmphasis', 0, () => {
      const document = MarkdownParser.parse('hello **world** and *italic*');
      const inlines = document.blocks[0].inlines;
      expect(document.blocks[0].type).assertEqual(MdBlockType.PARAGRAPH);
      expect(inlines.length).assertEqual(4);
      expect(inlines[1].type).assertEqual(MdInlineType.STRONG);
      expect(inlines[1].children[0].text).assertEqual('world');
      expect(inlines[3].type).assertEqual(MdInlineType.EMPHASIS);
    });

    it('parsesWikiLink', 0, () => {
      const document = MarkdownParser.parse('see [[Target Note]] and [[Other#Section|alias]]');
      const inlines = document.blocks[0].inlines;
      expect(inlines[1].type).assertEqual(MdInlineType.WIKI_LINK);
      expect(inlines[1].target).assertEqual('Target Note');
      expect(inlines[3].type).assertEqual(MdInlineType.WIKI_LINK);
      expect(inlines[3].target).assertEqual('Other');
      expect(inlines[3].heading).assertEqual('Section');
      expect(inlines[3].alias).assertEqual('alias');
    });

    it('parsesEmbed', 0, () => {
      // 独占一行的 ![[image.png]] 现在解析为图片块（见 parsesImageBlock）。
      const document = MarkdownParser.parse('正文 ![[image.png]] 结尾');
      expect(document.blocks[0].type).assertEqual(MdBlockType.PARAGRAPH);
      expect(document.blocks[0].inlines[1].type).assertEqual(MdInlineType.EMBED);
      expect(document.blocks[0].inlines[1].target).assertEqual('image.png');
    });

    it('parsesImageBlock', 0, () => {
      const document = MarkdownParser.parse('![[photo.png]]');
      expect(document.blocks.length).assertEqual(1);
      expect(document.blocks[0].type).assertEqual(MdBlockType.IMAGE);
      expect(document.blocks[0].target).assertEqual('photo.png');
    });

    it('parsesImageBlockWithWidth', 0, () => {
      const document = MarkdownParser.parse('![[photo.png|300]]');
      expect(document.blocks[0].type).assertEqual(MdBlockType.IMAGE);
      expect(document.blocks[0].target).assertEqual('photo.png');
      expect(document.blocks[0].imageWidth).assertEqual(300);
    });

    it('parsesMarkdownImageBlock', 0, () => {
      const document = MarkdownParser.parse('![说明](attachments/a.png)');
      expect(document.blocks.length).assertEqual(1);
      expect(document.blocks[0].type).assertEqual(MdBlockType.IMAGE);
      expect(document.blocks[0].target).assertEqual('attachments/a.png');
    });

    it('parsesEmbedBlockForNote', 0, () => {
      const document = MarkdownParser.parse('![[另一篇笔记]]');
      expect(document.blocks.length).assertEqual(1);
      expect(document.blocks[0].type).assertEqual(MdBlockType.EMBED);
      expect(document.blocks[0].target).assertEqual('另一篇笔记');
    });

    it('keepsInlineImageInsideParagraph', 0, () => {
      const document = MarkdownParser.parse('前缀 ![[photo.png]] 后缀');
      expect(document.blocks[0].type).assertEqual(MdBlockType.PARAGRAPH);
      expect(document.blocks[0].inlines[1].type).assertEqual(MdInlineType.EMBED);
    });

    it('flattensWikiLinkWithAnchor', 0, () => {
      const document = MarkdownParser.parse('see [[Target Note]] and [[Other#Section|alias]]');
      const first = MdInlineFlattener.flatten(document.blocks[0].inlines);
      expect(first[1].linkTarget).assertEqual('Target Note');
      expect(first[1].linkKind).assertEqual('wiki');
      // 锚点被拼回目标串，上层再拆分解析。
      expect(first[3].linkTarget).assertEqual('Other#Section');
    });

    it('flattensSamePageAnchor', 0, () => {
      const document = MarkdownParser.parse('[[#小节标题]]');
      const segments = MdInlineFlattener.flatten(document.blocks[0].inlines);
      expect(segments[0].linkTarget).assertEqual('#小节标题');
    });

    it('parsesTag', 0, () => {
      const document = MarkdownParser.parse('tag #project/alpha here');
      const inlines = document.blocks[0].inlines;
      expect(inlines[1].type).assertEqual(MdInlineType.TAG);
      expect(inlines[1].text).assertEqual('project/alpha');
    });

    it('parsesListAndTask', 0, () => {
      const document = MarkdownParser.parse('- first\n- [ ] todo\n- [x] done');
      const block = document.blocks[0];
      expect(block.type).assertEqual(MdBlockType.LIST);
      expect(block.items.length).assertEqual(3);
      expect(block.items[0].inlines[0].text).assertEqual('first');
      expect(block.items[1].isTask).assertEqual(true);
      expect(block.items[1].checked).assertEqual(false);
      expect(block.items[2].checked).assertEqual(true);
    });

    it('parsesCodeBlock', 0, () => {
      const document = MarkdownParser.parse('```ts\nconst a = 1;\n```');
      const block = document.blocks[0];
      expect(block.type).assertEqual(MdBlockType.CODE);
      expect(block.lang).assertEqual('ts');
      expect(block.rawContent).assertEqual('const a = 1;');
    });

    it('parsesTripleEmphasis', 0, () => {
      const document = MarkdownParser.parse('***粗斜体***');
      const inlines = document.blocks[0].inlines;
      expect(inlines[0].type).assertEqual(MdInlineType.STRONG);
      expect(inlines[0].children.length).assertEqual(1);
      expect(inlines[0].children[0].type).assertEqual(MdInlineType.EMPHASIS);
      expect(inlines[0].children[0].children[0].text).assertEqual('粗斜体');
    });

    it('rejectsEmphasisAfterSpace', 0, () => {
      const document = MarkdownParser.parse('3 * 4 * 5');
      const inlines = document.blocks[0].inlines;
      expect(inlines.length).assertEqual(1);
      expect(inlines[0].text).assertEqual('3 * 4 * 5');
    });

    it('parsesStrikethrough', 0, () => {
      const document = MarkdownParser.parse('~~已删除~~');
      expect(document.blocks[0].inlines[0].type).assertEqual(MdInlineType.STRIKETHROUGH);
    });

    it('parsesTableKeepingInlineSyntax', 0, () => {
      const document = MarkdownParser.parse('| **加粗** | `code` |\n| --- | :---: |\n| [[笔记]] | #标签 |');
      const block = document.blocks[0];
      expect(block.type).assertEqual(MdBlockType.TABLE);
      expect(block.headers[0]).assertEqual('**加粗**');
      expect(block.aligns[1]).assertEqual('center');
      expect(block.rows[0][0]).assertEqual('[[笔记]]');
    });

    it('parsesCallout', 0, () => {
      const document = MarkdownParser.parse('> [!warning] Careful\n> body');
      const block = document.blocks[0];
      expect(block.type).assertEqual(MdBlockType.CALLOUT);
      expect(block.calloutType).assertEqual('WARNING');
      expect(block.rawContent).assertEqual('Careful\nbody');
    });

    it('parsesQuote', 0, () => {
      const document = MarkdownParser.parse('> quoted text');
      expect(document.blocks[0].type).assertEqual(MdBlockType.QUOTE);
    });

    it('parsesTable', 0, () => {
      const document = MarkdownParser.parse('| a | b |\n| --- | ---: |\n| 1 | 2 |');
      const block = document.blocks[0];
      expect(block.type).assertEqual(MdBlockType.TABLE);
      expect(block.headers.length).assertEqual(2);
      expect(block.headers[0]).assertEqual('a');
      expect(block.aligns[1]).assertEqual('right');
      expect(block.rows.length).assertEqual(1);
      expect(block.rows[0][1]).assertEqual('2');
    });

    it('parsesFrontmatter', 0, () => {
      const document = MarkdownParser.parse(
        '---\ntitle: My Note\ntags: [a, b]\n---\n\n# Heading\n');
      expect(document.frontmatter.properties.length).assertEqual(2);
      expect(document.frontmatter.properties[0].key).assertEqual('title');
      expect(document.frontmatter.properties[0].value).assertEqual('My Note');
      expect(document.frontmatter.tags.length).assertEqual(2);
      expect(document.blocks.length).assertEqual(1);
      expect(document.title).assertEqual('My Note');
    });

    it('parsesFrontmatterInlineTags', 0, () => {
      const document = MarkdownParser.parse(
        '---\ntags: #知识库 #Obsidian #笔记管理 #实践记录\n---\n\n# Heading\n');
      expect(document.frontmatter.tags.length).assertEqual(4);
      expect(document.frontmatter.tags[0]).assertEqual('知识库');
      expect(document.frontmatter.tags[1]).assertEqual('Obsidian');
      expect(document.frontmatter.tags[2]).assertEqual('笔记管理');
      expect(document.frontmatter.tags[3]).assertEqual('实践记录');
    });

    it('parsesFrontmatterHashListTags', 0, () => {
      const document = MarkdownParser.parse('---\ntags:\n  - #a\n  - b\n---\n');
      expect(document.frontmatter.tags.length).assertEqual(2);
      expect(document.frontmatter.tags[0]).assertEqual('a');
      expect(document.frontmatter.tags[1]).assertEqual('b');
    });

    it('parsesFrontmatterTagsWithoutSpaces', 0, () => {
      const document = MarkdownParser.parse('---\ntags: #知识库#Obsidian#笔记管理\n---\n');
      expect(document.frontmatter.tags.length).assertEqual(3);
      expect(document.frontmatter.tags[0]).assertEqual('知识库');
      expect(document.frontmatter.tags[1]).assertEqual('Obsidian');
      expect(document.frontmatter.tags[2]).assertEqual('笔记管理');
    });

    it('parsesFrontmatterListItemsWithMultipleHashes', 0, () => {
      const document = MarkdownParser.parse('---\ntags:\n  - #a #b\n  - #c#d\n---\n');
      expect(document.frontmatter.tags.length).assertEqual(4);
      expect(document.frontmatter.tags[0]).assertEqual('a');
      expect(document.frontmatter.tags[1]).assertEqual('b');
      expect(document.frontmatter.tags[2]).assertEqual('c');
      expect(document.frontmatter.tags[3]).assertEqual('d');
    });

    it('parsesFrontmatterCommaSeparatedTags', 0, () => {
      const document = MarkdownParser.parse('---\ntags: 知识库, Obsidian，笔记管理\n---\n');
      expect(document.frontmatter.tags.length).assertEqual(3);
      expect(document.frontmatter.tags[0]).assertEqual('知识库');
      expect(document.frontmatter.tags[2]).assertEqual('笔记管理');
    });

    it('parsesThematicBreak', 0, () => {
      const document = MarkdownParser.parse('a\n\n---\n\nb');
      expect(document.blocks[0].type).assertEqual(MdBlockType.PARAGRAPH);
      expect(document.blocks[1].type).assertEqual(MdBlockType.THEMATIC_BREAK);
      expect(document.blocks[2].type).assertEqual(MdBlockType.PARAGRAPH);
    });

    it('parsesTaskMetadata', 0, () => {
      const item = new MdListItem();
      const rest = TaskMetadata.apply(item,
        '写周报 📅 2026-11-09 ⏳ 2026-11-08 ➕ 2026-11-01 🔁 every week ⏫');
      expect(item.dueDate).assertEqual('2026-11-09');
      expect(item.scheduledDate).assertEqual('2026-11-08');
      expect(item.createdDate).assertEqual('2026-11-01');
      expect(item.recurrence).assertEqual('every week');
      expect(item.priority).assertEqual('⏫');
      expect(rest).assertEqual('写周报');
    });

    it('togglesTaskDoneDate', 0, () => {
      const raw = '- [ ] 写周报 📅 2026-11-09';
      const checked = TaskMetadata.toggle(raw, true);
      expect(checked.startsWith('- [x] 写周报 📅 2026-11-09 ✅ ')).assertTrue();
      const unchecked = TaskMetadata.toggle(checked, false);
      expect(unchecked).assertEqual(raw);
    });

    it('togglesOrderedTask', 0, () => {
      const raw = '1. [ ] 任务';
      expect(TaskMetadata.toggle(raw, true).startsWith('1. [x] 任务 ✅ ')).assertTrue();
    });

    it('parsesDataViewTaskQuery', 0, () => {
      const query = DataViewQuery.parse(
        'TASK\nWHERE !completed AND contains(tags, "#task") ' +
        'AND file.name != this.file.name\nGROUP BY file.link');
      expect(query.isTaskQuery()).assertTrue();
      expect(query.requireIncomplete).assertTrue();
      expect(query.requireCompleted).assertFalse();
      expect(query.excludeCurrent).assertTrue();
      expect(query.groupByFile).assertTrue();
      expect(query.requiredTags.length).assertEqual(1);
      expect(query.requiredTags[0]).assertEqual('task');
      expect(query.matches('- [ ] 买菜 #task', false)).assertTrue();
      expect(query.matches('- [x] 买菜 #task', true)).assertFalse();
      expect(query.matches('- [ ] 买菜', false)).assertFalse();
    });

    it('parsesDataViewCompletedAndTextQuery', 0, () => {
      const query = DataViewQuery.parse(
        'TASK\nWHERE completed AND contains(text, "周报")');
      expect(query.requireCompleted).assertTrue();
      expect(query.containsText).assertEqual('周报');
      expect(query.matches('- [x] 写周报', true)).assertTrue();
      expect(query.matches('- [x] 开会', true)).assertFalse();
      expect(query.matches('- [ ] 写周报', false)).assertFalse();
    });

    it('parsesDataViewNonTaskQueryAsCode', 0, () => {
      const query = DataViewQuery.parse('TABLE file.size\nWHERE file.ext = "md"');
      expect(query.isTaskQuery()).assertFalse();
    });

    it('parsesDataViewLiveTableQuery', 0, () => {
      const query = DataViewQuery.parse('TABLE author, tags\nFROM #欢迎\nWHERE contains(tags, "指南")');
      expect(query.isTableQuery()).assertTrue();
      expect(query.live).assertTrue();
      expect(query.parsedOk).assertTrue();
      expect(query.fromTag).assertEqual('欢迎');
      expect(query.tableProps.length).assertEqual(2);
      expect(query.tableProps[0]).assertEqual('author');
      expect(query.tableColumns.length).assertEqual(3);
      expect(query.tableColumns[0]).assertEqual('File');
      expect(query.tableColumns[1]).assertEqual('author');
      expect(query.requiredTags.length).assertEqual(1);
      expect(query.requiredTags[0]).assertEqual('指南');
      expect(query.matchesPage('---\ntags: [欢迎, 指南]\n---\n正文', ['欢迎', '指南'], '欢迎.md', ''))
        .assertTrue();
      expect(query.matchesPage('正文 #欢迎', ['欢迎'], '欢迎.md', '')).assertFalse();
    });

    it('parsesDataViewLiveListQueryFromFolder', 0, () => {
      const query = DataViewQuery.parse('LIST\nFROM "示例"\nWHERE file.name != this.file.name');
      expect(query.isListQuery()).assertTrue();
      expect(query.live).assertTrue();
      expect(query.parsedOk).assertTrue();
      expect(query.fromFolder).assertEqual('示例');
      expect(query.excludeCurrent).assertTrue();
      expect(query.matchesPage('x', [], '示例/a.md', '')).assertTrue();
      expect(query.matchesPage('x', [], '其他/a.md', '')).assertFalse();
      expect(query.matchesPage('x', [], '示例/a.md', '示例/a.md')).assertFalse();
    });

    it('parsesDataViewListWithPropAndInlineFrom', 0, () => {
      const query = DataViewQuery.parse('LIST status FROM #任务');
      expect(query.live).assertTrue();
      expect(query.listProp).assertEqual('status');
      expect(query.fromTag).assertEqual('任务');
    });

    it('parsesDataViewTableWithoutId', 0, () => {
      const query = DataViewQuery.parse('TABLE WITHOUT ID author FROM #x');
      expect(query.withoutId).assertTrue();
      expect(query.tableColumns.length).assertEqual(1);
      expect(query.tableColumns[0]).assertEqual('author');
    });

    it('keepsStaticTableFallbackWithoutFrom', 0, () => {
      const query = DataViewQuery.parse('TABLE\n| a | b |\n| 1 | 2 |');
      expect(query.live).assertFalse();
      expect(query.parsedOk).assertTrue();
      expect(query.tableColumns.length).assertEqual(2);
      expect(query.tableRows.length).assertEqual(1);
      expect(query.tableRows[0][0]).assertEqual('1');
    });

    it('parsesMermaidGraphWithoutCrash', 0, () => {
      const graph = MermaidFlow.parse('graph TD\nA[开始] --> B[处理]\nB --> C[结束]');
      expect(graph.valid).assertTrue();
      expect(graph.nodes.length).assertEqual(3);
      expect(graph.nodes[0].label).assertEqual('开始');
      expect(graph.nodes[1].label).assertEqual('处理');
      expect(graph.edges.length).assertEqual(2);
    });

    it('keepsMermaidInvalidSourceSafe', 0, () => {
      const graph = MermaidFlow.parse('not a graph');
      expect(graph.valid).assertFalse();
      expect(graph.nodes.length).assertEqual(0);
    });

    it('rendersMathToPlainText', 0, () => {
      expect(MathRenderer.toPlain('a^2 + b^2 = c^2')).assertEqual('a² + b² = c²');
      expect(MathRenderer.toPlain('\\frac{1}{2}')).assertEqual('(1)/(2)');
      expect(MathRenderer.toPlain('\\sqrt{x}')).assertEqual('√(x)');
      expect(MathRenderer.toPlain('\\alpha + \\beta')).assertEqual('α + β');
    });

    it('flattensInlineMath', 0, () => {
      const document = MarkdownParser.parse('inline $x^2$ here');
      const segments = MdInlineFlattener.flatten(document.blocks[0].inlines);
      expect(segments[1].text).assertEqual('x²');
    });

    it('keepsFrontmatterKeysAfterListProperty', 0, () => {
      const document = MarkdownParser.parse(
        '---\nstatus: 进行中\ntags:\n  - 功能验证\ndue: 2026-11-20\n---\n\n# 标题');
      const properties = document.frontmatter.properties;
      expect(properties.length).assertEqual(3);
      expect(properties[0].key).assertEqual('status');
      expect(properties[1].key).assertEqual('tags');
      expect(properties[2].key).assertEqual('due');
      expect(properties[2].value).assertEqual('2026-11-20');
    });
  });
}
