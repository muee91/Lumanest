import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/explore/application/explore_intent_catalog.dart';
import 'package:luma_nest/src/features/explore/application/explore_intent_controller.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';

void main() {
  test('explore keeps creative controls separate from nearby services', () {
    expect(
      exploreCoreIntents,
      const [
        ExploreCreativeIntent.viewpoint,
        ExploreCreativeIntent.humanity,
      ],
    );
    expect(
      exploreNearbyServiceIntents,
      const [
        ExploreCreativeIntent.supplies,
        ExploreCreativeIntent.parking,
        ExploreCreativeIntent.food,
        ExploreCreativeIntent.fuel,
        ExploreCreativeIntent.medical,
      ],
    );
    expect(isExploreNearbyServiceIntent(ExploreCreativeIntent.food), isTrue);
    expect(
      isExploreNearbyServiceIntent(ExploreCreativeIntent.humanity),
      isFalse,
    );
  });

  test('regional themes are deduplicated and capped', () {
    final selected = selectExploreRegionThemes(const [
      RegionPhotoTheme(id: 'tidal', label: '潮汐海塘'),
      RegionPhotoTheme(id: 'tidal-copy', label: '潮汐海塘'),
      RegionPhotoTheme(id: 'lantern', label: '硖石灯彩'),
      RegionPhotoTheme(id: 'celebrity', label: '名人故里'),
    ]);

    expect(selected.map((item) => item.id), ['tidal', 'lantern']);
  });

  test('regional theme keeps its label in intent state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const theme = RegionPhotoTheme(id: 'tidal', label: '潮汐海塘');

    container
        .read(exploreIntentProvider.notifier)
        .chooseRegionTheme(theme);

    final state = container.read(exploreIntentProvider);
    expect(state.regionTheme?.id, 'tidal');
    expect(state.regionTheme?.label, '潮汐海塘');
    expect(state.category, NearbyPlaceCategory.waterfront);

    container
        .read(exploreIntentProvider.notifier)
        .chooseCreativeIntent(ExploreCreativeIntent.parking);
    final serviceState = container.read(exploreIntentProvider);
    expect(serviceState.regionTheme, isNull);
    expect(serviceState.creativeIntent, ExploreCreativeIntent.parking);
  });
}
