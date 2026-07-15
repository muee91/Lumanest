import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/hiking_return_assessment.dart';
import 'package:luma_nest/src/features/route/domain/route_support_stop.dart';
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

  test('merges support, route risk, elevation and hiking return nodes', () {
    final now = DateTime.utc(2026, 7, 13, 10);
    final route = DrivingRoute(
      destinationName: '山谷营地',
      distanceMeters: 10000,
      durationSeconds: const Duration(hours: 2).inSeconds,
      tollsYuan: 0,
      polyline: const [],
      travelMode: RouteTravelMode.walking,
      ascentMeters: 420,
      descentMeters: 160,
    );
    final timeline = RouteTimeline.build(
      route: route,
      departureAt: now,
      supportStops: const [
        RouteSupportStop(
          place: NearbyPlace(
            id: 'supply-1',
            name: '山脚补给站',
            category: NearbyPlaceCategory.supply,
            point: GeoPoint(latitude: 30, longitude: 120),
            distanceMeters: 180,
          ),
          routeProgress: 0.25,
        ),
      ],
      routeRisks: const [RouteTimelineRisk(id: 'route-wind', title: '路线范围有强风')],
      hikingAssessment: HikingReturnAssessment(
        outboundArrival: now.add(const Duration(hours: 2)),
        estimatedReturnArrival: now.add(const Duration(hours: 4)),
        latestReturnDeparture: now.add(const Duration(hours: 3)),
        risk: HikingReturnRisk.beforeSunset,
      ),
    );

    expect(timeline.map((entry) => entry.kind), [
      RouteTimelineKind.departure,
      RouteTimelineKind.safety,
      RouteTimelineKind.support,
      RouteTimelineKind.elevation,
      RouteTimelineKind.arrival,
      RouteTimelineKind.returnDeadline,
      RouteTimelineKind.estimatedReturn,
    ]);
    expect(
      timeline
          .singleWhere((entry) => entry.kind == RouteTimelineKind.support)
          .time,
      now.add(const Duration(minutes: 30)),
    );
    expect(timeline.any((entry) => entry.description.contains('进度估算')), isTrue);
    expect(
      timeline.any((entry) => entry.description.contains('不代表已规划返程路线')),
      isTrue,
    );
  });

  test('limits support nodes while preserving route-wide coverage', () {
    final now = DateTime.utc(2026, 7, 13, 10);
    final stops = List.generate(
      9,
      (index) => RouteSupportStop(
        place: NearbyPlace(
          id: 'stop-$index',
          name: '补给 $index',
          category: NearbyPlaceCategory.supply,
          point: GeoPoint(latitude: 30 + index / 100, longitude: 120),
          distanceMeters: 100,
        ),
        routeProgress: index / 8,
      ),
    );

    final timeline = RouteTimeline.build(
      route: _route(duration: const Duration(hours: 2)),
      departureAt: now,
      supportStops: stops,
    );
    final support = timeline
        .where((entry) => entry.kind == RouteTimelineKind.support)
        .toList();

    expect(support, hasLength(6));
    expect(support.first.id, 'support-stop-0');
    expect(support.last.id, 'support-stop-8');
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
