import 'package:luma_nest/src/core/context/context_snapshot.dart';

/// Decides when the app should renew its live environment snapshot while it
/// remains in the foreground. The snapshot contract already supplies the
/// authoritative expiry; the local calendar boundary is an additional UI
/// boundary because day-sensitive photography guidance must not carry a
/// yesterday label into a new day.
abstract final class EnvironmentRefreshPolicy {
  static const retryDelay = Duration(minutes: 1);

  /// Returns the next foreground refresh deadline in UTC.
  ///
  /// A snapshot that is already expired is retried after a bounded delay,
  /// rather than immediately, so a temporarily unavailable upstream cannot
  /// create a request loop.
  static DateTime nextRefreshAt({
    required ContextSnapshot snapshot,
    required DateTime now,
  }) {
    final localNow = now.toLocal();
    final nextLocalMidnight = DateTime(
      localNow.year,
      localNow.month,
      localNow.day + 1,
    ).toUtc();
    final expiresAt = snapshot.expiresAt.toUtc();
    final nowUtc = localNow.toUtc();
    if (!expiresAt.isAfter(nowUtc)) return nowUtc.add(retryDelay);
    return expiresAt.isBefore(nextLocalMidnight)
        ? expiresAt
        : nextLocalMidnight;
  }

  /// A foreground resume only requests fresh data when the existing snapshot
  /// has expired or belongs to an earlier local calendar day. Short task
  /// switches keep the cached state and avoid unnecessary location/network
  /// work.
  static bool needsRefreshOnResume({
    required ContextSnapshot? snapshot,
    required DateTime now,
  }) {
    if (snapshot == null) return true;
    final localNow = now.toLocal();
    if (!snapshot.expiresAt.toUtc().isAfter(localNow.toUtc())) return true;
    final generatedAt = (snapshot.remoteGeneratedAt ?? snapshot.observedAt)
        .toLocal();
    return generatedAt.year != localNow.year ||
        generatedAt.month != localNow.month ||
        generatedAt.day != localNow.day;
  }
}
