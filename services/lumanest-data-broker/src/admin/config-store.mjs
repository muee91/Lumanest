import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import * as defaultFileSystem from 'node:fs/promises';
import { dirname } from 'node:path';

const documentVersion = 1;
const algorithm = 'aes-256-gcm';
const sensitiveFields = new Set([
  'amapWebKey',
  'serviceToken',
  'qweatherPrivateKeyPem',
  'qweatherKeyId',
  'qweatherProjectId',
]);

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

function decodeDocumentField(document, field, expectedLength = null) {
  const value = document[field];
  if (typeof value !== 'string') throw new Error(`Invalid encrypted configuration ${field}`);
  const decoded = Buffer.from(value, 'base64');
  if (expectedLength != null && decoded.length !== expectedLength) {
    throw new Error(`Invalid encrypted configuration ${field}`);
  }
  return decoded;
}

export class EncryptedConfigStore {
  #filePath;
  #key;
  #fileSystem;
  #randomBytes;
  #writeQueue = Promise.resolve();

  constructor({
    filePath,
    masterKey,
    fileSystem = defaultFileSystem,
    randomBytesGenerator = randomBytes,
  }) {
    if (typeof filePath !== 'string' || filePath.length === 0) {
      throw new TypeError('Encrypted configuration file path is required');
    }
    this.#filePath = filePath;
    this.#key = decodeMasterKey(masterKey);
    this.#fileSystem = fileSystem;
    this.#randomBytes = randomBytesGenerator;
  }

  async read() {
    let serialized;
    try {
      serialized = await this.#fileSystem.readFile(this.#filePath, 'utf8');
    } catch (error) {
      if (error?.code === 'ENOENT') return null;
      throw error;
    }

    try {
      const document = JSON.parse(serialized);
      if (document.version !== documentVersion || document.algorithm !== algorithm) {
        throw new Error('Unsupported encrypted configuration version');
      }
      const iv = decodeDocumentField(document, 'iv', 12);
      const authenticationTag = decodeDocumentField(document, 'authenticationTag', 16);
      const ciphertext = decodeDocumentField(document, 'ciphertext');
      const decipher = createDecipheriv(algorithm, this.#key, iv);
      decipher.setAuthTag(authenticationTag);
      const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
      const value = JSON.parse(plaintext.toString('utf8'));
      if (value == null || typeof value !== 'object' || Array.isArray(value)) {
        throw new Error('Encrypted configuration payload must be an object');
      }
      return value;
    } catch (error) {
      throw new Error('Unable to decrypt encrypted configuration', { cause: error });
    }
  }

  write(value) {
    if (value == null || typeof value !== 'object' || Array.isArray(value)) {
      return Promise.reject(new TypeError('Encrypted configuration must be an object'));
    }
    const operation = this.#writeQueue.then(() => this.#writeAtomically(value));
    this.#writeQueue = operation.catch(() => {});
    return operation;
  }

  masked(value) {
    if (value == null || typeof value !== 'object' || Array.isArray(value)) return {};
    return Object.fromEntries(Object.entries(value).map(([name, fieldValue]) => {
      if (!sensitiveFields.has(name)) return [name, fieldValue];
      const configured = typeof fieldValue === 'string' && fieldValue.length > 0;
      return [name, {
        configured,
        lastFour: configured ? [...fieldValue].slice(-4).join('') : null,
      }];
    }));
  }

  async #writeAtomically(value) {
    const iv = this.#randomBytes(12);
    const cipher = createCipheriv(algorithm, this.#key, iv);
    const plaintext = Buffer.from(JSON.stringify(value), 'utf8');
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
