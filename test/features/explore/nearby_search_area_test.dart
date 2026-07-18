import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';

void main() {
  test('map movement remains pending until the user searches that area', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(nearbySearchAreaProvider.notifier);
    const base = GeoPoint(latitude: 30.25, longitude: 120.15);
    const moved = GeoPoint(latitude: 30.5, longitude: 120.5);

    controller.syncBase(base);
    controller.markMapMoved(moved);

    expect(container.read(nearbySearchAreaProvider).activeCenter, isNull);
    expect(container.read(nearbySearchAreaProvider).pendingCenter, moved);

    controller.searchPendingArea();
    expect(container.read(nearbySearchAreaProvider).activeCenter, moved);
    expect(container.read(nearbySearchAreaProvider).pendingCenter, isNull);

    controller.expand();
    expect(container.read(nearbySearchAreaProvider).radiusMeters, 15000);
    controller.expand();
    expect(container.read(nearbySearchAreaProvider).radiusMeters, 30000);
  });
}
