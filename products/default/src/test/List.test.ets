import localUnitTest from './LocalUnit.test';
import findReplaceTest from './FindReplace.test';
import syncEngineTest from './SyncEngine.test';
import codeHighlighterTest from './CodeHighlighter.test';
import externalOpenTest from './ExternalOpen.test';

export default function testsuite() {
  localUnitTest();
  findReplaceTest();
  syncEngineTest();
  codeHighlighterTest();
  externalOpenTest();
}
