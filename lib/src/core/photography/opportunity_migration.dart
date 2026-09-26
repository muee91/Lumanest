import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_distance.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';

class ShootingFallbackResolution {
  const ShootingFallbackResolution({required this.alternative, required this.reason});

  final ShootingSession? alternative;
  final String reason;

  bool get hasAlternative => alternative != null;
}

/// Selects an already-reviewed session from the current snapshot. It never
/// creates an opportunity and never reads a stale snapshot.
abstract final class ShootingOpportunityFallbackResolver {
  static ShootingFallbackResolution resolve({
    required ShootingSession? primary,
    required Iterable<ShootingSession> sessions,
    required DateTime now,
    bool snapshotFresh = true,
    ShootingTarget? primaryTarget,
    GeoPoint? currentLocation,
  }) {
    if (primary == null) {
      return const ShootingFallbackResolution(
        alternative: null,
        reason: '当前没有可迁移的主机会。',
      );
    }
    final utcNow = now.toUtc();
    if (!snapshotFresh) {
      return const ShootingFallbackResolution(
        alternative: null,
        reason: '当前依据已过期，暂不迁移机会。',
      );
    }
    final trigger = primary.conditionBand == ShootingConditionBand.limited
        ? '主机会条件有限'
        : primary.trend == ShootingTrend.weakening
        ? '主机会正在减弱'
        : primary.isEvidenceExpiredAt(utcNow)
        ? '主机会依据已过期'
        : null;
    if (trigger == null) {
      return const ShootingFallbackResolution(
        alternative: null,
        reason: '当前主机会仍然成立。',
      );
    }

    final candidates = sessions
        .where(
          (session) =>
              session.id != primary.id &&
              session.endsAt.toUtc().isAfter(utcNow) &&
              !session.isEvidenceExpiredAt(utcNow) &&
              session.conditionBand != ShootingConditionBand.limited &&
              session.confidenceBand != ShootingConfidenceBand.limited &&
              session.targetCandidates.any(
                (target) => target.supportedSessions.contains(session.kind),
              ),
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      return ShootingFallbackResolution(
        alternative: null,
        reason: '$trigger，暂时没有更可靠的替代窗口。',
      );
    }

    candidates.sort((left, right) {
      final leftActive = _isActive(left, utcNow) ? 0 : 1;
      final rightActive = _isActive(right, utcNow) ? 0 : 1;
      final active = leftActive.compareTo(rightActive);
      if (active != 0) return active;
      final leftTime = _sortTime(left, utcNow);
      final rightTime = _sortTime(right, utcNow);
      final time = leftTime.compareTo(rightTime);
      if (time != 0) return time;
      final leftContext = _contextDistance(left, primaryTarget, currentLocation);
      final rightContext = _contextDistance(right, primaryTarget, currentLocation);
      final context = leftContext.compareTo(rightContext);
      if (context != 0) return context;
      return left.id.compareTo(right.id);
    });
    return ShootingFallbackResolution(
      alternative: candidates.first,
      reason: '$trigger，已找到当前快照中的替代窗口。',
    );
  }

  static bool _isActive(ShootingSession session, DateTime now) =>
      !now.isBefore(session.startsAt.toUtc()) &&
      now.isBefore(session.endsAt.toUtc());

  static DateTime _sortTime(ShootingSession session, DateTime now) =>
      _isActive(session, now) ? session.endsAt.toUtc() : session.startsAt.toUtc();

  static double _contextDistance(
    ShootingSession session,
    ShootingTarget? primaryTarget,
    GeoPoint? currentLocation,
  ) {
    final primary = _normalize(primaryTarget?.coordinate);
    final location = _normalize(currentLocation);
    final distances = <double>[];
    for (final target in session.targetCandidates) {
      final point = _normalize(target.coordinate);
      if (point == null) continue;
      if (primary != null) distances.add(GeoDistance.metersBetween(primary, point));
      if (location != null) distances.add(GeoDistance.metersBetween(location, point));
    }
    return distances.isEmpty ? double.maxFinite : distances.reduce((a, b) => a < b ? a : b);
  }

  static GeoPoint? _normalize(GeoPoint? point) {
    if (point == null) return null;
    return point.coordinateSystem == CoordinateSystem.gcj02
        ? ChinaCoordinateConverter.gcj02ToWgs84(point)
        : point;
  }
}
