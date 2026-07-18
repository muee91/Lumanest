import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';

/// Bounded local-only outcome signal. Unknown historic IDs remain neutral.
abstract final class LocalCreativeAffinity {
  static Map<String, double> fromResults(
    Iterable<ShootingSessionResult> results, {
    DateTime? now,
  }) {
    final moment = (now ?? DateTime.now()).toUtc();
    final scores = <String, double>{};
    for (final result in results) {
      final kind = _kind(result.kind);
      final age = moment
          .difference(result.recordedAt.toUtc())
          .inDays
          .clamp(0, 365);
      final decay = 1 / (1 + age / 45);
      final signal = switch (result.outcome) {
        ShootingSessionOutcome.captured => 1.0,
        ShootingSessionOutcome.conditionsDidNotAppear ||
        ShootingSessionOutcome.arrivedLate => -0.35,
        ShootingSessionOutcome.didNotGo => -0.15,
      };
      scores[kind] = (scores[kind] ?? 0) + signal * decay;
    }
    return {
      for (final entry in scores.entries)
        if (entry.value != 0)
          entry.key: (entry.value / 3).clamp(-1, 1).toDouble(),
    };
  }

  static String _kind(ShootingSessionKind kind) => switch (kind) {
    ShootingSessionKind.waterMorning => 'session.water.morning',
    ShootingSessionKind.waterEvening => 'session.water.evening',
    ShootingSessionKind.mountainMorning => 'session.mountain.morning',
    ShootingSessionKind.mountainEvening => 'session.mountain.evening',
    ShootingSessionKind.cityBlueHour => 'session.city.blue_hour',
    ShootingSessionKind.cityAfterRain => 'session.city.after_rain',
    ShootingSessionKind.desertSideLight => 'session.desert.side_light',
    ShootingSessionKind.routeLightWindow => 'session.route.light_window',
  };
}
