import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/photography/equipment_capability.dart';

enum ShootingSessionKind {
  generalMorning,
  generalEvening,
  waterMorning,
  waterEvening,
  mountainMorning,
  mountainEvening,
  cityBlueHour,
  cityAfterRain,
  desertSideLight,
  routeLightWindow,
}

enum ShootingPhaseKind {
  morningBlueHour,
  sunrise,
  morningMist,
  reflection,
  warmLight,
  sunset,
  blueHour,
  artificialLights,
  rainEnding,
  wetReflection,
  desertSideLight,
  texture,
  approach,
  safeStop,
  shoot,
  rejoinRoute,
  returnWindow,
  sessionEnd,
}

enum ShootingConditionBand { good, fair, limited }

enum ShootingConfidenceBand { high, medium, limited }

enum ShootingTrend { improving, stable, weakening }

enum ShootingFactorEffect { supporting, neutral, limiting }

enum ShootingTravelMode { driving, walking }

enum ShootingShorelineSide {
  north,
  northeast,
  east,
  southeast,
  south,
  southwest,
  west,
  northwest,
}

enum ShootingSessionOutcome {
  captured,
  conditionsDidNotAppear,
  arrivedLate,
  didNotGo,
}

enum ShootingSessionOutcomeReason { wind, cloud, precipitation, target }

class ShootingSessionFactor {
  const ShootingSessionFactor({
    required this.id,
    required this.effect,
    required this.label,
    required this.value,
    required this.sourceAt,
  });

  final String id;
  final ShootingFactorEffect effect;
  final String label;
  final String value;
  final DateTime sourceAt;
}

class ShootingSessionTrendSample {
  const ShootingSessionTrendSample({
    required this.at,
    required this.conditionIndex,
    required this.windSpeedMps,
    required this.precipitationMm,
    this.cloudCoverPercent,
  });

  final DateTime at;
  final int conditionIndex;
  final double? cloudCoverPercent;
  final double windSpeedMps;
  final double precipitationMm;
}

class ShootingSessionPhase {
  const ShootingSessionPhase({
    required this.kind,
    required this.startsAt,
    required this.peaksAt,
    required this.endsAt,
    required this.conditionBand,
    required this.directionDegrees,
  });

  final ShootingPhaseKind kind;
  final DateTime startsAt;
  final DateTime peaksAt;
  final DateTime endsAt;
  final ShootingConditionBand conditionBand;
  final double directionDegrees;

  bool isActiveAt(DateTime now) =>
      !now.isBefore(startsAt) && now.isBefore(endsAt);
}

class ShootingTarget {
  ShootingTarget({
    required this.id,
    required this.name,
    required this.coordinate,
    required Iterable<ShootingSessionKind> supportedSessions,
    required this.viewBearingDegrees,
    required this.bearingToleranceDegrees,
    required Iterable<ShootingTravelMode> accessModes,
    required this.leadTimeMinutes,
    required this.arrivalRadiusMeters,
    required this.shorelineSide,
    required this.reviewedAt,
    required this.reviewReference,
    required this.sourceAttribution,
    required this.sourceLicense,
    required this.sourceUrl,
  }) : supportedSessions = Set.unmodifiable(supportedSessions),
       accessModes = Set.unmodifiable(accessModes);

  final String id;
  final String name;
  final GeoPoint coordinate;
  final Set<ShootingSessionKind> supportedSessions;
  final double viewBearingDegrees;
  final double bearingToleranceDegrees;
  final Set<ShootingTravelMode> accessModes;
  final int leadTimeMinutes;
  final int arrivalRadiusMeters;
  final ShootingShorelineSide shorelineSide;
  final DateTime reviewedAt;
  final Uri reviewReference;
  final String sourceAttribution;
  final String sourceLicense;
  final Uri sourceUrl;
}

class ShootingSession {
  ShootingSession({
    required this.id,
    required this.kind,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.primaryPhase,
    required this.conditionBand,
    required this.confidenceBand,
    required this.trend,
    required Iterable<ShootingSessionPhase> phases,
    required Iterable<ShootingSessionFactor> factors,
    required Iterable<ShootingSessionTrendSample> trendSamples,
    required Iterable<ShootingTarget> targetCandidates,
    Iterable<EquipmentCapability> recommendedCapabilities = const [],
    required this.ruleVersion,
    required this.expiresAt,
  }) : phases = List.unmodifiable(phases),
       factors = List.unmodifiable(factors),
       trendSamples = List.unmodifiable(trendSamples),
       targetCandidates = List.unmodifiable(targetCandidates),
       recommendedCapabilities = Set.unmodifiable(recommendedCapabilities);

  final String id;
  final ShootingSessionKind kind;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final ShootingPhaseKind primaryPhase;
  final ShootingConditionBand conditionBand;
  final ShootingConfidenceBand confidenceBand;
  final ShootingTrend trend;
  final List<ShootingSessionPhase> phases;
  final List<ShootingSessionFactor> factors;
  final List<ShootingSessionTrendSample> trendSamples;
  final List<ShootingTarget> targetCandidates;

  /// Optional preparation advice. It never changes the environmental verdict.
  final Set<EquipmentCapability> recommendedCapabilities;
  final String ruleVersion;

  /// Evidence freshness, independent from the stable solar window.
  final DateTime expiresAt;

  ShootingSessionPhase get primaryPhaseValue =>
      phases.firstWhere((phase) => phase.kind == primaryPhase);

  /// The user-visible window is the primary, evidence-bearing phase shown by
  /// the Today card. [endsAt] remains the broader session lifecycle bound for
  /// selection, notifications and subsequent phases.
  DateTime get presentationStartsAt => primaryPhaseValue.startsAt;

  DateTime get presentationEndsAt => primaryPhaseValue.endsAt;

  bool isEvidenceExpiredAt(DateTime now) => !expiresAt.isAfter(now);

  /// Foreground watch mode is useful only shortly before an actionable
  /// window. Keeping the lead time here prevents pages from independently
  /// offering an hours-long (or cross-day) watch for the same session.
  bool canStartWatchingAt(
    DateTime now, {
    Duration leadTime = const Duration(hours: 3),
  }) {
    final utcNow = now.toUtc();
    return utcNow.isBefore(endsAt) && !startsAt.isAfter(utcNow.add(leadTime));
  }
}

abstract final class ShootingSessionSelector {
  /// Chooses the active session first, otherwise the nearest upcoming one.
  /// A requested id wins only while that session has not ended.
  static ShootingSession? select(
    Iterable<ShootingSession> sessions, {
    required DateTime now,
    String? requestedId,
  }) {
    final utcNow = now.toUtc();
    final available = sessions
        .where((session) => session.endsAt.isAfter(utcNow))
        .toList(growable: false);
    if (requestedId != null) {
      for (final session in available) {
        if (session.id == requestedId) return session;
      }
    }
    final active =
        available
            .where(
              (session) =>
                  !utcNow.isBefore(session.startsAt) &&
                  utcNow.isBefore(session.endsAt),
            )
            .toList(growable: false)
          ..sort((left, right) => left.endsAt.compareTo(right.endsAt));
    if (active.isNotEmpty) return active.first;
    available.sort((left, right) {
      final time = left.startsAt.compareTo(right.startsAt);
      return time != 0 ? time : left.id.compareTo(right.id);
    });
    return available.firstOrNull;
  }
}

enum ShootingExecutionState {
  observe,
  planRoute,
  waitToDepart,
  departNow,
  waitAtTarget,
  shootNow,
  tooLate,
  ended,
}

class ShootingExecutionDecision {
  const ShootingExecutionDecision({
    required this.state,
    required this.label,
    required this.reason,
    this.phase,
    this.departureDeadline,
  });

  final ShootingExecutionState state;
  final String label;
  final String reason;
  final ShootingSessionPhase? phase;
  final DateTime? departureDeadline;
}

abstract final class ShootingExecutionResolver {
  static ShootingExecutionDecision resolve({
    required ShootingSession session,
    required DateTime now,
    ShootingTarget? target,
    Duration? routeDuration,
    bool atTarget = false,
  }) {
    if (!now.isBefore(session.endsAt)) {
      return const ShootingExecutionDecision(
        state: ShootingExecutionState.ended,
        label: '记录结果',
        reason: '本次拍摄窗口已经结束。',
      );
    }
    if (session.isEvidenceExpiredAt(now) ||
        session.confidenceBand == ShootingConfidenceBand.limited ||
        session.conditionBand == ShootingConditionBand.limited) {
      return const ShootingExecutionDecision(
        state: ShootingExecutionState.observe,
        label: '查看依据',
        reason: '当前数据只适合观察，不建议据此出发。',
      );
    }
    if (atTarget) {
      final active = session.phases
          .where((phase) => phase.isActiveAt(now))
          .firstOrNull;
      if (active != null) {
        return ShootingExecutionDecision(
          state: ShootingExecutionState.shootNow,
          label: '现在拍摄',
          reason: '已经进入${_phaseLabel(active.kind)}阶段。',
          phase: active,
        );
      }
      final next = session.phases
          .where((phase) => phase.startsAt.isAfter(now))
          .firstOrNull;
      return ShootingExecutionDecision(
        state: ShootingExecutionState.waitAtTarget,
        label: '继续等待',
        reason: next == null ? '等待现场条件变化。' : '下一阶段是${_phaseLabel(next.kind)}。',
        phase: next,
      );
    }
    if (target == null) {
      return const ShootingExecutionDecision(
        state: ShootingExecutionState.observe,
        label: '查看时间轴',
        reason: '附近暂无经过审核的推荐机位。',
      );
    }
    if (routeDuration == null) {
      return const ShootingExecutionDecision(
        state: ShootingExecutionState.planRoute,
        label: '计算路线',
        reason: '获取真实路程后才能判断最晚出发时间。',
      );
    }

    final lead = Duration(minutes: target.leadTimeMinutes);
    for (final phase in session.phases.where(
      (phase) => phase.conditionBand != ShootingConditionBand.limited,
    )) {
      final deadline = phase.startsAt.subtract(routeDuration + lead);
      if (!deadline.isBefore(now)) {
        final imminent =
            deadline.difference(now) <= const Duration(minutes: 10);
        return ShootingExecutionDecision(
          state: imminent
              ? ShootingExecutionState.departNow
              : ShootingExecutionState.waitToDepart,
          label: imminent ? '立即出发' : '按时出发',
          reason: imminent ? '已接近最晚出发时间。' : '仍有时间准备器材。',
          phase: phase,
          departureDeadline: deadline,
        );
      }
    }
    return const ShootingExecutionDecision(
      state: ShootingExecutionState.tooLate,
      label: '查看下次窗口',
      reason: '按当前路程已无法在有效阶段开始前到达。',
    );
  }

  static String _phaseLabel(ShootingPhaseKind phase) => switch (phase) {
    ShootingPhaseKind.morningBlueHour => '晨间蓝调',
    ShootingPhaseKind.sunrise => '日出',
    ShootingPhaseKind.morningMist => '晨雾',
    ShootingPhaseKind.reflection => '倒影',
    ShootingPhaseKind.warmLight => '暖光',
    ShootingPhaseKind.sunset => '日落',
    ShootingPhaseKind.blueHour => '蓝调',
    ShootingPhaseKind.artificialLights => '灯光亮起',
    ShootingPhaseKind.rainEnding => '降水结束',
    ShootingPhaseKind.wetReflection => '湿地反光',
    ShootingPhaseKind.desertSideLight => '荒漠侧光',
    ShootingPhaseKind.texture => '地表纹理',
    ShootingPhaseKind.approach => '接近目标',
    ShootingPhaseKind.safeStop => '安全停靠',
    ShootingPhaseKind.shoot => '拍摄',
    ShootingPhaseKind.rejoinRoute => '返回路线',
    ShootingPhaseKind.returnWindow => '返程窗口',
    ShootingPhaseKind.sessionEnd => '会话结束',
  };
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
