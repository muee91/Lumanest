import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/shooting_window/domain/shooting_window_timeline.dart';

enum RouteTimelineKind { departure, shooting, arrival }

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
    required ContextSnapshot snapshot,
    required DateTime departureAt,
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
      for (final window in ShootingWindowTimeline.build(snapshot))
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
}
