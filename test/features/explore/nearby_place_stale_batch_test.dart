import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/entry/context_entry_providers.dart';
import 'package:luma_nest/src/core/entry/context_entry_store.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/application/explore_intent_controller.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place_repository.dart';

/// The canonical entry store outlives any single nearby-places run: moving the
/// map invalidates the provider while its batch is still in flight, and a
/// cancelled run that published anyway could delete entries the newer batch
/// just wrote. This test pins the observable outcome - exactly one batch, the
/// fresh run's, reaches the store. The defense is layered (the isCancelled
/// gate plus Riverpod refusing ref usage on a disposed element); validated by
/// neutering the gate alone, this still passes, so the assertion deliberately
/// trips on any refactor that lets a stale batch through either layer.
void main() {
  test('a cancelled nearby batch never reaches the entry store', () async {
    final clock = DateTime.utc(2026, 11, 1, 8);
    final store = _RecordingStore(clock);
    final repository = _GatedRepository();
    final container = ProviderContainer(
      overrides: [
        environmentSnapshotProvider.overrideWith(
          _FixedEnvironmentController.new,
        ),
        nearbySearchAreaProvider.overrideWith(_FixedAreaController.new),
        exploreIntentProvider.overrideWith(_FixedIntentController.new),
        nearbyPlaceRepositoryProvider.overrideWithValue(repository),
        currentTimeProvider.overrideWithValue(() => clock),
        contextEntryStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    // Keep the provider alive across the invalidation, like an open Explore
    // page does.
    final subscription = container.listen(nearbyPlacesProvider, (_, _) {});
    addTearDown(subscription.close);
    await _settle();

    // The map moves while the first batch is still in flight.
    container.invalidate(nearbyPlacesProvider);
    await _settle();
    expect(repository.pending, 2);

    // The stale batch answers before the fresh one.
    repository.completeAt(0, [
      _place('stale-place'),
      _place('stale-place-2'),
    ]);
    await _settle();
    repository.completeAt(0, [_place('fresh-place')]);
    await _settle();

    // Exactly one batch - the fresh run's - may reach the shared store.
    expect(store.batches, hasLength(1));
    expect(store.batches.single.entries, hasLength(1));
  });
}

Future<void> _settle() async {
  for (var round = 0; round < 8; round += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

NearbyPlace _place(String id) => NearbyPlace(
  id: id,
  name: id,
  category: NearbyPlaceCategory.food,
  point: const GeoPoint(latitude: 30.25, longitude: 120.15),
  distanceMeters: 800,
);

class _RecordingStore implements ContextEntryStore {
  _RecordingStore(DateTime now)
    : _delegate = InMemoryContextEntryStore(now: () => now);

  final InMemoryContextEntryStore _delegate;
  final List<EntryBatch> batches = [];

  @override
  EntryDelta apply(EntryBatch batch) {
    batches.add(batch);
    return _delegate.apply(batch);
  }

  @override
  EntryStoreSnapshot get current => _delegate.current;

  @override
  Stream<EntryDelta> watch() => _delegate.watch();

  @override
  ContextEntry? byId(String id) => _delegate.byId(id);

  @override
  List<ContextEntry> query(EntryQuery query) => _delegate.query(query);
}

class _GatedRepository implements NearbyPlaceRepository {
  final List<Completer<List<NearbyPlace>>> _pending = [];

  int get pending => _pending.length;

  @override
  Future<List<NearbyPlace>> fetchNearby({
    required GeoPoint center,
    required NearbyPlaceCategory category,
    int radiusMeters = 5000,
  }) {
    final completer = Completer<List<NearbyPlace>>();
    _pending.add(completer);
    return completer.future;
  }

  void completeAt(int index, List<NearbyPlace> places) {
    _pending.removeAt(index).complete(places);
  }
}

class _FixedAreaController extends NearbySearchAreaController {
  @override
  NearbySearchArea build() => NearbySearchArea(
    activeCenter: const GeoPoint(latitude: 30.25, longitude: 120.15),
  );
}

class _FixedIntentController extends ExploreIntentController {
  @override
  ExploreIntentState build() =>
      const ExploreIntentState(category: NearbyPlaceCategory.food);
}

class _FixedEnvironmentController extends LiveEnvironmentController {
  @override
  Future<ContextSnapshot> build() async => ContextFixtures.lakeSunset();
}
