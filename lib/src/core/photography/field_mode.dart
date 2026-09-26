import 'package:luma_nest/src/core/photography/shooting_session.dart';

/// Pure timing helpers used by the foreground Field Mode presentation.
abstract final class FieldModeCountdown {
  static Duration remaining(ShootingSessionPhase phase, DateTime now) {
    if (phase.isActiveAt(now)) return phase.endsAt.difference(now);
    if (now.isBefore(phase.startsAt)) return phase.startsAt.difference(now);
    return Duration.zero;
  }

  static bool usesSecondPrecision(Duration remaining) =>
      remaining > Duration.zero && remaining <= const Duration(minutes: 10);
}
