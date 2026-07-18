import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
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

  test('sunrise entry activates the dedicated multi-candidate layer', () {
    controller().activate(ExploreFocus.sunrise);

    expect(state().activeFocus, ExploreFocus.sunrise);
    expect(state().category, NearbyPlaceCategory.sunriseCandidate);
    expect(NearbyPlaceCategory.sunriseCandidate.searchKeywords, hasLength(9));
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

  test('scene defaults select lake and humanity layers deterministically', () {
    controller().syncScene(SceneType.lake);
    expect(state().category, NearbyPlaceCategory.waterfront);

    controller().syncScene(SceneType.village);
    expect(state().category, NearbyPlaceCategory.humanity);

    for (final scene in [
      SceneType.unknown,
      SceneType.city,
      SceneType.mountain,
      SceneType.desert,
      SceneType.unknown,
      SceneType.mountain,
    ]) {
      controller().syncScene(scene);
      expect(state().category, NearbyPlaceCategory.viewpoint);
    }
  });

  test('manual category is not overwritten by later scene updates', () {
    controller().complete(category: NearbyPlaceCategory.food);
    controller().syncScene(SceneType.lake);

    expect(state().category, NearbyPlaceCategory.food);
    expect(state().sceneCategory, NearbyPlaceCategory.waterfront);
  });

  test('temporary intent expires back to the latest scene layer', () {
    controller().syncScene(SceneType.lake);
    controller().activate(ExploreFocus.water);
    controller().syncScene(SceneType.village);

    expect(controller().expire(), isTrue);
    expect(state().category, NearbyPlaceCategory.humanity);
    expect(state().activeFocus, isNull);
  });

  test('creative intent resolves to its existing nearby category', () {
    controller().chooseCreativeIntent(ExploreCreativeIntent.water);

    expect(state().creativeIntent, ExploreCreativeIntent.water);
    expect(state().category, NearbyPlaceCategory.waterfront);

    controller().chooseCreativeIntent(ExploreCreativeIntent.supplies);
    expect(state().category, NearbyPlaceCategory.supply);
  });
}
