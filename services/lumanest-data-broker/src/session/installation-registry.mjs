import * as defaultFileSystem from 'node:fs/promises';
import { dirname } from 'node:path';
import { randomBytes } from 'node:crypto';

const documentVersion = 1;

// A healthy installation bootstraps once per process launch and the client
// renews a handful of times per day, so a rolling window of 20 issuances
// absorbs restarts and clock skew while capping how long one self-reported
// identifier can keep minting fresh tokens.
const defaultWindowMilliseconds = 24 * 60 * 60 * 1_000;
const defaultMaximumIssuances = 20;

// Records that neither renewed nor were revoked within the retention window
// are pruned on save; revoked records are kept forever because dropping one
// would silently un-revoke that installation.
const defaultRetentionMilliseconds = 30 * 24 * 60 * 60 * 1_000;
const defaultMaximumTrackedInstallations = 10_000;

const installationIdPattern = /^[A-Za-z0-9_-]{22,80}$/;

export function isValidInstallationId(value) {
  return typeof value === 'string' && installationIdPattern.test(value);
}

function emptyRecord(now) {
  return {
    firstSeenAt: now.toISOString(),
    lastIssuedAt: now.toISOString(),
    issuances: [],
    totalIssuances: 0,
    revoked: false,
    revokedAt: null,
  };
}

function sanitizeRecord(value, now) {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) return null;
  const issuances = Array.isArray(value.issuances)
    ? value.issuances.filter((entry) => typeof entry === 'string' && !Number.isNaN(Date.parse(entry)))
    : [];
  const revokedAt = typeof value.revokedAt === 'string' && !Number.isNaN(Date.parse(value.revokedAt))
    ? value.revokedAt
    : null;
  return {
    firstSeenAt: typeof value.firstSeenAt === 'string' && !Number.isNaN(Date.parse(value.firstSeenAt))
      ? value.firstSeenAt
      : now.toISOString(),
    lastIssuedAt: typeof value.lastIssuedAt === 'string' && !Number.isNaN(Date.parse(value.lastIssuedAt))
      ? value.lastIssuedAt
      : now.toISOString(),
    issuances,
    totalIssuances: Number.isInteger(value.totalIssuances) && value.totalIssuances >= 0
      ? value.totalIssuances
      : issuances.length,
    revoked: value.revoked === true,
    revokedAt: value.revoked === true ? revokedAt : null,
  };
}

// The installation identifier is the quota and revocation handle for the
// short-lived app session tokens: issuance counts and revocations are tracked
// per identifier so one abusive install can be cut off without rotating the
// signing key for everybody. The records hold random client-generated
// identifiers plus counts and timestamps - no credentials, no personal data -
// so a plain JSON file in the broker's private data directory is appropriate.
export class SessionInstallationRegistry {
  #filePath;
  #fileSystem;
  #now;
  #windowMilliseconds;
  #maximumIssuances;
  #retentionMilliseconds;
  #maximumTrackedInstallations;
  #installations = new Map();
  #writeQueue = Promise.resolve();
  #initialized = false;

  constructor({
    filePath = '',
    fileSystem = defaultFileSystem,
    now = () => new Date(),
    windowMilliseconds = defaultWindowMilliseconds,
    maximumIssuances = defaultMaximumIssuances,
    retentionMilliseconds = defaultRetentionMilliseconds,
    maximumTrackedInstallations = defaultMaximumTrackedInstallations,
  } = {}) {
    if (typeof filePath !== 'string') throw new TypeError('filePath must be a string');
    this.#filePath = filePath;
    this.#fileSystem = fileSystem;
    this.#now = now;
    if (!Number.isInteger(windowMilliseconds) || windowMilliseconds <= 0) {
      throw new TypeError('windowMilliseconds must be a positive integer');
    }
    if (!Number.isInteger(maximumIssuances) || maximumIssuances < 1) {
      throw new TypeError('maximumIssuances must be a positive integer');
    }
    this.#windowMilliseconds = windowMilliseconds;
    this.#maximumIssuances = maximumIssuances;
    this.#retentionMilliseconds = retentionMilliseconds;
    this.#maximumTrackedInstallations = maximumTrackedInstallations;
    // Without a file path there is nothing to load, so the registry is usable
    // immediately; initialize() only exists to restore persisted state.
    this.#initialized = this.#filePath.length === 0;
  }

  async initialize() {
    if (this.#filePath.length === 0) {
      this.#initialized = true;
      return this;
    }
    let serialized;
    try {
      serialized = await this.#fileSystem.readFile(this.#filePath, 'utf8');
    } catch (error) {
      if (error?.code === 'ENOENT') {
        this.#initialized = true;
        return this;
      }
      throw error;
    }
    try {
      const document = JSON.parse(serialized);
      if (document?.version !== documentVersion || document?.installations == null ||
          typeof document.installations !== 'object' || Array.isArray(document.installations)) {
        throw new Error('Unsupported session installation document');
      }
      const now = this.#now();
      for (const [installationId, record] of Object.entries(document.installations)) {
        if (isValidInstallationId(installationId)) {
          this.#installations.set(installationId, sanitizeRecord(record, now));
        }
      }
    } catch (error) {
      throw new Error('Unable to parse session installation records', { cause: error });
    }
    this.#initialized = true;
    return this;
  }

  #requireInitialized() {
    if (!this.#initialized) throw new Error('Session installation registry is not initialized');
  }

  isRevoked(installationId) {
    this.#requireInitialized();
    return this.#installations.get(installationId)?.revoked === true;
  }

  // Returns { allowed: true } or { allowed: false, status, retryAfterSeconds }.
  // The quota uses a rolling window of recorded issuance timestamps; when the
  // window is exhausted the caller receives how long to wait, not a permanent
  // refusal.
  async recordIssuance({ installationId }) {
    this.#requireInitialized();
    if (!isValidInstallationId(installationId)) {
      throw new TypeError('installationId is required');
    }
    const now = this.#now();
    const record = this.#installations.get(installationId) ?? emptyRecord(now);
    if (record.revoked) {
      return { allowed: false, status: 403 };
    }
    const windowStart = now.getTime() - this.#windowMilliseconds;
    record.issuances = record.issuances.filter(
      (entry) => Date.parse(entry) > windowStart,
    );
    if (record.issuances.length >= this.#maximumIssuances) {
      const oldestAllowedAt = Date.parse(record.issuances[0]) + this.#windowMilliseconds;
      this.#installations.set(installationId, record);
      return {
        allowed: false,
        status: 429,
        retryAfterSeconds: Math.max(1, Math.ceil((oldestAllowedAt - now.getTime()) / 1_000)),
      };
    }
    record.issuances.push(now.toISOString());
    record.lastIssuedAt = now.toISOString();
    record.totalIssuances += 1;
    this.#installations.set(installationId, record);
    await this.#persist();
    return { allowed: true };
  }

  async setRevoked(installationId, revoked) {
    this.#requireInitialized();
    if (!isValidInstallationId(installationId)) {
      throw new TypeError('installationId is required');
    }
    const now = this.#now();
    const record = this.#installations.get(installationId) ?? emptyRecord(now);
    record.revoked = revoked === true;
    record.revokedAt = record.revoked ? now.toISOString() : null;
    this.#installations.set(installationId, record);
    await this.#persist();
    return this.describe(installationId);
  }

  describe(installationId) {
    this.#requireInitialized();
    const record = this.#installations.get(installationId);
    if (record == null) return null;
    return {
      installationId,
      ...structuredClone(record),
    };
  }

  list({ limit = 50 } = {}) {
    this.#requireInitialized();
    if (!Number.isInteger(limit) || limit < 1) throw new TypeError('limit must be a positive integer');
    return [...this.#installations.entries()]
      .sort(([, a], [, b]) => Date.parse(b.lastIssuedAt) - Date.parse(a.lastIssuedAt))
      .slice(0, limit)
      .map(([installationId, record]) => ({ installationId, ...structuredClone(record) }));
  }

  async #persist() {
    if (this.#filePath.length === 0) return;
    const operation = this.#writeQueue.then(() => this.#writeAtomically());
    this.#writeQueue = operation.catch(() => {});
    await operation;
  }

  async #writeAtomically() {
    const now = this.#now();
    const retentionStart = now.getTime() - this.#retentionMilliseconds;
    const windowStart = now.getTime() - this.#windowMilliseconds;
    const pruned = new Map();
    for (const [installationId, record] of this.#installations) {
      if (record.revoked) {
        pruned.set(installationId, record);
        continue;
      }
      const lastIssuedAt = Date.parse(record.lastIssuedAt);
      const stillActive = lastIssuedAt > retentionStart ||
        record.issuances.some((entry) => Date.parse(entry) > windowStart);
      if (stillActive) pruned.set(installationId, record);
    }
    while (pruned.size > this.#maximumTrackedInstallations) {
      // Drop the least recently issued non-revoked record first.
      let oldest = null;
      for (const [installationId, record] of pruned) {
        if (record.revoked) continue;
        if (oldest == null || Date.parse(record.lastIssuedAt) < Date.parse(pruned.get(oldest).lastIssuedAt)) {
          oldest = installationId;
        }
      }
      if (oldest == null) break;
      pruned.delete(oldest);
    }
    const document = JSON.stringify({
      version: documentVersion,
      installations: Object.fromEntries(pruned),
    });

    const directory = dirname(this.#filePath);
    const temporaryPath = `${this.#filePath}.tmp-${process.pid}-${randomBytes(8).toString('hex')}`;
    await this.#fileSystem.mkdir(directory, { recursive: true, mode: 0o700 });
    let handle;
    try {
      handle = await this.#fileSystem.open(temporaryPath, 'wx', 0o600);
      await handle.writeFile(document, 'utf8');
      await handle.sync();
      await handle.close();
      handle = null;
      await this.#fileSystem.rename(temporaryPath, this.#filePath);

      const directoryHandle = await this.#fileSystem.open(directory, 'r');
      try {
        await directoryHandle.sync();
      } finally {
        await directoryHandle.close();
      }
    } catch (error) {
      if (handle != null) await handle.close().catch(() => {});
      await this.#fileSystem.unlink(temporaryPath).catch(() => {});
      throw error;
    }
  }
}
