import 'package:luma_nest/src/core/context/context_snapshot.dart';

abstract interface class ContextCache {
  Future<ContextSnapshot?> readLatest();

  Future<void> write(ContextSnapshot snapshot);

  Future<void> clear();
}

/// Compares two snapshots to decide whether [candidate] may replace the
/// [current] cached entry.
///
/// The monotonic version is [ContextSnapshot.remoteGeneratedAt] when both
/// snapshots carry one, otherwise [ContextSnapshot.expiresAt]. A strictly
/// older candidate is rejected so a late-arriving write from an earlier
/// request cannot overwrite a fresher cache state. Equal versions are
/// allowed to update so non-versioned fields can refresh.
bool canReplaceCachedSnapshot(
  ContextSnapshot candidate,
  ContextSnapshot current,
) {
  final candidateGeneratedAt = candidate.remoteGeneratedAt;
  final currentGeneratedAt = current.remoteGeneratedAt;
  final candidateVersion =
      candidateGeneratedAt != null && currentGeneratedAt != null
      ? candidateGeneratedAt
      : candidate.expiresAt;
  final currentVersion =
      candidateGeneratedAt != null && currentGeneratedAt != null
      ? currentGeneratedAt
      : current.expiresAt;
  return !candidateVersion.isBefore(currentVersion);
}

class InMemoryContextCache implements ContextCache {
  ContextSnapshot? _latest;

  @override
  Future<ContextSnapshot?> readLatest() async => _latest;

  @override
  Future<void> write(ContextSnapshot snapshot) async {
    final latest = _latest;
    if (latest != null && !canReplaceCachedSnapshot(snapshot, latest)) return;
    _latest = snapshot;
  }

  @override
  Future<void> clear() async {
    _latest = null;
  }
}
