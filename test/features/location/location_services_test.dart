import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';
import 'package:luma_nest/src/features/location/application/location_services.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';

void main() {
  final now = DateTime.utc(2026, 7, 18, 10);

  test('environment search is biased toward the snapshot coordinate', () async {
    final repository = _RecordingSearchRepository();
    final snapshot = ContextFixtures.lakeSunset(observedAt: now);
    final container = ProviderContainer(
      overrides: [
        locationSearchRepositoryProvider.overrideWithValue(repository),
        environmentSnapshotProvider.overrideWith(
          () => _FixedEnvironmentController(snapshot),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(locationSearchServiceProvider)
        .searchAroundEnvironment('湖岸');

    expect(repository.queries, ['湖岸']);
    expect(repository.centers.single, snapshot.location);
  });

  test('plain search leaves the ranking centre to the repository', () async {
    final repository = _RecordingSearchRepository();
    final container = ProviderContainer(
      overrides: [
        locationSearchRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(locationSearchServiceProvider).search('湖岸');

    expect(repository.centers.single, isNull);
  });

  test('device fix never resolves through a manual location fallback', () async {
    final device = _CountingLocationRepository(
      LocationReading(
        point: const GeoPoint(latitude: 30.25, longitude: 120.15),
        recordedAt: now,
        accuracyMeters: 8,
      ),
    );
    final container = ProviderContainer(
      overrides: [locationRepositoryProvider.overrideWithValue(device)],
    );
    addTearDown(container.dispose);

    final reading = await container
        .read(deviceLocationFixServiceProvider)
        .current();

    expect(reading.accuracyMeters, 8);
    expect(device.calls, 1);
  });
}

class _RecordingSearchRepository implements LocationSearchRepository {
  final queries = <String>[];
  final centers = <GeoPoint?>[];

  @override
  Future<List<LocationSearchResult>> search(
    String keywords, {
    GeoPoint? center,
  }) async {
    queries.add(keywords);
    centers.add(center);
    return const [];
  }
}

class _CountingLocationRepository implements LocationRepository {
  _CountingLocationRepository(this.reading);

  final LocationReading reading;
  int calls = 0;

  @override
  Future<LocationReading> current() async {
    calls += 1;
    return reading;
  }
}

class _FixedEnvironmentController extends LiveEnvironmentController {
  _FixedEnvironmentController(this.snapshot);

  final ContextSnapshot snapshot;

  @override
  Future<ContextSnapshot> build() async => snapshot;
}
