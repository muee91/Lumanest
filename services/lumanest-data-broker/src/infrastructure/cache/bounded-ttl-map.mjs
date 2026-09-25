const defaultMaximumEntries = 256;

/// Insertion-ordered cache with a hard ceiling, API-compatible with the subset of
/// `Map` the injected cache consumers use.
///
/// These caches used to be plain `new Map()`: an entry only ever left when
/// somebody read the same key after its TTL, so a broker serving many distinct
/// coordinates kept one entry per coordinate forever. The process is expected to
/// stay up for weeks on a NAS that also hosts another service, so "forgetting"
/// has to be a property of the structure rather than of someone revisiting a key.
export class BoundedTtlMap {
  #entries = new Map();

  #maximumEntries;

  constructor(maximumEntries = defaultMaximumEntries) {
    if (!Number.isInteger(maximumEntries) || maximumEntries < 1) {
      throw new RangeError('maximumEntries must be a positive integer');
    }
    this.#maximumEntries = maximumEntries;
  }

  get(key) {
    if (!this.#entries.has(key)) return undefined;
    const value = this.#entries.get(key);
    // Re-insert so eviction drops what has been touched least recently, not what
    // happened to be written first.
    this.#entries.delete(key);
    this.#entries.set(key, value);
    return value;
  }

  set(key, value) {
    this.#entries.delete(key);
    this.#entries.set(key, value);
    while (this.#entries.size > this.#maximumEntries) {
      this.#entries.delete(this.#entries.keys().next().value);
    }
    return this;
  }

  has(key) {
    return this.#entries.has(key);
  }

  delete(key) {
    return this.#entries.delete(key);
  }

  clear() {
    this.#entries.clear();
  }

  get size() {
    return this.#entries.size;
  }

  get maximumEntries() {
    return this.#maximumEntries;
  }
}
