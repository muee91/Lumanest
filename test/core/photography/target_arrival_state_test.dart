import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/core/photography/target_arrival_state.dart';

void main() {
  final now = DateTime.utc(2026, 9, 27, 4);

  test('arrival requires the location uncertainty to fit inside target radius', () {
    final target = _target(arrivalRadiusMeters: 100);

    final arrived = TargetArrivalStateResolver.assess(
      reading: LocationReading(
        point: const GeoPoint(latitude: 30, longitude: 120),
        recordedAt: now,
        accuracyMeters: 12,
      ),
      target: target,
      now: now,
    );
    expect(arrived?.state, TargetArrivalState.arrived);

    final uncertain = TargetArrivalStateResolver.assess(
      reading: LocationReading(
        point: const GeoPoint(latitude: 30.00072, longitude: 120),
        recordedAt: now,
        accuracyMeters: 30,
      ),
      target: target,
      now: now,
    );
    expect(uncertain?.state, isNot(TargetArrivalState.arrived));
  });

  test('stale or low-accuracy readings cannot assert automatic arrival', () {
    final target = _target(arrivalRadiusMeters: 100);

    expect(
      TargetArrivalStateResolver.assess(
        reading: LocationReading(
          point: const GeoPoint(latitude: 30, longitude: 120),
          recordedAt: now.subtract(const Duration(minutes: 3)),
          accuracyMeters: 10,
        ),
        target: target,
        now: now,
      ),
      isNull,
    );
    expect(
      TargetArrivalStateResolver.assess(
        reading: LocationReading(
          point: const GeoPoint(latitude: 30, longitude: 120),
          recordedAt: now,
          accuracyMeters: 120,
        ),
        target: target,
        now: now,
      ),
      isNull,
    );
  });

  test('GCJ-02 reviewed targets are normalized before distance assessment', () {
    final target = _target(
      coordinate: ChinaCoordinateConverter.wgs84ToGcj02(
        const GeoPoint(latitude: 30, longitude: 120),
      ),
      arrivalRadiusMeters: 100,
    );

    final result = TargetArrivalStateResolver.assess(
      reading: LocationReading(
        point: const GeoPoint(latitude: 30, longitude: 120),
        recordedAt: now,
        accuracyMeters: 10,
      ),
      target: target,
      now: now,
    );

    expect(result?.state, TargetArrivalState.arrived);
  });
}

ShootingTarget _target({
  GeoPoint coordinate = const GeoPoint(latitude: 30, longitude: 120),
  int arrivalRadiusMeters = 100,
}) => ShootingTarget(
  id: 'target_0123456789abcdef01234567',
  name: '审核机位',
  coordinate: coordinate,
  supportedSessions: const [ShootingSessionKind.waterEvening],
  viewBearingDegrees: 258,
  bearingToleranceDegrees: 20,
  accessModes: const [ShootingTravelMode.driving],
  leadTimeMinutes: 10,
  arrivalRadiusMeters: arrivalRadiusMeters,
  shorelineSide: ShootingShorelineSide.east,
  reviewedAt: DateTime.utc(2026, 9, 1),
  reviewReference: Uri.parse('https://review.example/target'),
  sourceAttribution: '审核目录',
  sourceLicense: 'CC-BY-4.0',
  sourceUrl: Uri.parse('https://source.example/target'),
);
