import 'package:luma_nest/src/core/context/context_snapshot.dart';
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
    return '$category$location · 距路线采样点约 ${stop.place.distanceMeters} m，时间为进度估算。';
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
