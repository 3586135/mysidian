import markdownParserTest from './LocalUnit.test';
import wysiwygCodecTest from './WysiwygCodec.test';

export default function testsuite() {
  markdownParserTest();
  wysiwygCodecTest();
}
