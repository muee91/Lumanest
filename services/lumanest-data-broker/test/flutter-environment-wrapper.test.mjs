import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

test('Flutter wrapper keeps unit tests hermetic and requires explicit configured tests', async () => {
  const script = await readFile(
    new URL('../../../tool/flutter_with_environment.sh', import.meta.url),
    'utf8',
  );

  assert.match(script, /build\|run\|drive\|test-configured\)/);
  assert.match(script, /\*\)\n[\s\S]*?flutter "\$@"\n[\s\S]*?exit/);
  assert.match(
    script,
    /test-configured\)\n[\s\S]*?flutter test "\$@" --dart-define-from-file="\$safe_file"/,
  );
  assert.doesNotMatch(script, /build\|run\|test\|drive\)/);
});
