import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/photography/photography_opportunity.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/hiking_return_assessment.dart';
import 'package:luma_nest/src/features/route/domain/route_support_stop.dart';
import 'package:luma_nest/src/features/shooting_window/domain/shooting_window_timeline.dart';

enum RouteTimelineKind {
  departure,
  safety,
  support,
  elevation,
  shooting,
  shootingMissed,
  arrival,
  returnDeadline,
  estimatedReturn,
}

class RouteTimelineRisk {
  const RouteTimelineRisk({required this.id, required this.title});

  final String id;
  final String title;
}

class RouteTimelineEntry {
  const RouteTimelineEntry({
    required this.id,
    required this.kind,
    required this.label,
    required this.time,
    this.end,
    required this.description,
  });

  final String id;
  final RouteTimelineKind kind;
  final String label;
  final DateTime time;
  final DateTime? end;
  final String description;
}

abstract final class RouteTimeline {
  /// Opportunities are only route-aware when the context service has
  /// explicitly established a regional or route-wide scope. A point snapshot
  /// belongs to the current location and must not be projected along a route.
  static List<PhotographyOpportunity> eligiblePhotographyOpportunities(
    ContextSnapshot? snapshot, {
    required DateTime departureAt,
  }) {
    if (snapshot == null || snapshot.isStale) return const [];
    final departure = departureAt.toUtc();
    return snapshot.photographyOpportunities
        .where(
          (opportunity) =>
              opportunity.geoScope != PhotographyOpportunityGeoScope.point &&
              opportunity.expiresAt.toUtc().isAfter(departure),
        )
        .toList(growable: false);
  }

  static List<RouteTimelineEntry> build({
    required DrivingRoute route,
    ContextSnapshot? snapshot,
    required DateTime departureAt,
    List<RouteSupportStop> supportStops = const [],
    List<RouteTimelineRisk> routeRisks = const [],
    HikingReturnAssessment? hikingAssessment,
  }) {
    final departure = departureAt.toUtc();
    final arrival = departure.add(Duration(seconds: route.durationSeconds));
    final entries = <RouteTimelineEntry>[
      RouteTimelineEntry(
        id: 'departure',
        kind: RouteTimelineKind.departure,
        label: '出发',
        time: departure,
        description: '从当前位置出发',
      ),
      for (final risk in routeRisks)
        RouteTimelineEntry(
          id: 'risk-${risk.id}',
          kind: RouteTimelineKind.safety,
          label: '路线风险节点',
          time: departure,
          description: '${risk.title}。当前已成立，请以独立安全卡片和官方指引为准。',
        ),
      for (final stop in _representativeSupportStops(supportStops, maximum: 6))
        RouteTimelineEntry(
          id: 'support-${stop.place.id}',
          kind: RouteTimelineKind.support,
          label: stop.place.name,
          time: _atProgress(
            departure,
            route.durationSeconds,
            stop.routeProgress,
          ),
          description: _supportDescription(stop),
        ),
      if (route.travelMode == RouteTravelMode.walking &&
          route.ascentMeters != null)
        RouteTimelineEntry(
          id: 'elevation-summary',
          kind: RouteTimelineKind.elevation,
          label: '累计爬升参考',
          time: _atProgress(departure, route.durationSeconds, 0.5),
          description: route.descentMeters == null
              ? '全程累计爬升约 ${route.ascentMeters} m。'
              : '全程累计爬升约 ${route.ascentMeters} m，累计下降约 ${route.descentMeters} m。',
        ),
      for (final opportunity in eligiblePhotographyOpportunities(
        snapshot,
        departureAt: departure,
      ))
        _routeOpportunityEntry(opportunity: opportunity, arrival: arrival),
      for (final window
          in snapshot == null
              ? const <ShootingWindow>[]
              : ShootingWindowTimeline.build(snapshot))
        if (_overlaps(
          window.start.toUtc(),
          window.end.toUtc(),
          departure,
          arrival,
        ))
          RouteTimelineEntry(
            id: window.id,
            kind: RouteTimelineKind.shooting,
            label: window.label,
            time: window.start.toUtc(),
            end: window.end.toUtc(),
            description: window.description,
          ),
      RouteTimelineEntry(
        id: 'arrival',
        kind: RouteTimelineKind.arrival,
        label: '预计到达',
        time: arrival,
        description: '抵达 ${route.destinationName}',
      ),
      if (hikingAssessment?.latestReturnDeparture case final latest?)
        RouteTimelineEntry(
          id: 'latest-return-departure',
          kind: RouteTimelineKind.returnDeadline,
          label: '最晚返程参考',
          time: latest.isBefore(departure) ? departure : latest,
          description: latest.isBefore(departure)
              ? '按原路同等耗时估算，安全返程时间已经不足。'
              : '按原路同等耗时估算，建议不晚于此时从目的地返程。',
        ),
      if (hikingAssessment case final assessment?)
        RouteTimelineEntry(
          id: 'estimated-return-arrival',
          kind: RouteTimelineKind.estimatedReturn,
          label: '预计返回起点',
          time: assessment.estimatedReturnArrival,
          description: '按去程同等耗时估算，不代表已规划返程路线。',
        ),
    ];
    entries.sort((first, second) {
      final timeOrder = first.time.compareTo(second.time);
      if (timeOrder != 0) return timeOrder;
      return first.kind.index.compareTo(second.kind.index);
    });
    return List.unmodifiable(entries);
  }

  static RouteTimelineEntry _routeOpportunityEntry({
    required PhotographyOpportunity opportunity,
    required DateTime arrival,
  }) {
    final start = opportunity.startsAt.toUtc();
    final end = opportunity.expiresAt.toUtc();
    final action = _actionLabel(opportunity.primaryAction);
    final fallback = _actionLabel(opportunity.fallbackAction);
    if (!arrival.isBefore(end)) {
      return RouteTimelineEntry(
        id: 'missed-opportunity-${opportunity.id}',
        kind: RouteTimelineKind.shootingMissed,
        label: '错过 ${opportunity.title}',
        time: arrival,
        end: end,
        description:
            '预计抵达时窗口已结束；${fallback ?? '跳过这段窗口'}。仅依据已成立的${_scopeLabel(opportunity.geoScope)}机会，未推断沿途逐点天气。',
      );
    }
    final actionAt = arrival.isAfter(start) ? arrival : start;
    final timing = arrival.isAfter(start) ? '预计抵达时仍在窗口内' : '预计抵达后等待窗口开始';
    return RouteTimelineEntry(
      id: 'opportunity-${opportunity.id}',
      kind: RouteTimelineKind.shooting,
      label: opportunity.title,
      time: actionAt,
      end: end,
      description:
          '$timing；${action ?? '抵达后拍摄'}。仅依据已成立的${_scopeLabel(opportunity.geoScope)}机会，未推断沿途逐点天气。',
    );
  }

  static String _scopeLabel(PhotographyOpportunityGeoScope scope) =>
      switch (scope) {
        PhotographyOpportunityGeoScope.route => '路线范围',
        PhotographyOpportunityGeoScope.regional => '区域范围',
        PhotographyOpportunityGeoScope.point => '点位范围',
      };

  static String? _actionLabel(ContextAction? action) => switch (action) {
    null => null,
    ContextAction.openShootingWindow => '抵达后查看拍摄建议',
    ContextAction.openExplore => '抵达后查看备选机位',
    ContextAction.openRoute => '保留路线并观察',
    _ => '查看拍摄建议',
  };

  static bool _overlaps(
    DateTime start,
    DateTime end,
    DateTime departure,
    DateTime arrival,
  ) => !end.isBefore(departure) && !start.isAfter(arrival);

  static DateTime _atProgress(
    DateTime departure,
    int durationSeconds,
    double progress,
  ) {
    final bounded = progress.clamp(0.05, 0.95);
    return departure.add(
      Duration(milliseconds: (durationSeconds * 1000 * bounded).round()),
    );
  }

  static String _supportDescription(RouteSupportStop stop) {
    final category = switch (stop.place.category) {
      NearbyPlaceCategory.fuel => '加油',
      NearbyPlaceCategory.food => '餐饮',
      NearbyPlaceCategory.supply => '补给',
      _ => stop.place.category.label,
    };
    final address = stop.place.address;
    final location = address == null ? '' : ' · $address';
    final freshness = stop.isCached ? ' · 离线缓存' : '';
    return '$category$location · 距路线采样点约 ${stop.place.distanceMeters} m，时间为进度估算$freshness。';
  }

  static List<RouteSupportStop> _representativeSupportStops(
    List<RouteSupportStop> stops, {
    required int maximum,
  }) {
    if (stops.length <= maximum) return stops;
    final indexes = <int>{};
    for (var index = 0; index < maximum; index++) {
      indexes.add((index * (stops.length - 1) / (maximum - 1)).round());
    }
    return indexes.map((index) => stops[index]).toList(growable: false);
  }
}
