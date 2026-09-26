import 'package:luma_nest/src/core/photography/shooting_session.dart';

/// A factor already present in the reviewed session, selected for quick use in
/// Field Mode. No value is derived or filled in when the source is missing.
typedef FieldEnvironmentFact = ShootingSessionFactor;

abstract final class FieldEnvironmentSelector {
  static List<FieldEnvironmentFact> select({
    required ShootingSession session,
    ShootingSessionPhase? phase,
    int limit = 3,
  }) {
    if (limit <= 0) return const [];
    final priorities = _priorities(session.kind);
    final ranked = <_RankedFactor>[];
    for (var index = 0; index < session.factors.length; index++) {
      final factor = session.factors[index];
      final key = _canonicalKey(factor);
      final priority = priorities.indexOf(key);
      final fallback = priority == -1
          ? _fallbackRank(factor, phase: phase)
          : priority;
      ranked.add(_RankedFactor(factor, fallback, index));
    }
    ranked.sort((left, right) {
      final rank = left.rank.compareTo(right.rank);
      if (rank != 0) return rank;
      final effect = _effectRank(left.factor.effect).compareTo(
        _effectRank(right.factor.effect),
      );
      if (effect != 0) return effect;
      return left.index.compareTo(right.index);
    });
    return ranked
        .take(limit)
        .map((entry) => entry.factor)
        .toList(growable: false);
  }

  static List<String> _priorities(ShootingSessionKind kind) => switch (kind) {
    ShootingSessionKind.waterMorning ||
    ShootingSessionKind.waterEvening => const ['wind', 'precipitation', 'cloud'],
    ShootingSessionKind.mountainMorning ||
    ShootingSessionKind.mountainEvening => const [
      'lowCloud',
      'cloud',
      'visibility',
      'light',
    ],
    ShootingSessionKind.cityBlueHour => const ['cloud', 'visibility', 'light'],
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
      'wind',
      'precipitation',
      'light',
    ],
  };

  static String _canonicalKey(ShootingSessionFactor factor) {
    final id = factor.id.trim().toLowerCase().replaceAll('_', '').replaceAll('-', '');
    if (id == 'lowcloud' || id == 'lowcloudcover') return 'lowCloud';
    if (id.contains('precip') || id.contains('rain')) return 'precipitation';
    if (id.contains('visibility') || id.contains('vis')) return 'visibility';
    if (id.contains('cloud')) return 'cloud';
    if (id.contains('wind')) return 'wind';
    if (id.contains('light') || id.contains('solar')) return 'light';
    return '';
  }

  static int _fallbackRank(
    ShootingSessionFactor factor, {
    ShootingSessionPhase? phase,
  }) {
    if (phase?.conditionBand == ShootingConditionBand.limited &&
        factor.effect == ShootingFactorEffect.limiting) {
      return 99;
    }
    return switch (factor.effect) {
      ShootingFactorEffect.supporting => 100,
      ShootingFactorEffect.neutral => 110,
      ShootingFactorEffect.limiting => 120,
    };
  }

  static int _effectRank(ShootingFactorEffect effect) => switch (effect) {
    ShootingFactorEffect.supporting => 0,
    ShootingFactorEffect.neutral => 1,
    ShootingFactorEffect.limiting => 2,
  };
}

class _RankedFactor {
  const _RankedFactor(this.factor, this.rank, this.index);
  final ShootingSessionFactor factor;
  final int rank;
  final int index;
}
