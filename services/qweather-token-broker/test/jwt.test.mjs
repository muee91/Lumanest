import assert from 'node:assert/strict';
import { generateKeyPairSync, verify } from 'node:crypto';
import test from 'node:test';

import { createQWeatherJwt } from '../src/jwt.mjs';

test('creates an EdDSA JWT with the required QWeather claims', () => {
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const now = new Date('2026-07-12T00:00:00Z');

  const token = createQWeatherJwt({
    privateKey,
    keyId: 'credential-id',
    projectId: 'project-id',
    now,
    ttlSeconds: 900,
  });

  const [headerPart, payloadPart, signaturePart] = token.split('.');
  const header = JSON.parse(Buffer.from(headerPart, 'base64url'));
  const payload = JSON.parse(Buffer.from(payloadPart, 'base64url'));

  assert.deepEqual(header, { alg: 'EdDSA', kid: 'credential-id' });
  assert.deepEqual(payload, {
    sub: 'project-id',
    iat: 1783814370,
    exp: 1783815270,
  });
  assert.equal(
    verify(
      null,
      Buffer.from(`${headerPart}.${payloadPart}`),
      publicKey,
      Buffer.from(signaturePart, 'base64url'),
    ),
    true,
  );
});

test('rejects a JWT lifetime longer than QWeather allows', () => {
  const { privateKey } = generateKeyPairSync('ed25519');

  assert.throws(
    () =>
      createQWeatherJwt({
        privateKey,
        keyId: 'credential-id',
        projectId: 'project-id',
        ttlSeconds: 86401,
      }),
    /86400/,
  );
});
