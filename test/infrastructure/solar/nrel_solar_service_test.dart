import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/infrastructure/solar/nrel_solar_service.dart';

void main() {
  const shanghai = GeoPoint(latitude: 31.2304, longitude: 121.4737);
  const utc8 = Duration(hours: 8);
  final service = NrelSolarService();

  test('calculates ordered sunrise and sunset without network access', () {
    final result = service.calculate(
      point: shanghai,
      moment: DateTime.utc(2026, 7, 11, 4),
      utcOffset: utc8,
    );

    expect(result.sunrise, isNotNull);
    expect(result.sunset, isNotNull);
    expect(result.sunrise!.isBefore(result.sunset!), isTrue);
  });

  test('returns solar angles within physical display ranges', () {
    final result = service.calculate(
      point: shanghai,
      moment: DateTime.utc(2026, 7, 11, 4),
      utcOffset: utc8,
    );

    expect(result.azimuthDegrees, inInclusiveRange(0, 360));
    expect(result.elevationDegrees, inInclusiveRange(-90, 90));
  });

  test('derives day, dawn and night phases from calculated events', () {
    final noon = service.calculate(
      point: shanghai,
      moment: DateTime.utc(2026, 7, 11, 4),
      utcOffset: utc8,
    );
    final dawn = service.calculate(
      point: shanghai,
      moment: noon.sunrise!.subtract(const Duration(minutes: 10)),
      utcOffset: utc8,
    );
    final night = service.calculate(
      point: shanghai,
      moment: noon.sunset!.add(const Duration(hours: 2)),
      utcOffset: utc8,
    );

    expect(noon.dayPhase, DayPhase.day);
    expect(dawn.dayPhase, DayPhase.dawn);
    expect(night.dayPhase, DayPhase.night);
  });

  test('supports western China coordinates with an explicit offset', () {
    final result = service.calculate(
      point: const GeoPoint(latitude: 38.925, longitude: 100.449),
      moment: DateTime.utc(2026, 7, 11, 4),
      utcOffset: utc8,
      altitudeMeters: 1500,
    );

    expect(result.sunrise, isNotNull);
    expect(result.sunset, isNotNull);
    expect(result.sunrise!.isBefore(result.sunset!), isTrue);
  });
}
