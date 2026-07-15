import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';
import 'package:luma_nest/src/features/location/application/manual_location_providers.dart';
import 'package:luma_nest/src/features/location/application/environment_location_display.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';

void main() {
  test('manual selection bypasses every automatic location source', () async {
    final automatic = _CountingLocationRepository();
    final container = ProviderContainer(
      overrides: [locationRepositoryProvider.overrideWithValue(automatic)],
    );
    addTearDown(container.dispose);

    container
        .read(manualLocationProvider.notifier)
        .select(
          const LocationSearchResult(
            id: 'manual-shanghai',
            name: '上海',
            address: '上海市',
            point: GeoPoint(latitude: 31.2304, longitude: 121.4737),
          ),
        );

    final reading = await container
        .read(effectiveLocationRepositoryProvider)
        .current();

    expect(automatic.calls, 0);
    expect(reading.accuracyMeters, 1000);
    expect(
      container.read(environmentLocationDisplayProvider).description,
      '上海 · 手动地点 · 非实时',
    );
  });

  test('automatic location is not labeled as a reference place', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final display = container.read(environmentLocationDisplayProvider);

    expect(display, const TypeMatcher<EnvironmentLocationDisplay>());
    expect(display.isReference, isFalse);
    expect(display.description, '当前位置');
  });
}

class _CountingLocationRepository implements LocationRepository {
  var calls = 0;

  @override
  Future<LocationReading> current() async {
    calls += 1;
    return LocationReading(
      point: const GeoPoint(latitude: 0, longitude: 0),
      recordedAt: DateTime.utc(2026),
      accuracyMeters: 1,
    );
  }
}
