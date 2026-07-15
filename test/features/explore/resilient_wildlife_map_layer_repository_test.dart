import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/resilient_wildlife_map_layer_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/wildlife_map_layer_cache.dart';

void main() {
  const center = GeoPoint(latitude: 30.25, longitude: 120.15);

  test('writes live results including an empty reviewed layer', () async {
    final live = WildlifeMapLayer(
      generatedAt: DateTime.utc(2026, 7, 16),
      radiusKilometers: 20,
    );
    final cache = _FakeCache();
    final repository = ResilientWildlifeMapLayerRepository(
      primary: _FakeRepository(result: live),
      cache: cache,
      writeGuard: ContextCacheWriteGuard(),
    );

    final result = await repository.fetch(center: center);

    expect(result, same(live));
    expect(cache.written, same(live));
  });

  test(
    'uses cache for network failure but not missing configuration',
    () async {
      final cached = WildlifeMapLayer(
        generatedAt: DateTime.utc(2026, 7, 16),
        radiusKilometers: 20,
        cachedAt: DateTime.utc(2026, 7, 16, 1),
      );
      final cache = _FakeCache()..result = cached;
      final networkRepository = ResilientWildlifeMapLayerRepository(
        primary: _FakeRepository(
          error: const WildlifeMapLayerFailure(
            WildlifeMapLayerFailureKind.network,
          ),
        ),
        cache: cache,
        writeGuard: ContextCacheWriteGuard(),
      );
      expect(await networkRepository.fetch(center: center), same(cached));

      cache
        ..result = null
        ..readError = StateError('corrupt local cache');
      await expectLater(
        networkRepository.fetch(center: center),
        throwsA(
          isA<WildlifeMapLayerFailure>().having(
            (failure) => failure.kind,
            'kind',
            WildlifeMapLayerFailureKind.network,
          ),
        ),
      );
      cache.readError = null;

      final configurationRepository = ResilientWildlifeMapLayerRepository(
        primary: _FakeRepository(
          error: const WildlifeMapLayerFailure(
            WildlifeMapLayerFailureKind.configuration,
          ),
        ),
        cache: cache,
        writeGuard: ContextCacheWriteGuard(),
      );
      await expectLater(
        configurationRepository.fetch(center: center),
        throwsA(
          isA<WildlifeMapLayerFailure>().having(
            (failure) => failure.kind,
            'kind',
            WildlifeMapLayerFailureKind.configuration,
          ),
        ),
      );
    },
  );

  test(
    'privacy invalidation blocks a late network result from writing',
    () async {
      final completer = Completer<WildlifeMapLayer>();
      final primary = _FakeRepository()..pending = completer.future;
      final cache = _FakeCache();
      final guard = ContextCacheWriteGuard();
      final repository = ResilientWildlifeMapLayerRepository(
        primary: primary,
        cache: cache,
        writeGuard: guard,
      );

      final request = repository.fetch(center: center);
      guard.invalidate();
      completer.complete(
        WildlifeMapLayer(
          generatedAt: DateTime.utc(2026, 7, 16),
          radiusKilometers: 20,
        ),
      );
      await request;

      expect(cache.written, isNull);
    },
  );
}

class _FakeRepository implements WildlifeMapLayerRepository {
  _FakeRepository({this.result, this.error});

  WildlifeMapLayer? result;
  Object? error;
  Future<WildlifeMapLayer>? pending;

  @override
  Future<WildlifeMapLayer> fetch({
    required GeoPoint center,
    int radiusKilometers = 20,
  }) async {
    if (pending case final future?) return future;
    if (error case final failure?) throw failure;
    return result!;
  }
}

class _FakeCache implements WildlifeMapLayerCache {
  WildlifeMapLayer? result;
  WildlifeMapLayer? written;
  Object? readError;

  @override
  Future<void> clear() async {}

  @override
  Future<WildlifeMapLayer?> readMatching({
    required GeoPoint center,
    required int radiusKilometers,
  }) async {
    if (readError case final error?) throw error;
    return result;
  }

  @override
  Future<void> write({
    required GeoPoint center,
    required WildlifeMapLayer layer,
  }) async => written = layer;
}
