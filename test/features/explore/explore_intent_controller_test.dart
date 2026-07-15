import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/explore/application/explore_intent_controller.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  ExploreIntentState state() => container.read(exploreIntentProvider);
  ExploreIntentController controller() =>
      container.read(exploreIntentProvider.notifier);

  test('entry focus selects its category and remains explicitly temporary', () {
    controller().activate(ExploreFocus.water);

    expect(state().activeFocus, ExploreFocus.water);
    expect(state().category, NearbyPlaceCategory.waterfront);
    expect(
      container.read(nearbyCategoryProvider),
      NearbyPlaceCategory.waterfront,
    );
  });

  test('manual completion keeps the chosen category and clears intent', () {
    controller().activate(ExploreFocus.humanity);
    controller().complete(category: NearbyPlaceCategory.food);

    expect(state().activeFocus, isNull);
    expect(state().category, NearbyPlaceCategory.food);

    controller().activate(ExploreFocus.photography);
    expect(state().category, NearbyPlaceCategory.food);
  });

  test(
    'timeout restores the photography layer only when an intent is active',
    () {
      expect(controller().expire(), isFalse);

      controller().activate(ExploreFocus.wildlife);
      expect(controller().expire(), isTrue);
      expect(state().activeFocus, isNull);
      expect(state().category, NearbyPlaceCategory.viewpoint);
    },
  );
}
