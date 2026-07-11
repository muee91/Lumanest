import { sign } from 'node:crypto';

const maxTtlSeconds = 86400;
const clockSkewSeconds = 30;

function base64urlJson(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

/**
 * Creates a QWeather-compatible EdDSA JWT. The supplied private key must
 * remain server-side; this module never serializes or logs it.
 */
export function createQWeatherJwt({
  privateKey,
  keyId,
  projectId,
  now = new Date(),
  ttlSeconds = 900,
}) {
  if (!Number.isInteger(ttlSeconds) || ttlSeconds <= 0 || ttlSeconds > maxTtlSeconds) {
    throw new RangeError(`JWT ttlSeconds must be between 1 and ${maxTtlSeconds}`);
  }
  if (!keyId || !projectId) {
    throw new TypeError('QWeather keyId and projectId are required');
  }

  const iat = Math.floor(now.getTime() / 1000) - clockSkewSeconds;
  const header = base64urlJson({ alg: 'EdDSA', kid: keyId });
  const payload = base64urlJson({ sub: projectId, iat, exp: iat + ttlSeconds });
  const signingInput = `${header}.${payload}`;
  const signature = sign(null, Buffer.from(signingInput), privateKey).toString('base64url');
  return `${signingInput}.${signature}`;
}
