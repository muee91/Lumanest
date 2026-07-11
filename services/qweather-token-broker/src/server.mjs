import { createPrivateKey, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { createQWeatherJwt } from './jwt.mjs';

const tokenLifetimeSeconds = 900;

function writeJson(response, status, body) {
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  });
  response.end(JSON.stringify(body));
}

function hasValidAuthorization(header, serviceToken) {
  if (typeof header !== 'string') return false;
  const actual = Buffer.from(header);
  const expected = Buffer.from(`Bearer ${serviceToken}`);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export function createTokenBrokerServer({
  privateKey,
  keyId,
  projectId,
  serviceToken,
  now = () => new Date(),
}) {
  return createServer((request, response) => {
    if (request.method === 'GET' && request.url === '/healthz') {
      writeJson(response, 200, { status: 'ok' });
      return;
    }

    if (request.method !== 'POST' || request.url !== '/v1/qweather/token') {
      writeJson(response, 404, { error: 'not_found' });
      return;
    }

    if (!hasValidAuthorization(request.headers.authorization, serviceToken)) {
      writeJson(response, 401, { error: 'unauthorized' });
      return;
    }

    const issuedAt = now();
    const iat = Math.floor(issuedAt.getTime() / 1000) - 30;
    const token = createQWeatherJwt({
      privateKey,
      keyId,
      projectId,
      now: issuedAt,
      ttlSeconds: tokenLifetimeSeconds,
    });
    writeJson(response, 200, {
      token,
      expiresAt: new Date((iat + tokenLifetimeSeconds) * 1000).toISOString(),
    });
  });
}

export function configurationFromEnvironment(environment = process.env) {
  const required = (name) => {
    const value = environment[name]?.trim();
    if (!value) throw new Error(`Missing required environment variable: ${name}`);
    return value;
  };

  const privateKeyPath = required('QWEATHER_PRIVATE_KEY_PATH');
  return {
    privateKey: createPrivateKey(readFileSync(privateKeyPath)),
    keyId: required('QWEATHER_KEY_ID'),
    projectId: required('QWEATHER_PROJECT_ID'),
    serviceToken: required('LUMANEST_SERVICE_TOKEN'),
    port: Number.parseInt(environment.PORT ?? '8787', 10),
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const configuration = configurationFromEnvironment();
  const server = createTokenBrokerServer(configuration);
  server.listen(configuration.port, '0.0.0.0', () => {
    console.log(`qweather-token-broker listening on ${configuration.port}`);
  });
}
