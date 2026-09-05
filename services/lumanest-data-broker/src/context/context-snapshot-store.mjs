function object(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

// Process-local, bounded storage used only to bind follow-up Assistant and
// Region Brief requests to a previously issued Context snapshot. This is
// infrastructure state, not a user-facing inventory or recommendation feed.
export class ContextSnapshotStore {
  constructor({ maximumSnapshots = 24 } = {}) {
    this.maximumSnapshots = maximumSnapshots;
    this.snapshots = new Map();
  }

  rememberSnapshot(snapshot) {
    if (!object(snapshot) || typeof snapshot.contextId !== 'string') return;
    this.snapshots.set(
      snapshot.contextId,
      Object.freeze(structuredClone(snapshot)),
    );
    while (this.snapshots.size > this.maximumSnapshots) {
      this.snapshots.delete(this.snapshots.keys().next().value);
    }
  }

  snapshot(contextId) {
    return this.snapshots.get(contextId) ?? null;
  }
}
