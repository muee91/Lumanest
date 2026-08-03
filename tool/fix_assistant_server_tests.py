from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "services/lumanest-data-broker/test/server.test.mjs"

text = PATH.read_text(encoding="utf-8")
text = text.replace(
    "test('assistant keeps environment facts and place data out of normal model prompts', async () => {",
    "test('assistant exposes only bounded Broker context without raw location fields', async () => {",
    1,
)
old = """  assert.equal(Object.hasOwn(capturedUserPayload, 'contextFacts'), false);
  assert.equal(Object.hasOwn(capturedUserPayload, 'placeSummaries'), false);
  assert.equal(Object.hasOwn(capturedUserPayload, 'scene'), false);
  assert.equal(Object.hasOwn(capturedUserPayload, 'dayPhase'), false);
  assert.equal(typeof capturedUserPayload.templateAnswer, 'string');
"""
new = """  assert.equal(Object.hasOwn(capturedUserPayload, 'contextFacts'), true);
  assert.equal(capturedUserPayload.contextFacts, '');
  assert.deepEqual(capturedUserPayload.placeSummaries, []);
  assert.equal(Object.hasOwn(capturedUserPayload, 'scene'), false);
  assert.equal(Object.hasOwn(capturedUserPayload, 'dayPhase'), false);
  assert.equal(Object.hasOwn(capturedUserPayload, 'location'), false);
  assert.equal(Object.hasOwn(capturedUserPayload, 'latitude'), false);
  assert.equal(Object.hasOwn(capturedUserPayload, 'longitude'), false);
  assert.equal(typeof capturedUserPayload.templateAnswer, 'string');
"""
if text.count(old) != 1:
    raise RuntimeError(f"expected one obsolete assertion block, found {text.count(old)}")
PATH.write_text(text.replace(old, new), encoding="utf-8")
print("assistant server privacy test updated")
