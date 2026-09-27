import 'package:luma_nest/src/core/photography/shooting_session.dart';

/// Selects at most three already-established evidence factors for Field Mode.
///
/// This is intentionally pure: it only reorders factors already present on the
/// session and never creates a weather value or fills a missing observation.
abstract final class FieldEnvironmentSelector {
  static List<ShootingSessionFactor> select(
    ShootingSession session, {
    int maxFacts = 3,
  }) {
    if (maxFacts <= 0 || session.factors.isEmpty) return const [];

    final limit = maxFacts > 3 ? 3 : maxFacts;
    final priorities = _priorities(session.kind);
    final ranked = <({ShootingSessionFactor factor, int index, int rank})>[];
    for (var index = 0; index < session.factors.length; index++) {
      final factor = session.factors[index];
      final key = _canonicalKey(factor.id, factor.label);
      final priority = priorities.indexOf(key);
      ranked.add((
        factor: factor,
        index: index,
        rank: priority < 0 ? _fallbackRank(factor.effect) : priority,
      ));
    }
    ranked.sort((left, right) {
      final rank = left.rank.compareTo(right.rank);
      return rank != 0 ? rank : left.index.compareTo(right.index);
    });
    return List.unmodifiable(
      ranked.take(limit).map((entry) => entry.factor),
    );
  }

  static List<String> _priorities(ShootingSessionKind kind) => switch (kind) {
    ShootingSessionKind.waterMorning ||
    ShootingSessionKind.waterEvening => const [
      'wind',
      'precipitation',
      'cloud',
    ],
    ShootingSessionKind.mountainMorning ||
    ShootingSessionKind.mountainEvening => const [
      'low_cloud',
      'cloud',
      'visibility',
      'light',
    ],
    ShootingSessionKind.cityBlueHour => const [
      'cloud',
      'visibility',
      'light',
    ],
    ShootingSessionKind.cityAfterRain => const [
      'precipitation',
      'cloud',
      'visibility',
    ],
    ShootingSessionKind.desertSideLight => const [
      'visibility',
      'cloud',
      'wind',
    ],
    ShootingSessionKind.routeLightWindow => const [
      'cloud',
      'precipitation',
      'visibility',
    ],
    ShootingSessionKind.generalMorning ||
    ShootingSessionKind.generalEvening => const [
      'cloud',
      'visibility',
      'light',
      'wind',
    ],
  };

  static int _fallbackRank(ShootingFactorEffect effect) => switch (effect) {
    ShootingFactorEffect.limiting => 100,
    ShootingFactorEffect.supporting => 200,
    ShootingFactorEffect.neutral => 300,
  };

  static String _canonicalKey(String id, String label) {
    final value = '${id.toLowerCase()} ${label.toLowerCase()}';
    if (value.contains('low_cloud') ||
        value.contains('low cloud') ||
        value.contains('低云')) {
      return 'low_cloud';
    }
    if (value.contains('precip') ||
        value.contains('rain') ||
        value.contains('降水') ||
        value.contains('雨')) {
      return 'precipitation';
    }
    if (value.contains('visibility') ||
        value.contains('vis') ||
        value.contains('能见度')) {
      return 'visibility';
    }
    if (value.contains('cloud') || value.contains('云')) return 'cloud';
    if (value.contains('wind') || value.contains('风')) return 'wind';
    if (value.contains('light') ||
        value.contains('solar') ||
        value.contains('光')) {
      return 'light';
    }
    return 'unknown';
  }
}
