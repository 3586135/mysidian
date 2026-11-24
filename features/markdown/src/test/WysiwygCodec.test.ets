import { describe, it, expect } from '@ohos/hypium';
import { MarkdownParser } from '../main/ets/parser/MarkdownParser';
import { MdBlockType, MdPropType } from '@ohos/domain';
import { WysiwygCodec } from '../main/ets/editor/WysiwygCodec';
import { WysiwygBlockKind, WysiwygDocument, WysiwygInline, WysiwygSpanKind } from '../main/ets/editor/WysiwygModel';
import { WysiwygTableCodec, WysiwygTableData } from '../main/ets/editor/WysiwygTableCodec';
import { BlockTriggerResult, InlineTriggerResult, WysiwygTriggers } from '../main/ets/editor/WysiwygTriggers';

export default function wysiwygCodecTest() {
  describe('WysiwygCodecTest', () => {
    it('roundTripsFrontmatterHeadingsListsAndTasks', 0, () => {
      const md: string = [
        '---',
        'journal-date: 2026/11/02',
        'tags:',
        '  - daily',
        '  - review',
        '---',
        '',
        '# 今日计划',
        '',
        '包含 **加粗**、*斜体*、~~删除~~、==高亮== 与 `行内代码` 以及 [[另一篇笔记|别名]] 和 #效率。',
        '',
        '- 无序项',
        '  - 嵌套子项',
        '1. 有序一项',
        '2. 有序二项',
        '- [ ] 未完成待办 📅 2026-11-20',
        '- [x] 已完成待办',
        '',
        '> 引用说明',
        '',
        '---',
        '',
        '```ts',
        'const answer: number = 42;',
        '```'
      ].join('\n');

      const doc: WysiwygDocument = WysiwygCodec.parse(md);
      expect(doc.hasFrontmatter).assertTrue();
      expect(doc.frontmatterRaw.includes('journal-date: 2026/11/02')).assertTrue();
      expect(doc.paragraphs[0].kind).assertEqual(WysiwygBlockKind.HEADING);
      expect(doc.paragraphs[0].level).assertEqual(1);
      expect(doc.paragraphs[2].kind).assertEqual(WysiwygBlockKind.BULLET);
      expect(doc.paragraphs[3].indent).assertEqual(1);
      expect(doc.paragraphs[4].kind).assertEqual(WysiwygBlockKind.ORDERED);
      expect(doc.paragraphs[4].ordinal).assertEqual(1);
      expect(doc.paragraphs[6].kind).assertEqual(WysiwygBlockKind.TASK);
      expect(doc.paragraphs[6].checked).assertFalse();
      expect(doc.paragraphs[7].checked).assertTrue();
      expect(doc.paragraphs[8].kind).assertEqual(WysiwygBlockKind.QUOTE);
      expect(doc.paragraphs[9].kind).assertEqual(WysiwygBlockKind.HR);
      expect(doc.paragraphs[10].kind).assertEqual(WysiwygBlockKind.CODE);
      expect(doc.paragraphs[10].lang).assertEqual('ts');

      const out: string = WysiwygCodec.serialize(doc);
      const reparsed = MarkdownParser.parse(out);
      expect(reparsed.frontmatter.properties.length).assertEqual(2);
      expect(reparsed.frontmatter.properties[0].value).assertEqual('2026/11/02');
      expect(reparsed.frontmatter.properties[1].type).assertEqual(MdPropType.LIST);
      expect(reparsed.blocks[0].type).assertEqual(MdBlockType.HEADING);
      expect(reparsed.blocks[0].level).assertEqual(1);
      expect(reparsed.blocks.some((b) => b.type === MdBlockType.LIST && b.items.length >= 2)).assertTrue();
      expect(reparsed.blocks.some((b) => b.type === MdBlockType.QUOTE)).assertTrue();
      expect(reparsed.blocks.some((b) => b.type === MdBlockType.THEMATIC_BREAK)).assertTrue();
      expect(reparsed.blocks.some((b) => b.type === MdBlockType.CODE && b.lang === 'ts')).assertTrue();
      expect(out.includes('[[另一篇笔记|别名]]')).assertTrue();
      expect(out.includes('==高亮==')).assertTrue();
      expect(out.includes('`行内代码`')).assertTrue();
    });

    it('mergesAdjacentFormattedSpansAndMovesEdgeSpacesOutside', 0, () => {
      const doc: WysiwygDocument = WysiwygCodec.parse('测试');
      const p = doc.paragraphs[0];
      p.inlines = [];
      const s1 = WysiwygCodec.parseInlines('**foo**')[0];
      const s2 = s1.clone();
      s2.text = 'bar ';
      p.inlines.push(s1);
      p.inlines.push(s2);
      const out: string = WysiwygCodec.serialize(doc);
      expect(out).assertEqual('**foobar** ');
    });

    it('preservesDataviewMermaidImagesAndCallouts', 0, () => {
      const md: string = [
        '> [!TIP]- 技巧',
        '> 保持专注',
        '',
        '![[demo.png|320]]',
        '',
        '![[嵌入笔记]]',
        '',
        '```dataview',
        'TASK FROM #work',
        '```'
      ].join('\n');

      const doc: WysiwygDocument = WysiwygCodec.parse(md);
      expect(doc.paragraphs[0].kind).assertEqual(WysiwygBlockKind.CALLOUT);
      expect(doc.paragraphs[0].calloutType).assertEqual('TIP');
      expect(doc.paragraphs[0].calloutFolded).assertTrue();
      expect(doc.paragraphs[2].kind).assertEqual(WysiwygBlockKind.IMAGE);
      expect(doc.paragraphs[3].kind).assertEqual(WysiwygBlockKind.EMBED);
      expect(doc.paragraphs[4].kind).assertEqual(WysiwygBlockKind.CODE);
      expect(doc.paragraphs[4].lang).assertEqual('dataview');

      const out: string = WysiwygCodec.serialize(doc);
      expect(out.includes('> [!TIP]- 技巧')).assertTrue();
      expect(out.includes('![[demo.png|320]]')).assertTrue();
      expect(out.includes('![[嵌入笔记]]')).assertTrue();
      expect(out.includes('```dataview\nTASK FROM #work\n```')).assertTrue();
    });

    it('keepsConsecutiveCodeBlocksSeparateOnRoundTrip', 0, () => {
      const md: string = [
        '```dataview',
        'LIST',
        'FROM #示例',
        '```',
        '',
        '```dataview',
        'TABLE author, tags',
        'FROM #欢迎',
        '```'
      ].join('\n');

      const doc: WysiwygDocument = WysiwygCodec.parse(md);
      expect(doc.paragraphs.length).assertEqual(4);
      expect(doc.paragraphs[0].blockGroupId !== doc.paragraphs[2].blockGroupId).assertTrue();
      const out: string = WysiwygCodec.serialize(doc);
      expect(out).assertEqual(md);
    });

    it('matchesLiveBlockAndInlineTriggers', 0, () => {
      const h2: BlockTriggerResult | null = WysiwygTriggers.matchBlockPrefix('## ');
      expect(h2 !== null).assertTrue();
      expect(h2 !== null && h2.kind === WysiwygBlockKind.HEADING && h2.level === 2).assertTrue();

      const task: BlockTriggerResult | null = WysiwygTriggers.matchBlockPrefix('- [ ] ');
      expect(task !== null && task.kind === WysiwygBlockKind.TASK && !task.checked).assertTrue();

      const shortTask: BlockTriggerResult | null = WysiwygTriggers.matchBlockPrefix('[] ');
      expect(shortTask !== null && shortTask.kind === WysiwygBlockKind.TASK).assertTrue();

      const ordered: BlockTriggerResult | null = WysiwygTriggers.matchBlockPrefix('3. ');
      expect(ordered !== null && ordered.kind === WysiwygBlockKind.ORDERED && ordered.ordinal === 3).assertTrue();

      const codeEnter: BlockTriggerResult | null = WysiwygTriggers.matchEnterBlock('```arkts');
      expect(codeEnter !== null && codeEnter.kind === WysiwygBlockKind.CODE && codeEnter.lang === 'arkts')
        .assertTrue();

      const bold: InlineTriggerResult | null = WysiwygTriggers.matchInlineSyntax('你好 **世界**');
      expect(bold !== null && bold.bold && bold.text === '世界' && bold.startOffset === 3).assertTrue();

      // **加粗 未闭合时不误判为 *斜体*
      const halfBold: InlineTriggerResult | null = WysiwygTriggers.matchInlineSyntax('**world*');
      expect(halfBold === null).assertTrue();

      const italic: InlineTriggerResult | null = WysiwygTriggers.matchInlineSyntax('前文 *斜体*');
      expect(italic !== null && italic.italic && !italic.bold && italic.text === '斜体').assertTrue();

      const wiki: InlineTriggerResult | null = WysiwygTriggers.matchInlineSyntax('参考 [[笔记A|显示名]]');
      expect(wiki !== null && wiki.kind === WysiwygSpanKind.WIKI_LINK && wiki.text === '显示名').assertTrue();

      const tag: InlineTriggerResult | null = WysiwygTriggers.matchInlineSyntax('分类 #工作/项目 ');
      expect(tag !== null && tag.kind === WysiwygSpanKind.TAG && tag.target === '工作/项目').assertTrue();
    });

    it('mapsCaretPositionsBetweenWysiwygAndSource', 0, () => {
      const md: string = [
        '---',
        'tag: test',
        '---',
        '',
        '# 大标题',
        '',
        '普通段落 **加粗** 尾部'
      ].join('\n');
      const doc: WysiwygDocument = WysiwygCodec.parse(md);
      const srcOffsetAtHeadingEnd: number = WysiwygCodec.sourceOffsetFromWysiwyg(doc, 0, 3);
      expect(md.substring(0, srcOffsetAtHeadingEnd).endsWith('# 大标题')).assertTrue();

      const srcAtParaWord: number = md.indexOf('尾部');
      const wysiwygPos: number = WysiwygCodec.wysiwygOffsetFromSource(md, srcAtParaWord);
      expect(wysiwygPos).assertEqual('大标题\n普通段落 加粗 '.length);
      const roundBack: number = WysiwygCodec.sourceOffsetFromWysiwyg(doc, 1, wysiwygPos - '大标题\n'.length);
      expect(roundBack).assertEqual(srcAtParaWord);

      // 拆分后的相邻加粗片段，源码映射不额外膨胀标记长度导致串行到下一段
      const multiDoc: WysiwygDocument = WysiwygCodec.parse('**BoldWord**N**ormalWord**\n\n## 列表');
      const splitBold: WysiwygInline = new WysiwygInline();
      splitBold.text = 'Bold';
      splitBold.bold = true;
      const splitBold2: WysiwygInline = new WysiwygInline();
      splitBold2.text = 'Word';
      splitBold2.bold = true;
      multiDoc.paragraphs[0].inlines = [splitBold, splitBold2].concat(multiDoc.paragraphs[0].inlines.slice(1));
      const endOfPara0: number = WysiwygCodec.sourceOffsetFromWysiwyg(multiDoc, 0, 'BoldWordNormalWord'.length);
      const listHeadingSrc: number = '**BoldWord**N**ormalWord**\n\n'.length;
      expect(endOfPara0).assertEqual(listHeadingSrc - 2);
      expect(WysiwygCodec.wysiwygOffsetFromSource('**BoldWord**N**ormalWord**\n\n## 列表', endOfPara0))
        .assertEqual('BoldWordNormalWord'.length);
    });

    it('roundTripsExplicitBlankLinesWithoutGrowth', 0, () => {
      // 显式空行（连续 2 个及以上）往返必须逐字稳定；此前每轮序列化会让空行倍增（数据损坏）。
      const md: string = '第一段\n\n\n\n中间隔两行\n\n尾段';
      const doc: WysiwygDocument = WysiwygCodec.parse(md);
      const once: string = WysiwygCodec.serialize(doc);
      expect(once).assertEqual(md);
      const twice: string = WysiwygCodec.serialize(WysiwygCodec.parse(once));
      expect(twice).assertEqual(md);
    });

    it('roundTripsVisualTableAndMapsCaretAcrossTable', 0, () => {
      const md: string = [
        '前置段落',
        '',
        '| 列1 | 列2 | 列3 |',
        '| :--- | :---: | ---: |',
        '| A \\| B | `x|y` | 100 |',
        '',
        '后续段落 结尾'
      ].join('\n');
      const doc: WysiwygDocument = WysiwygCodec.parse(md);
      expect(doc.paragraphs.length).assertEqual(3);
      expect(doc.paragraphs[1].kind).assertEqual(WysiwygBlockKind.TABLE);
      expect(doc.paragraphs[1].inlines.length).assertEqual(1);
      expect(doc.paragraphs[1].inlines[0].isImage).assertTrue();
      expect(WysiwygCodec.wysiwygParagraphPlainText(doc.paragraphs[1])).assertEqual(' ');
      expect(WysiwygCodec.serialize(doc)).assertEqual(md);

      // 光标映射到表格之后应精准跨过整块表格 Markdown 长度
      const tailSrc: number = md.indexOf('结尾');
      const tailWysiwyg: number = WysiwygCodec.wysiwygOffsetFromSource(md, tailSrc);
      expect(tailWysiwyg).assertEqual('前置段落\n \n后续段落 '.length);
      const backToSrc: number = WysiwygCodec.sourceOffsetFromWysiwyg(doc, 2, '后续段落 '.length);
      expect(backToSrc).assertEqual(tailSrc);
    });

    it('parsesMathBlockFirstLineContent', 0, () => {
      // 开栏 $$ 与内容同行：首行内容不得被吞。
      const doc: WysiwygDocument = WysiwygCodec.parse('$$x = 1\ny = 2$$');
      expect(doc.paragraphs.length).assertEqual(2);
      expect(doc.paragraphs[0].kind).assertEqual(WysiwygBlockKind.MATH);
      expect(doc.paragraphs[1].kind).assertEqual(WysiwygBlockKind.MATH);
      expect(WysiwygCodec.wysiwygParagraphPlainText(doc.paragraphs[0])).assertEqual('x = 1');
      expect(WysiwygCodec.wysiwygParagraphPlainText(doc.paragraphs[1])).assertEqual('y = 2');

      // 单行块 $$...$$ 保持原行为。
      const single: WysiwygDocument = WysiwygCodec.parse('$$x = 1$$');
      expect(single.paragraphs.length).assertEqual(1);
      expect(WysiwygCodec.wysiwygParagraphPlainText(single.paragraphs[0])).assertEqual('x = 1');
    });

    it('parsesEditsAndSerializesStructuredTableData', 0, () => {
      const cells: string[] = WysiwygTableCodec.splitRow('| A \\| B | `x|y` | **C** |');
      expect(cells.length).assertEqual(3);
      expect(cells[0]).assertEqual('A | B');
      expect(cells[1]).assertEqual('`x|y`');
      expect(cells[2]).assertEqual('**C**');

      expect(WysiwygTableCodec.isDelimiterLine('| :--- | :---: | ---: |')).assertTrue();
      expect(WysiwygTableCodec.isDelimiterLine('| ordinary | row |')).assertFalse();

      const table: WysiwygTableData = WysiwygTableCodec.parseFromMarkdown([
        '| 名称 | 状态 | 分值 |',
        '| :--- | :---: | ---: |',
        '| 甲 | ✅ | 99 |'
      ].join('\n'));
      expect(table.aligns[0]).assertEqual('left');
      expect(table.aligns[1]).assertEqual('center');
      expect(table.aligns[2]).assertEqual('right');

      WysiwygTableCodec.cycleAlign(table, 0);
      expect(table.aligns[0]).assertEqual('center');
      WysiwygTableCodec.appendRow(table);
      expect(table.rows.length).assertEqual(2);
      table.rows[1][0] = 'a|b';
      table.rows[1][1] = '`c|d`';
      WysiwygTableCodec.appendColumn(table);
      expect(table.headers.length).assertEqual(4);
      WysiwygTableCodec.removeColumn(table, 3);
      expect(table.headers.length).assertEqual(3);

      const outMd: string = WysiwygTableCodec.toMarkdown(table);
      expect(outMd.includes(':---:')).assertTrue();
      expect(outMd.includes('a\\|b')).assertTrue();
      expect(outMd.includes('`c|d`')).assertTrue();
    });

    it('parsesOrderedListTriggersAndIncrementingSequences', 0, () => {
      const t1: BlockTriggerResult | null = WysiwygTriggers.matchBlockPrefix('1. ');
      expect(t1 !== null).assertTrue();
      expect(t1?.kind).assertEqual(WysiwygBlockKind.ORDERED);
      expect(t1?.ordinal).assertEqual(1);
      expect(t1?.orderedDelimiter).assertEqual('.');

      const t3: BlockTriggerResult | null = WysiwygTriggers.matchBlockPrefix('3) ');
      expect(t3 !== null).assertTrue();
      expect(t3?.kind).assertEqual(WysiwygBlockKind.ORDERED);
      expect(t3?.ordinal).assertEqual(3);
      expect(t3?.orderedDelimiter).assertEqual(')');

      const orderedMd: string = '1. First\n2. Second\n3. Third';
      const orderedDoc: WysiwygDocument = WysiwygCodec.parse(orderedMd);
      expect(orderedDoc.paragraphs.length).assertEqual(3);
      expect(orderedDoc.paragraphs[0].ordinal).assertEqual(1);
      expect(orderedDoc.paragraphs[1].ordinal).assertEqual(2);
      expect(orderedDoc.paragraphs[2].ordinal).assertEqual(3);
      expect(WysiwygCodec.serialize(orderedDoc)).assertEqual(orderedMd);
    });

    it('roundTripsInlineEscapesWithoutSemanticLoss', 0, () => {
      // \*a\* 的字面星号往返不得退化成斜体（此前 InlineParser 丢 \ 且序列化不还原）。
      const md: string = '前文 \\*a\\* 后文';
      const doc: WysiwygDocument = WysiwygCodec.parse(md);
      const inline = doc.paragraphs[0].inlines[0];
      expect(inline.kind).assertEqual(WysiwygSpanKind.PLAIN);
      expect(inline.italic).assertFalse();
      expect(inline.text.includes('前文')).assertTrue();

      const out: string = WysiwygCodec.serialize(doc);
      expect(out).assertEqual(md);
      const twice: string = WysiwygCodec.serialize(WysiwygCodec.parse(out));
      expect(twice).assertEqual(md);

      // 所见模式键入的字面星号同样受转义协议保护。
      const typed: WysiwygDocument = WysiwygCodec.parse('占位');
      const typedInline = new WysiwygInline();
      typedInline.text = '*a*';
      typed.paragraphs[0].inlines = [typedInline];
      const typedOut: string = WysiwygCodec.serialize(typed);
      expect(typedOut).assertEqual('\\*a\\*');
      const reparsed: WysiwygDocument = WysiwygCodec.parse(typedOut);
      expect(reparsed.paragraphs[0].inlines[0].kind).assertEqual(WysiwygSpanKind.PLAIN);
      expect(reparsed.paragraphs[0].inlines[0].text).assertEqual('*a*');
    });

    it('keepsBackslashRunsAndWindowsPathsStable', 0, () => {
      // 反斜杠+字母不是转义（CommonMark），原样保留不膨胀。
      const md: string = '路径 C:\\Users\\song\\notes 保持不变';
      const doc: WysiwygDocument = WysiwygCodec.parse(md);
      expect(doc.paragraphs[0].inlines[0].text).assertEqual('路径 C:\\Users\\song\\notes 保持不变');
      expect(WysiwygCodec.serialize(doc)).assertEqual(md);
      expect(WysiwygCodec.serialize(WysiwygCodec.parse(WysiwygCodec.serialize(doc)))).assertEqual(md);

      // 字面反斜杠+标点（源码 \\*）与结尾反斜杠（后随样式标记）必须转义防吞。
      const tricky: WysiwygDocument = WysiwygCodec.parse('占位');
      const trickyInline = new WysiwygInline();
      trickyInline.text = 'a\\*b\\';
      tricky.paragraphs[0].inlines = [trickyInline];
      const boldInline = new WysiwygInline();
      boldInline.text = '粗';
      boldInline.bold = true;
      tricky.paragraphs[0].inlines.push(boldInline);
      const trickyOut: string = WysiwygCodec.serialize(tricky);
      expect(trickyOut).assertEqual('a\\\\\\*b\\\\**粗**');
      const trickyBack: WysiwygDocument = WysiwygCodec.parse(trickyOut);
      expect(trickyBack.paragraphs[0].inlines[0].text).assertEqual('a\\*b\\');
      expect(trickyBack.paragraphs[0].inlines[1].bold).assertTrue();
    });

    it('escapesMathDollarTildeAndExclaimEdges', 0, () => {
      // 成对 $ 会形成行内数学、成对 ~~ 形成删除线、末尾 ! 紧跟 wiki 链接会变嵌入。
      const doc: WysiwygDocument = WysiwygCodec.parse('占位');
      const plain = new WysiwygInline();
      plain.text = 'a $5$ b ~~c~~ d!';
      const wiki = WysiwygCodec.parseInlines('[[目标]]')[0];
      doc.paragraphs[0].inlines = [plain, wiki];

      const out: string = WysiwygCodec.serialize(doc);
      expect(out).assertEqual('a \\$5\\$ b \\~~c\\~~ d\\![[目标]]');

      const back: WysiwygDocument = WysiwygCodec.parse(out);
      expect(back.paragraphs[0].inlines[0].kind).assertEqual(WysiwygSpanKind.PLAIN);
      expect(back.paragraphs[0].inlines[0].text).assertEqual('a $5$ b ~~c~~ d!');
      expect(back.paragraphs[0].inlines[1].kind).assertEqual(WysiwygSpanKind.WIKI_LINK);
      expect(WysiwygCodec.serialize(back)).assertEqual(out);

      // 被转义的 \! 不得触发嵌入检测（\![[x]] = 字面 ! + wiki 链接）；
      // 真实未转义的 !（\\![[x]]）仍解析为嵌入。
      const escapedBang: WysiwygInline[] = WysiwygCodec.parseInlines('前 \\![[目标]]');
      expect(escapedBang[0].text).assertEqual('前 !');
      expect(escapedBang[1].kind).assertEqual(WysiwygSpanKind.WIKI_LINK);
      const realBang: WysiwygInline[] = WysiwygCodec.parseInlines('前 \\\\![[目标]]');
      expect(realBang[0].text).assertEqual('前 \\');
      expect(realBang[1].kind).assertEqual(WysiwygSpanKind.PLAIN);
      expect(realBang[1].text).assertEqual('![[目标]]');
    });

    it('keepsBlockTriggerLeadingCharsAsParagraph', 0, () => {
      const cases: string[] = ['- item', '1. item', '> quote', '# 标题', '| a |', '<div>x'];
      const expected: string[] =
        ['\\- item', '1\\. item', '\\> quote', '\\# 标题', '\\| a |', '\\<div>x'];
      for (let i = 0; i < cases.length; i++) {
        const doc: WysiwygDocument = WysiwygCodec.parse('占位');
        const inline = new WysiwygInline();
        inline.text = cases[i];
        doc.paragraphs[0].inlines = [inline];
        const out: string = WysiwygCodec.serialize(doc);
        expect(out).assertEqual(expected[i]);
        const back: WysiwygDocument = WysiwygCodec.parse(out);
        expect(back.paragraphs[0].kind).assertEqual(WysiwygBlockKind.PARAGRAPH);
        expect(WysiwygCodec.serialize(back)).assertEqual(out);
      }
    });

    it('keepsNaturalTextAndInlineStylesUntouched', 0, () => {
      // 自然文本零扰动：x = 1、a ~ b、snake_case、中文标点不得被加转义。
      const md: string = 'x = 1 与 a ~ b 与 snake_case 与 你好，世界！ 保持原样 **加粗** 依旧。';
      const out: string = WysiwygCodec.serialize(WysiwygCodec.parse(md));
      expect(out).assertEqual(md);
    });
  });
}
