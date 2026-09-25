import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import test from 'node:test';

import { apiErrorCodes } from '../src/api/error-codes.mjs';

async function sources(dir) {
  const found = [];
  for (const entry of await readdir(new URL(dir, import.meta.url), { withFileTypes: true })) {
    const path = `${dir}${entry.name}`;
    if (entry.isDirectory()) found.push(...(await sources(`${path}/`)));
    else if (entry.name.endsWith('.mjs')) found.push(path);
  }
  return found;
}

test('error codes are unique snake_case wire values', () => {
  const values = Object.values(apiErrorCodes);
  assert.equal(new Set(values).size, values.length, 'two keys share one wire value');
  for (const value of values) {
    assert.match(value, /^[a-z][a-z0-9_]*$/, `${value} is not a wire-shaped code`);
  }
});

test('an upstream contract violation is never reported as an outage', () => {
  // Both codes exist because a 200 whose shape breaks our contract needs a
  // different runbook from a service that is not answering.
  assert.notEqual(apiErrorCodes.upstreamContractMismatch, apiErrorCodes.upstreamUnavailable);
});

test('no broker handler can invent an unlisted error code', async () => {
  const files = (await sources('../src/')).filter((path) => !path.includes('network-controller'));
  const offenders = [];
  for (const path of files) {
    if (path.endsWith('src/api/error-codes.mjs')) continue;
    const source = await readFile(new URL(path, import.meta.url), 'utf8');
    for (const match of source.matchAll(/(?<![\w.])error: '([a-z_]+)'/g)) {
      offenders.push(`${path}: ${match[1]}`);
    }
  }
  assert.deepEqual(offenders, [], 'free-typed wire codes bypass the contract table');
});

test('every listed code is still reachable, so the table cannot accrete ghosts', async () => {
  const brokerFiles = (await sources('../src/')).filter((path) => !path.includes('network-controller'));
  const referenced = new Set();
  for (const path of [...brokerFiles, ...(await sources('../test/'))]) {
    if (path.endsWith('src/api/error-codes.mjs')) continue;
    const source = await readFile(new URL(path, import.meta.url), 'utf8');
    for (const match of source.matchAll(/apiErrorCodes\.([A-Za-z0-9_]+)/g)) referenced.add(match[1]);
  }
  const unused = Object.keys(apiErrorCodes).filter((key) => !referenced.has(key));
  assert.deepEqual(unused, [], 'unreferenced codes make the contract table a lie');
});
