import localUnitTest from './LocalUnit.test';
import findReplaceTest from './FindReplace.test';
import syncEngineTest from './SyncEngine.test';

export default function testsuite() {
  localUnitTest();
  findReplaceTest();
  syncEngineTest();
}
