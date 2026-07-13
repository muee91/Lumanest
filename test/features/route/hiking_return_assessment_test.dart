import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/hiking_return_assessment.dart';

void main() {
  test('warns when an immediate out-and-back estimate crosses sunset', () {
    final now = DateTime.utc(2026, 7, 13, 10);
    final route = _walkingRoute(const Duration(hours: 1));
    final assessment = HikingReturnAssessment.build(
      route: route,
      snapshot: _snapshot(now, sunset: now.add(const Duration(minutes: 90))),
      departureAt: now,
    );

    expect(assessment?.risk, HikingReturnRisk.afterSunset);
    expect(
      assessment?.latestReturnDeparture,
      now.add(const Duration(minutes: 30)),
    );
  });

  test('does not claim a daylight result without sunset data', () {
    final now = DateTime.utc(2026, 7, 13, 10);
    final assessment = HikingReturnAssessment.build(
      route: _walkingRoute(const Duration(minutes: 30)),
      snapshot: _snapshot(now),
      departureAt: now,
    );

    expect(assessment?.risk, HikingReturnRisk.unknown);
    expect(assessment?.latestReturnDeparture, isNull);
  });

  test('does not create a hiking assessment for driving routes', () {
    final now = DateTime.utc(2026, 7, 13, 10);
    final driving = DrivingRoute(
      destinationName: '机位',
      distanceMeters: 1000,
      durationSeconds: 300,
      tollsYuan: 0,
      polyline: const [],
    );
    expect(
      HikingReturnAssessment.build(
        route: driving,
        snapshot: _snapshot(now),
        departureAt: now,
      ),
      isNull,
    );
  });
}

DrivingRoute _walkingRoute(Duration duration) => DrivingRoute(
  destinationName: '徒步机位',
  distanceMeters: 3000,
  durationSeconds: duration.inSeconds,
  tollsYuan: 0,
  polyline: const [],
  travelMode: RouteTravelMode.walking,
);

ContextSnapshot _snapshot(DateTime now, {DateTime? sunset}) => ContextSnapshot(
  id: 'hiking-context',
  observedAt: now,
  expiresAt: now.add(const Duration(minutes: 15)),
  primaryScene: SceneType.hiking,
  dayPhase: DayPhase.day,
  weather: WeatherType.clear,
  activeRoute: true,
  sunset: sunset,
);
