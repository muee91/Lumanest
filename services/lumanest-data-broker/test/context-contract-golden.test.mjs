import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { forwardContextSnapshot } from '../src/context/proxy.mjs';
import { apiErrorCodes } from '../src/api/error-codes.mjs';

const golden = JSON.parse(
  await readFile(new URL('../../../contract/context-v5.snapshot.golden.json', import.meta.url), 'utf8'),
);
const policy = JSON.parse(
  await readFile(new URL('../../../contract/context-v5.policy.json', import.meta.url), 'utf8'),
);

async function validate(body) {
  return forwardContextSnapshot({
    body: {},
    serviceUrl: 'http://context-service:8000',
    internalToken: 'internal-secret',
    fetcher: async () => new Response(JSON.stringify(body), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    }),
  });
}

test('the shipped response shape is what the proxy accepts', async () => {
  assert.deepEqual(await validate(golden), { ok: true, body: golden });
});

test('one extra upstream field is a contract violation, not an outage', async () => {
  const widened = { ...golden, futureField: 1 };
  assert.deepEqual(await validate(widened), {
    ok: false,
    error: apiErrorCodes.upstreamContractMismatch,
  });
});

test('one missing upstream field is reported the same way', async () => {
  const narrowed = { ...golden };
  delete narrowed.refreshHints;
  assert.deepEqual(await validate(narrowed), {
    ok: false,
    error: apiErrorCodes.upstreamContractMismatch,
  });
});

test('the sky opportunity lead window matches the shared policy', async () => {
  const source = await readFile(
    new URL('../src/domain/sky_opportunity/sky_opportunity_service.mjs', import.meta.url),
    'utf8',
  );
  const literal = source.match(/NOTIFICATION_LEAD_LIMIT_MS = ([\d_][\d_*\s]*);/)[1];
  const milliseconds = literal.split('*').reduce(
    (total, factor) => total * Number(factor.replace(/_/g, '').trim()),
    1,
  );

  assert.equal(
    milliseconds,
    policy.interruptLeadLimitSeconds * 1000,
    'the broker and the context service must interrupt at the same horizon',
  );
});
