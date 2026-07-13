export class AuditLog {
  #entries = [];
  #maximumEntries;
  #now;

  constructor({ maximumEntries = 200, now = () => new Date() } = {}) {
    this.#maximumEntries = maximumEntries;
    this.#now = now;
  }

  record({ remoteAddress, operation, fields = [], result }) {
    this.#entries.push(Object.freeze({
      timestamp: this.#now().toISOString(),
      remoteAddress,
      operation,
      fields: [...fields],
      result,
    }));
    if (this.#entries.length > this.#maximumEntries) this.#entries.shift();
  }

  list() {
    return this.#entries.map((entry) => ({ ...entry, fields: [...entry.fields] })).reverse();
  }
}
