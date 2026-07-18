import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
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
  /// A shooting session enters a route timeline only when it has a reviewed
  /// target. Sessions without targets belong to observation, not navigation.
  static List<ShootingSession> eligibleShootingSessions(
    ContextSnapshot? snapshot, {
    required DateTime departureAt,
  }) {
    if (snapshot == null || snapshot.isStale) return const [];
    final departure = departureAt.toUtc();
    return snapshot.shootingSessions
        .where(
          (session) =>
              session.targetCandidates.isNotEmpty &&
              session.endsAt.toUtc().isAfter(departure),
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
      for (final session in eligibleShootingSessions(
        snapshot,
        departureAt: departure,
      ))
        _routeSessionEntry(session: session, arrival: arrival),
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

  static RouteTimelineEntry _routeSessionEntry({
    required ShootingSession session,
    required DateTime arrival,
  }) {
    final start = session.startsAt.toUtc();
    final end = session.endsAt.toUtc();
    if (!arrival.isBefore(end)) {
      return RouteTimelineEntry(
        id: 'missed-session-${session.id}',
        kind: RouteTimelineKind.shootingMissed,
        label: '错过 ${session.title}',
        time: arrival,
        end: end,
        description: '预计抵达时会话已结束，跳过这次窗口并继续路线。',
      );
    }
    final actionAt = arrival.isAfter(start) ? arrival : start;
    final timing = arrival.isAfter(start) ? '预计抵达时仍在窗口内' : '预计抵达后等待窗口开始';
    return RouteTimelineEntry(
      id: 'session-${session.id}',
      kind: RouteTimelineKind.shooting,
      label: session.title,
      time: actionAt,
      end: end,
      description: '$timing；抵达后查看拍摄建议。仅使用已审核目标与当前会话证据。',
    );
  }

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
