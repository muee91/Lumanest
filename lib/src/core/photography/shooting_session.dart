import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_distance.dart';
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

  /// Selects the session and reviewed target that actually cover a route
  /// destination. A route opened without an active intent must not first pick
  /// a globally current session and only then try to fit its targets; doing so
  /// can discard a different session that is the real match for this place.
  static ShootingSessionTargetSelection? selectForDestination(
    Iterable<ShootingSession> sessions, {
    required GeoPoint destination,
    required DateTime now,
    String? requestedSessionId,
    String? requestedTargetId,
  }) {
    final utcNow = now.toUtc();
    final canonicalDestination = ChinaCoordinateConverter.gcj02ToWgs84(
      destination,
    );
    final candidates = <ShootingSessionTargetSelection>[];
    for (final session in sessions) {
      if (!session.endsAt.toUtc().isAfter(utcNow) ||
          session.isEvidenceExpiredAt(utcNow) ||
          requestedSessionId != null && session.id != requestedSessionId) {
        continue;
      }
      final targets = session.targetCandidates.where(
        (target) =>
            (requestedTargetId == null || target.id == requestedTargetId) &&
            target.arrivalRadiusMeters > 0 &&
            target.supportedSessions.contains(session.kind),
      );
      for (final target in targets) {
        final targetPoint = ChinaCoordinateConverter.gcj02ToWgs84(
          target.coordinate,
        );
        final distance = GeoDistance.metersBetween(
          canonicalDestination,
          targetPoint,
        );
        if (distance <= target.arrivalRadiusMeters) {
          candidates.add(
            ShootingSessionTargetSelection(
              session: session,
              target: target,
              distanceMeters: distance,
            ),
          );
        }
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((left, right) {
      final leftActive = _isActive(left.session, utcNow);
      final rightActive = _isActive(right.session, utcNow);
      if (leftActive != rightActive) return leftActive ? -1 : 1;

      final condition = _conditionRank(
        right.session.conditionBand,
      ).compareTo(_conditionRank(left.session.conditionBand));
      if (condition != 0) return condition;
      final confidence = _confidenceRank(
        right.session.confidenceBand,
      ).compareTo(_confidenceRank(left.session.confidenceBand));
      if (confidence != 0) return confidence;
      final distance = left.distanceMeters.compareTo(right.distanceMeters);
      if (distance != 0) return distance;
      final time = left.session.presentationStartsAt.compareTo(
        right.session.presentationStartsAt,
      );
      if (time != 0) return time;
      final session = left.session.id.compareTo(right.session.id);
      return session != 0 ? session : left.target.id.compareTo(right.target.id);
    });
    return candidates.first;
  }

  static bool _isActive(ShootingSession session, DateTime now) =>
      !now.isBefore(session.startsAt.toUtc()) &&
      now.isBefore(session.endsAt.toUtc());

  static int _conditionRank(ShootingConditionBand value) => switch (value) {
    ShootingConditionBand.good => 2,
    ShootingConditionBand.fair => 1,
    ShootingConditionBand.limited => 0,
  };

  static int _confidenceRank(ShootingConfidenceBand value) => switch (value) {
    ShootingConfidenceBand.high => 2,
    ShootingConfidenceBand.medium => 1,
    ShootingConfidenceBand.limited => 0,
  };
}

/// A route or fallback decision keeps the session and target bound together.
/// This prevents a later presentation-layer `first` target lookup from
/// silently opening a different reviewed location than the one that was
/// ranked by the domain layer.
class ShootingSessionTargetSelection {
  const ShootingSessionTargetSelection({
    required this.session,
    required this.target,
    required this.distanceMeters,
  });

  final ShootingSession session;
  final ShootingTarget target;
  final double distanceMeters;
}

abstract final class ShootingTargetSelector {
  /// Returns a reviewed, session-compatible target in deterministic order.
  /// Callers with an active intent must provide [requestedId]; an invalid id
  /// intentionally returns null instead of silently switching locations.
  static ShootingTarget? selectForSession(
    ShootingSession session, {
    String? requestedId,
    ShootingTravelMode? travelMode,
  }) {
    final candidates = session.targetCandidates
        .where(
          (target) =>
              target.arrivalRadiusMeters > 0 &&
              target.supportedSessions.contains(session.kind) &&
              (travelMode == null || target.accessModes.contains(travelMode)),
        )
        .toList(growable: false);
    if (requestedId != null) {
      for (final candidate in candidates) {
        if (candidate.id == requestedId) return candidate;
      }
      return null;
    }
    candidates.sort((left, right) {
      final reviewed = right.reviewedAt.compareTo(left.reviewedAt);
      if (reviewed != 0) return reviewed;
      final lead = left.leadTimeMinutes.compareTo(right.leadTimeMinutes);
      return lead != 0 ? lead : left.id.compareTo(right.id);
    });
    return candidates.firstOrNull;
  }
}

abstract final class ShootingSessionFallback {
  /// Existing secondary windows may be presented as a fallback only when the
  /// selected primary window is visibly weakening or limited. This is a copy
  /// and ranking signal; it never invents a new opportunity.
  static bool shouldOfferPlanB(ShootingSession? primary, {DateTime? now}) {
    if (primary == null) return false;
    final utcNow = (now ?? DateTime.now()).toUtc();
    return primary.conditionBand == ShootingConditionBand.limited ||
        primary.trend == ShootingTrend.weakening ||
        primary.isEvidenceExpiredAt(utcNow);
  }

  /// Shared eligibility used by Today and the detail page. Keeping this in
  /// the domain prevents the rail from drifting into a title-only Plan B.
  static bool isUsablePlanBSession(
    ShootingSession session, {
    required DateTime now,
  }) {
    final utcNow = now.toUtc();
    return session.endsAt.toUtc().isAfter(utcNow) &&
        !session.isEvidenceExpiredAt(utcNow) &&
        session.confidenceBand != ShootingConfidenceBand.limited &&
        session.conditionBand != ShootingConditionBand.limited &&
        session.targetCandidates.any(
          (target) =>
              target.arrivalRadiusMeters > 0 &&
              target.supportedSessions.contains(session.kind),
        );
  }

  /// Chooses only from sessions that are already established by the current
  /// snapshot. The fallback layer never manufactures a new opportunity and
  /// never upgrades limited or expired evidence into an action.
  static ShootingPlanBSelection? selectPlanB(
    Iterable<ShootingSession> sessions, {
    required ShootingSession primary,
    required DateTime now,
    GeoPoint? currentLocation,
  }) {
    if (!shouldOfferPlanB(primary, now: now)) return null;
    final utcNow = now.toUtc();
    final candidates = sessions
        .where(
          (session) =>
              session.id != primary.id &&
              isUsablePlanBSession(session, now: utcNow),
        )
        .expand((session) {
          final target = _bestUsableTarget(session, currentLocation);
          return target == null
              ? const <ShootingPlanBSelection>[]
              : <ShootingPlanBSelection>[target];
        })
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    candidates.sort((left, right) {
      final leftSession = left.session;
      final rightSession = right.session;
      final leftActive =
          !utcNow.isBefore(leftSession.startsAt.toUtc()) &&
          utcNow.isBefore(leftSession.endsAt.toUtc());
      final rightActive =
          !utcNow.isBefore(rightSession.startsAt.toUtc()) &&
          utcNow.isBefore(rightSession.endsAt.toUtc());
      if (leftActive != rightActive) return leftActive ? -1 : 1;

      final condition = _conditionRank(
        rightSession.conditionBand,
      ).compareTo(_conditionRank(leftSession.conditionBand));
      if (condition != 0) return condition;

      final trend = _trendRank(
        rightSession.trend,
      ).compareTo(_trendRank(leftSession.trend));
      if (trend != 0) return trend;

      final leftDistance = left.distanceMeters;
      final rightDistance = right.distanceMeters;
      if (leftDistance != null && rightDistance != null) {
        final distance = leftDistance.compareTo(rightDistance);
        if (distance != 0) return distance;
      }

      final time = leftSession.presentationStartsAt.compareTo(
        rightSession.presentationStartsAt,
      );
      return time != 0 ? time : leftSession.id.compareTo(rightSession.id);
    });
    return candidates.first;
  }

  static ShootingPlanBSelection? _bestUsableTarget(
    ShootingSession session,
    GeoPoint? currentLocation,
  ) {
    ShootingPlanBSelection? best;
    for (final target in session.targetCandidates) {
      if (target.arrivalRadiusMeters <= 0 ||
          !target.supportedSessions.contains(session.kind)) {
        continue;
      }
      double? distance;
      if (currentLocation != null) {
        try {
          final current = ChinaCoordinateConverter.gcj02ToWgs84(
            currentLocation,
          ).validate();
          final targetPoint = ChinaCoordinateConverter.gcj02ToWgs84(
            target.coordinate,
          ).validate();
          distance = GeoDistance.metersBetween(current, targetPoint);
        } on Object {
          distance = null;
        }
      }
      final candidate = ShootingPlanBSelection(
        session: session,
        target: target,
        distanceMeters: distance,
      );
      if (best == null ||
          _distanceSort(distance, best.distanceMeters) < 0 ||
          _distanceSort(distance, best.distanceMeters) == 0 &&
              target.id.compareTo(best.target.id) < 0) {
        best = candidate;
      }
    }
    return best;
  }

  static int _distanceSort(double? left, double? right) {
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  }

  static int _conditionRank(ShootingConditionBand value) => switch (value) {
    ShootingConditionBand.good => 2,
    ShootingConditionBand.fair => 1,
    ShootingConditionBand.limited => 0,
  };

  static int _trendRank(ShootingTrend value) => switch (value) {
    ShootingTrend.improving => 2,
    ShootingTrend.stable => 1,
    ShootingTrend.weakening => 0,
  };
}

/// A Plan B selection returned by the domain layer with its reviewed target
/// already bound to the chosen session.
class ShootingPlanBSelection {
  const ShootingPlanBSelection({
    required this.session,
    required this.target,
    this.distanceMeters,
  });

  final ShootingSession session;
  final ShootingTarget target;
  final double? distanceMeters;

  // Small forwarding getters keep callers that only need display metadata
  // from having to unpack the selection again.
  String get id => session.id;
  ShootingSessionKind get kind => session.kind;
  String get title => session.title;
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
        label: '查看下次窗口',
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
