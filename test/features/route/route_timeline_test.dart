import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/route_timeline.dart';

void main() {
  test('orders departure, overlapping shooting windows and arrival', () {
    final now = DateTime.utc(2026, 7, 13, 10);
    final sunset = now.add(const Duration(minutes: 50));
    final snapshot = _snapshot(
      now: now,
      sunrise: now.subtract(const Duration(hours: 8)),
      sunset: sunset,
    );
    final route = _route(duration: const Duration(hours: 2));

    final timeline = RouteTimeline.build(
      route: route,
      snapshot: snapshot,
      departureAt: now,
    );

    expect(timeline.first.kind, RouteTimelineKind.departure);
    expect(timeline.last.kind, RouteTimelineKind.arrival);
    expect(
      timeline
          .where((item) => item.kind == RouteTimelineKind.shooting)
          .map((item) => item.id),
      ['sunset', 'blue-hour'],
    );
  });

  test('keeps departure and arrival when solar data is unavailable', () {
    final now = DateTime.utc(2026, 7, 13, 10);
    final timeline = RouteTimeline.build(
      route: _route(duration: const Duration(minutes: 30)),
      snapshot: _snapshot(now: now),
      departureAt: now,
    );

    expect(timeline.map((item) => item.kind), [
      RouteTimelineKind.departure,
      RouteTimelineKind.arrival,
    ]);
  });
}

DrivingRoute _route({required Duration duration}) => DrivingRoute(
  destinationName: '湖岸机位',
  distanceMeters: 5000,
  durationSeconds: duration.inSeconds,
  tollsYuan: 0,
  polyline: const [],
);

ContextSnapshot _snapshot({
  required DateTime now,
  DateTime? sunrise,
  DateTime? sunset,
}) => ContextSnapshot(
  id: 'route-context',
  observedAt: now,
  expiresAt: now.add(const Duration(minutes: 15)),
  primaryScene: SceneType.lake,
  dayPhase: DayPhase.sunset,
  weather: WeatherType.clear,
  activeRoute: true,
  sunrise: sunrise,
  sunset: sunset,
);
