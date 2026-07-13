import assert from 'node:assert/strict';
import test from 'node:test';

import { isLanAddress } from '../src/admin/lan-address.mjs';

test('accepts loopback and private IPv4 addresses', () => {
  for (const address of ['127.0.0.1', '10.2.3.4', '172.16.0.1', '172.31.255.254', '192.168.100.151']) {
    assert.equal(isLanAddress(address), true, address);
  }
});

test('accepts IPv4-mapped private IPv6 addresses', () => {
  assert.equal(isLanAddress('::ffff:192.168.1.1'), true);
  assert.equal(isLanAddress('::ffff:127.0.0.1'), true);
});

test('accepts IPv6 loopback, unique local and link-local addresses', () => {
  for (const address of ['::1', 'fd12:3456::1', 'fc00::1', 'fe80::1']) {
    assert.equal(isLanAddress(address), true, address);
  }
});

test('rejects public and unspecified addresses', () => {
  for (const address of ['0.0.0.0', '8.8.8.8', '172.32.0.1', '192.169.1.1', '::', '2001:4860:4860::8888']) {
    assert.equal(isLanAddress(address), false, address);
  }
});

test('rejects malformed or missing addresses', () => {
  assert.equal(isLanAddress(null), false);
  assert.equal(isLanAddress('not-an-address'), false);
});
