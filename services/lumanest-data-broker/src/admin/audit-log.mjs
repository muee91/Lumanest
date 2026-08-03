import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import * as defaultFileSystem from 'node:fs/promises';
import { dirname } from 'node:path';

const documentVersion = 1;
const algorithm = 'aes-256-gcm';

const maximumEntries = 500;
const retentionMilliseconds = 30 * 24 * 60 * 60 * 1_000; // 30 days
const maximumListEntries = 200;

const maximumOperationLength = 48;
const maximumResultLength = 48;
const maximumFieldLength = 32;
const maximumFieldsCount = 12;
const maximumDetailValueLength = 64;
const maximumDetailsCount = 6;

// How far in the future a timestamp can be before we consider it malformed.
// Clock skew between machines or minor drift should not cause records to be
// dropped, but a wildly future timestamp (e.g. corrupted/garbage data) must
// not survive.
const maximumFutureClockSkewMilliseconds = 5 * 60 * 1_000; // 5 minutes

const allowedOperations = new Set([
  'login',
  'logout',
  'change_password',
  'update_config',
  'update_llm_routing',
  'create_llm_profile',
  'update_llm_profile',
  'delete_llm_profile',
  'test_llm_profile',
  'list_llm_models',
  'update_discovery_search_profile',
  'list_context_sources',
  'read_shooting_calibration',
  'import_context_dataset',
  'activate_simulation',
  'clear_simulation',
  'clear_all_simulations',
  'clear_cache',
  'restart',
  'update_outbound_network',
  'test_7timer',
  'test_provider',
]);

const allowedFields = new Set([
  'product',
  'providerId',
  'id',
  'profileId',
  'preset',
  'mode',
  'days',
  'minimumSamples',
  'sourceId',
  'datasetType',
  'primaryProfileId',
  'fallbackEnabled',
  'fallbackProfileIds',
  'settings',
  'llmProfiles',
  'llmRouting',
  'discoverySearchProfile',
  'apiKey',
  'baseUrl',
  'enabled',
  'timeoutMs',
  'model',
  'name',
  'protocol',
  'allowFallback',
  'sourcePolicies',
]);

const allowedResults = new Set([
  'ok',
  'accepted',
  'rejected',
  'failed',
  'invalid_password',
  'invalid_current_password',
  'rate_limited',
  'profile_not_found',
  'profile_exists',
  'profile_referenced',
  'not_configured',
  'upstream_unavailable',
  'disabled',
  'test_in_progress',
  'test_cooldown',
  'test_busy',
  'invalid_import',
  'unauthorized',
  'csrf_mismatch',
]);

const allowedDetailKeys = new Set(['product', 'providerId', 'traceId']);

function decodeMasterKey(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) {
    throw new TypeError('Master key must be a 32-byte base64 value');
  }
  const decoded = Buffer.from(value, 'base64');
  if (decoded.length !== 32 || decoded.toString('base64') !== value) {
    throw new TypeError('Master key must be a 32-byte base64 value');
  }
  return decoded;
}

function boundedString(value, maximum) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > maximum) return null;
  return trimmed;
}

function sanitizeOperation(value) {
  const candidate = boundedString(value, maximumOperationLength);
  if (candidate == null || !allowedOperations.has(candidate)) return null;
  return candidate;
}

function sanitizeResult(value) {
  const candidate = boundedString(value, maximumResultLength);
  if (candidate == null) return null;
  // Results are mostly whitelisted, but upstream error codes can vary. Accept
  // any bounded string that matches the allowed set; unknown values collapse
  // to a generic 'failed' so the log never silently drops an audit event.
  return allowedResults.has(candidate) ? candidate : 'failed';
}

function sanitizeFields(value) {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => boundedString(item, maximumFieldLength))
    .filter((item) => item != null && allowedFields.has(item))
    .slice(0, maximumFieldsCount);
}

function sanitizeDetails(value) {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) return {};
  return Object.fromEntries(
    Object.entries(value)
      .filter(([name, val]) =>
        allowedDetailKeys.has(name) &&
        (typeof val === 'string' || val == null))
      .map(([name, val]) => {
        if (val == null) return [name, null];
        const bounded = boundedString(val, maximumDetailValueLength);
        return bounded == null ? null : [name, bounded];
      })
      .filter(Boolean)
      .slice(0, maximumDetailsCount),
  );
}

/**
 * Parses an ISO 8601 timestamp string into epoch milliseconds.
 * Returns null for invalid, non-string, or out-of-range values.
 * A timestamp too far in the future (beyond allowed clock skew) is treated as
 * malformed and rejected — untrusted records must not survive.
 */
function parseTimestampMillis(value, nowMillis) {
  if (typeof value !== 'string' || value.length === 0 || value.length > 40) return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return null;
  const millis = parsed.getTime();
  if (millis > nowMillis + maximumFutureClockSkewMilliseconds) return null;
  return millis;
}

/**
 * Determines whether an entry has exceeded the retention period.
 * Uses strict timestamp parsing — an unparseable timestamp is treated as
 * expired so malformed records are always evicted.
 */
function isExpired(entry, nowMillis) {
  const entryMillis = parseTimestampMillis(entry.timestamp, nowMillis);
  if (entryMillis == null) return true;
  return nowMillis - entryMillis >= retentionMilliseconds;
}

/**
 * Sanitizes an error into a safe, non-sensitive code for observability.
 * Never exposes raw file paths, exception text, or credentials.
 */
function safeErrorCode(error, fallback) {
  if (error == null) return fallback;
  // Only use stable error codes (e.g. 'EACCES', 'ENOENT'), never raw messages
  // or paths that might leak filesystem structure.
  if (typeof error.code === 'string' && /^[A-Z_]{2,32}$/.test(error.code)) {
    return error.code;
  }
  return fallback;
}

/**
 * Persistent, encrypted, redacted audit log.
 *
 * Reuses the same AES-256-GCM + master-key approach as EncryptedConfigStore.
 * Stores entries in `${dataDirectory}/audit-log.enc.json`. Never records
 * remoteAddress, coordinates, raw requests, tokens, auth headers, passwords,
 * or model prompts/responses — only a whitelisted operation, bounded field
 * names, a whitelisted result, and a tiny whitelisted details object.
 *
 * Write failures are observable via `lastWriteError` / `lastWriteAt` but never
 * reject the caller's record() promise, so a disk problem cannot block an
 * admin request. A corrupted or undecryptable file degrades to an empty log
 * rather than crashing the broker.
 */
export class AuditLog {
  #filePath;
  #key;
  #fileSystem;
  #randomBytes;
  #entries = [];
  #now;
  #writeQueue = Promise.resolve();
  #lastWriteError = null;
  #lastWriteAt = null;
  #lastWriteOk = null;

  constructor({
    filePath,
    masterKey,
    fileSystem = defaultFileSystem,
    randomBytesGenerator = randomBytes,
    now = () => new Date(),
  } = {}) {
    if (typeof filePath !== 'string' || filePath.length === 0) {
      throw new TypeError('Audit log file path is required');
    }
    this.#filePath = filePath;
    this.#key = decodeMasterKey(masterKey);
    this.#fileSystem = fileSystem;
    this.#randomBytes = randomBytesGenerator;
    this.#now = now;
  }

  /**
   * Loads and decrypts the persisted log. If the file is missing, empty, or
   * corrupted, the log starts empty — never throws. After pruning expired
   * or malformed entries, persists the cleaned state so the encrypted file
   * does not retain stale data. A persistence failure during init does not
   * prevent the broker from starting, but is reflected in status().
   */
  async initialize() {
    this.#entries = await this.#readFromDisk();
    const nowMillis = new Date(this.#now()).getTime();
    const before = this.#entries.length;
    this.#prune(nowMillis);
    // If pruning actually removed entries, persist the cleaned state so the
    // encrypted file does not retain expired or malformed records.
    if (this.#entries.length !== before) {
      try {
        await this.#writeAtomically();
      } catch {
        // Swallowed: status() exposes the failure. Broker startup continues.
      }
    }
    return this;
  }

  /**
   * Returns observability status for health checks. Never throws.
   * `lastWriteError` is a safe code — never a raw path or exception text.
   */
  status() {
    return Object.freeze({
      entries: this.#entries.length,
      lastWriteAt: this.#lastWriteAt,
      lastWriteOk: this.#lastWriteOk,
      lastWriteError: this.#lastWriteError,
    });
  }

  /**
   * Records an audit entry. The returned promise never rejects — a disk write
   * failure is captured in `status()` instead of blocking the admin request.
   * `remoteAddress` is intentionally ignored.
   *
   * For most operations the persistence is fully asynchronous: the caller does
   * not await the returned promise and the write happens in the background.
   * For `restart` — where the process is about to exit — the caller should
   * use `flush()` to ensure the entry reaches disk before the process exits.
   */
  record({ remoteAddress: _ignored, operation, fields = [], result, details = {} }) {
    const sanitizedOperation = sanitizeOperation(operation);
    if (sanitizedOperation == null) return Promise.resolve();
    const entry = Object.freeze({
      timestamp: new Date(this.#now()).toISOString(),
      operation: sanitizedOperation,
      fields: Object.freeze(sanitizeFields(fields)),
      result: sanitizeResult(result),
      details: Object.freeze(sanitizeDetails(details)),
    });
    this.#entries.push(entry);
    this.#prune(new Date(this.#now()).getTime());
    return this.#persist().catch(() => {
      // Swallowed: status() exposes the failure. The in-memory entry is kept
      // so the current request's audit trail survives until the next write.
    });
  }

  /**
   * Ensures all pending writes have completed. Call this before a process
   * exit (e.g. restart) so the final audit entry is not lost.
   * Never rejects — a write failure is reflected in status().
   */
  async flush() {
    try {
      await this.#writeQueue;
    } catch {
      // The write queue catches all errors internally, but guard just in case.
    }
  }

  /**
   * Returns entries newest-first, bounded by maximumListEntries. Async because
   * a future implementation may lazy-load from disk; callers should await.
   */
  async list() {
    return this.#entries
      .slice(-maximumListEntries)
      .map((entry) => ({
        ...entry,
        fields: [...entry.fields],
        details: { ...entry.details },
      }))
      .reverse();
  }

  #prune(nowMillis) {
    if (this.#entries.length <= maximumEntries && !this.#entries.some((e) => isExpired(e, nowMillis))) {
      return;
    }
    this.#entries = this.#entries
      .filter((entry) => !isExpired(entry, nowMillis))
      .slice(-maximumEntries);
  }

  #persist() {
    const operation = this.#writeQueue.then(() => this.#writeAtomically());
    this.#writeQueue = operation.catch(() => {});
    return operation;
  }

  async #writeAtomically() {
    const iv = this.#randomBytes(12);
    const cipher = createCipheriv(algorithm, this.#key, iv);
    const plaintext = Buffer.from(JSON.stringify(this.#entries), 'utf8');
    const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
    const document = JSON.stringify({
      version: documentVersion,
      algorithm,
      iv: iv.toString('base64'),
      authenticationTag: cipher.getAuthTag().toString('base64'),
      ciphertext: ciphertext.toString('base64'),
    });

    const directory = dirname(this.#filePath);
    const temporaryPath = `${this.#filePath}.tmp-${process.pid}-${this.#randomBytes(8).toString('hex')}`;
    let handle;
    try {
      await this.#fileSystem.mkdir(directory, { recursive: true, mode: 0o700 });
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
      this.#lastWriteAt = new Date(this.#now()).toISOString();
      this.#lastWriteOk = true;
      this.#lastWriteError = null;
    } catch (error) {
      this.#lastWriteAt = new Date(this.#now()).toISOString();
      this.#lastWriteOk = false;
      this.#lastWriteError = safeErrorCode(error, 'write_failed');
      throw error;
    } finally {
      if (handle != null) await handle.close().catch(() => {});
      await this.#fileSystem.unlink(temporaryPath).catch(() => {});
    }
  }

  async #readFromDisk() {
    let serialized;
    try {
      serialized = await this.#fileSystem.readFile(this.#filePath, 'utf8');
    } catch (error) {
      if (error?.code === 'ENOENT') return [];
      this.#lastWriteError = safeErrorCode(error, 'read_failed');
      return [];
    }

    try {
      const document = JSON.parse(serialized);
      if (document.version !== documentVersion || document.algorithm !== algorithm) {
        throw new Error('Unsupported audit log version');
      }
      const iv = Buffer.from(document.iv, 'base64');
      const authenticationTag = Buffer.from(document.authenticationTag, 'base64');
      const ciphertext = Buffer.from(document.ciphertext, 'base64');
      if (iv.length !== 12 || authenticationTag.length !== 16) {
        throw new Error('Invalid audit log header');
      }
      const decipher = createDecipheriv(algorithm, this.#key, iv);
      decipher.setAuthTag(authenticationTag);
      const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
      const entries = JSON.parse(plaintext.toString('utf8'));
      if (!Array.isArray(entries)) throw new Error('Audit log payload must be an array');
      const nowMillis = new Date(this.#now()).getTime();
      return entries
        .filter((entry) => entry != null && typeof entry === 'object' && !Array.isArray(entry))
        .map((entry) => {
          // Strict validation: discard entries with invalid operation,
          // result, or timestamp. Never produce 'unknown' — malformed
          // historical entries are dropped entirely.
          const sanitizedOperation = sanitizeOperation(entry.operation);
          if (sanitizedOperation == null) return null;
          const sanitizedResult = sanitizeResult(entry.result);
          if (sanitizedResult == null) return null;
          const timestampMillis = parseTimestampMillis(entry.timestamp, nowMillis);
          if (timestampMillis == null) return null;
          return Object.freeze({
            timestamp: entry.timestamp,
            operation: sanitizedOperation,
            fields: Object.freeze(sanitizeFields(entry.fields)),
            result: sanitizedResult,
            details: Object.freeze(sanitizeDetails(entry.details)),
          });
        })
        .filter((entry) => entry != null);
    } catch {
      // Corrupted or tampered file: degrade to empty log, never crash.
      this.#lastWriteError = 'corrupt_file';
      return [];
    }
  }
}
