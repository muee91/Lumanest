import assert from 'node:assert/strict';
import test from 'node:test';

import { ContextSnapshotStore } from '../src/context/context-snapshot-store.mjs';

test('context snapshot store clones accepted snapshots before retaining them', () => {
  const store = new ContextSnapshotStore();
  const source = {
    contextId: 'ctx_1234567890abcdef12345678',
    expiresAt: '2026-09-05T08:00:00Z',
    facts: { events: [{ id: 'session.city.blue_hour' }] },
  };

  store.rememberSnapshot(source);
  source.facts.events[0].id = 'mutated';

  assert.equal(
    store.snapshot('ctx_1234567890abcdef12345678').facts.events[0].id,
    'session.city.blue_hour',
  );
  assert.equal(store.snapshot('missing'), null);
});

test('context snapshot store remains bounded and evicts the oldest snapshot', () => {
  const store = new ContextSnapshotStore({ maximumSnapshots: 2 });
  store.rememberSnapshot({ contextId: 'ctx_first' });
  store.rememberSnapshot({ contextId: 'ctx_second' });
  store.rememberSnapshot({ contextId: 'ctx_third' });

  assert.equal(store.snapshot('ctx_first'), null);
  assert.equal(store.snapshot('ctx_second').contextId, 'ctx_second');
  assert.equal(store.snapshot('ctx_third').contextId, 'ctx_third');
});
