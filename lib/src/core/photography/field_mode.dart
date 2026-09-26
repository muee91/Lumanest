import 'package:luma_nest/src/core/photography/shooting_session.dart';

/// Pure timing helpers used by the foreground Field Mode presentation.
abstract final class FieldModeCountdown {
  static Duration remaining(ShootingSessionPhase phase, DateTime now) {
    return phase.isActiveAt(now)
        ? phase.endsAt.difference(now)
        : phase.startsAt.difference(now);
  }

  static bool usesSecondPrecision(Duration remaining) =>
      remaining > Duration.zero && remaining <= const Duration(minutes: 10);
}
