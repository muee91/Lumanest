import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import * as defaultFileSystem from 'node:fs/promises';
import { dirname } from 'node:path';

import { Algorithm, hash, verify } from '@node-rs/argon2';

const stateVersion = 1;
const sessionLifetimeMilliseconds = 30 * 24 * 60 * 60 * 1_000;
const failureWindowMilliseconds = 15 * 60 * 1_000;
const lockDurationMilliseconds = 15 * 60 * 1_000;
const maximumFailures = 5;

function digest(value) {
  return createHash('sha256').update(value).digest('hex');
}

function sameDigest(actual, expected) {
  if (typeof actual !== 'string' || typeof expected !== 'string') return false;
  const actualBytes = Buffer.from(actual, 'hex');
  const expectedBytes = Buffer.from(expected, 'hex');
  return actualBytes.length === expectedBytes.length &&
    actualBytes.length > 0 && timingSafeEqual(actualBytes, expectedBytes);
}

function validatePassword(password) {
  if (typeof password !== 'string' || password.length < 8 || password.length > 256) {
    throw new TypeError('Administrator password must contain 8 to 256 characters');
  }
}

async function hashPassword(password) {
  return hash(password, {
    algorithm: Algorithm.Argon2id,
    memoryCost: 19_456,
    timeCost: 2,
    parallelism: 1,
    outputLen: 32,
  });
}

export class AdminAuthService {
  #filePath;
  #bootstrapPassword;
  #now;
  #randomBytes;
  #fileSystem;
  #state = null;
  #failures = new Map();
  #operationQueue = Promise.resolve();

  constructor({
    filePath,
    bootstrapPassword = '',
    now = () => new Date(),
    randomBytesGenerator = randomBytes,
    fileSystem = defaultFileSystem,
  }) {
    if (typeof filePath !== 'string' || filePath.length === 0) {
      throw new TypeError('Administrator auth file path is required');
    }
    this.#filePath = filePath;
    this.#bootstrapPassword = bootstrapPassword;
    this.#now = now;
    this.#randomBytes = randomBytesGenerator;
    this.#fileSystem = fileSystem;
  }

  initialize() {
    return this.#enqueue(async () => {
      if (this.#state != null) return;
      try {
        const serialized = await this.#fileSystem.readFile(this.#filePath, 'utf8');
        const state = JSON.parse(serialized);
        if (state.version !== stateVersion || typeof state.passwordHash !== 'string' ||
            !Array.isArray(state.sessions)) {
          throw new Error('Invalid administrator auth state');
        }
        this.#state = state;
      } catch (error) {
        if (error?.code !== 'ENOENT') throw error;
        validatePassword(this.#bootstrapPassword);
        this.#state = {
          version: stateVersion,
          passwordHash: await hashPassword(this.#bootstrapPassword),
          sessions: [],
        };
        await this.#persist();
      }
    });
  }

  async verifyPassword(password) {
    this.#requireInitialized();
    if (typeof password !== 'string') return false;
    try {
      return await verify(this.#state.passwordHash, password);
    } catch {
      return false;
    }
  }

  login({ password, ipAddress }) {
    return this.#enqueue(async () => {
      this.#requireInitialized();
      const now = this.#now().getTime();
      const failure = this.#activeFailure(ipAddress, now);
      if (failure.lockedUntil > now) return { ok: false, reason: 'rate_limited' };

      if (!await this.verifyPassword(password)) {
        failure.timestamps.push(now);
        if (failure.timestamps.length >= maximumFailures) {
          failure.lockedUntil = now + lockDurationMilliseconds;
          this.#failures.set(ipAddress, failure);
          return { ok: false, reason: 'rate_limited' };
        }
        this.#failures.set(ipAddress, failure);
        return { ok: false, reason: 'invalid_credentials' };
      }

      this.#failures.delete(ipAddress);
      const sessionToken = this.#randomBytes(32).toString('base64url');
      const csrfToken = this.#randomBytes(32).toString('base64url');
      this.#state.sessions = this.#state.sessions
        .filter((session) => session.expiresAt > now)
        .concat({
          tokenDigest: digest(sessionToken),
          csrfDigest: digest(csrfToken),
          createdAt: now,
          expiresAt: now + sessionLifetimeMilliseconds,
        });
      await this.#persist();
      return {
        ok: true,
        sessionToken,
        csrfToken,
        cookie: `lumanest_admin=${sessionToken}; HttpOnly; SameSite=Strict; Path=/; Max-Age=2592000`,
      };
    });
  }

  authenticate({ sessionToken, csrfToken = null, requireCsrf = false }) {
    return this.#enqueue(async () => {
      this.#requireInitialized();
      if (typeof sessionToken !== 'string' || sessionToken.length === 0) {
        return { ok: false, reason: 'unauthenticated' };
      }
      const now = this.#now().getTime();
      const tokenDigest = digest(sessionToken);
      const session = this.#state.sessions.find((candidate) =>
        sameDigest(candidate.tokenDigest, tokenDigest));
      if (session == null || session.expiresAt <= now) {
        if (session != null) {
          this.#state.sessions = this.#state.sessions.filter((candidate) => candidate !== session);
          await this.#persist();
        }
        return { ok: false, reason: 'unauthenticated' };
      }
      if (requireCsrf &&
          (typeof csrfToken !== 'string' || !sameDigest(session.csrfDigest, digest(csrfToken)))) {
        return { ok: false, reason: 'csrf_mismatch' };
      }
      return { ok: true, expiresAt: session.expiresAt };
    });
  }

  logout(sessionToken) {
    return this.#enqueue(async () => {
      this.#requireInitialized();
      if (typeof sessionToken !== 'string') return;
      const tokenDigest = digest(sessionToken);
      const remaining = this.#state.sessions.filter((session) =>
        !sameDigest(session.tokenDigest, tokenDigest));
      if (remaining.length !== this.#state.sessions.length) {
        this.#state.sessions = remaining;
        await this.#persist();
      }
    });
  }

  changePassword(password) {
    return this.#enqueue(async () => {
      this.#requireInitialized();
      validatePassword(password);
      this.#state.passwordHash = await hashPassword(password);
      this.#state.sessions = [];
      this.#failures.clear();
      await this.#persist();
    });
  }

  #activeFailure(ipAddress, now) {
    const existing = this.#failures.get(ipAddress) ?? { timestamps: [], lockedUntil: 0 };
    existing.timestamps = existing.timestamps.filter((time) =>
      now - time <= failureWindowMilliseconds);
    if (existing.lockedUntil <= now) existing.lockedUntil = 0;
    return existing;
  }

  #requireInitialized() {
    if (this.#state == null) throw new Error('Administrator auth service is not initialized');
  }

  #enqueue(operation) {
    const result = this.#operationQueue.then(operation);
    this.#operationQueue = result.catch(() => {});
    return result;
  }

  async #persist() {
    const directory = dirname(this.#filePath);
    const temporaryPath = `${this.#filePath}.tmp-${process.pid}-${this.#randomBytes(8).toString('hex')}`;
    await this.#fileSystem.mkdir(directory, { recursive: true, mode: 0o700 });
    let handle;
    try {
      handle = await this.#fileSystem.open(temporaryPath, 'wx', 0o600);
      await handle.writeFile(JSON.stringify(this.#state), 'utf8');
      await handle.sync();
      await handle.close();
      handle = null;
      await this.#fileSystem.rename(temporaryPath, this.#filePath);
    } catch (error) {
      if (handle != null) await handle.close().catch(() => {});
      await this.#fileSystem.unlink(temporaryPath).catch(() => {});
      throw error;
    }
  }
}
