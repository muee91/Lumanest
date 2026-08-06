import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const serverSource = readFileSync(new URL('../src/server.mjs', import.meta.url), 'utf8');

test('assistant prompts require a decision-first answer contract', () => {
  assert.doesNotMatch(serverSource, /用中文单段回答/);
  assert.equal((serverSource.match(/首行必须是“结论｜/g) ?? []).length, 2);
  assert.match(serverSource, /最多3行“依据｜/);
  assert.match(serverSource, /最多2行“限制｜/);
  assert.match(serverSource, /1行“下一步｜/);
  assert.match(serverSource, /不要寒暄、复述问题/);
});
