import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/trip/trip_task.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/presentation_v2/route/v2_route_page.dart';

void main() {
  const taskPoint = GeoPoint(
    latitude: 31.25,
    longitude: 121.15,
    coordinateSystem: CoordinateSystem.wgs84,
  );

  test('active trip task takes precedence over recent route history', () {
    final task = TripTask(
      id: 'trip_active',
      destinationName: '当前任务目的地',
      destination: taskPoint,
      travelMode: TripTravelMode.driving,
      stage: TripTaskStage.planning,
      createdAt: DateTime.utc(2026, 11, 3),
    );
    final destination = resolveV2RouteDestination(
      destinationName: null,
      destinationLatitude: null,
      destinationLongitude: null,
      destinationCoordinateSystem: CoordinateSystem.wgs84,
      travelMode: RouteTravelMode.driving,
      recentRoute: const SavedRouteDestination(
        name: '历史路线',
        latitude: 30.25,
        longitude: 120.15,
      ),
      activeTask: task,
    );

    expect(destination?.name, '当前任务目的地');
    expect(destination?.point.latitude, taskPoint.latitude);
    expect(destination?.point.longitude, taskPoint.longitude);
  });

  test(
    'explicit route request still takes precedence over the active task',
    () {
      final task = TripTask(
        id: 'trip_active',
        destinationName: '当前任务目的地',
        destination: taskPoint,
        travelMode: TripTravelMode.driving,
        stage: TripTaskStage.planning,
        createdAt: DateTime.utc(2026, 11, 3),
      );
      final destination = resolveV2RouteDestination(
        destinationName: '深链目的地',
        destinationLatitude: 30.25,
        destinationLongitude: 120.15,
        destinationCoordinateSystem: CoordinateSystem.wgs84,
        travelMode: RouteTravelMode.walking,
        recentRoute: null,
        activeTask: task,
      );

      expect(destination?.name, '深链目的地');
      expect(destination?.point.latitude, 30.25);
      expect(destination?.travelMode, RouteTravelMode.walking);
    },
  );
}
