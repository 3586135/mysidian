import { describe, it, expect } from '@ohos/hypium';
import { MdBlockType, MdInlineType } from '@ohos/domain';
import { MarkdownParser } from '../main/ets/parser/MarkdownParser';

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
      const document = MarkdownParser.parse('![[image.png]]');
      expect(document.blocks[0].inlines[0].type).assertEqual(MdInlineType.EMBED);
      expect(document.blocks[0].inlines[0].target).assertEqual('image.png');
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

    it('parsesThematicBreak', 0, () => {
      const document = MarkdownParser.parse('a\n\n---\n\nb');
      expect(document.blocks[0].type).assertEqual(MdBlockType.PARAGRAPH);
      expect(document.blocks[1].type).assertEqual(MdBlockType.THEMATIC_BREAK);
      expect(document.blocks[2].type).assertEqual(MdBlockType.PARAGRAPH);
    });
  });
}
