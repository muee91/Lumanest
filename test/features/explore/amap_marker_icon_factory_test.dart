import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/presentation/amap_marker_icon_factory.dart';

void main() {
  testWidgets('builds category-specific PNG marker icons and selected states', (
    tester,
  ) async {
    final icons = await tester.runAsync(AmapMarkerIconFactory.build);
    expect(icons, isNotNull);
    final builtIcons = icons!;

    expect(builtIcons.regular.keys, containsAll(NearbyPlaceCategory.values));
    expect(builtIcons.selected.keys, containsAll(NearbyPlaceCategory.values));
    expect(
      builtIcons.regular.values.every(
        (icon) => icon.toMap().first == 'fromBytes',
      ),
      isTrue,
    );
    expect(builtIcons.search.toMap().first, 'fromBytes');
    expect(
      AmapMarkerIconFactory.iconFor(NearbyPlaceCategory.sunriseCandidate),
      isNot(AmapMarkerIconFactory.iconFor(NearbyPlaceCategory.humanity)),
    );
    expect(
      AmapMarkerIconFactory.colorFor(NearbyPlaceCategory.waterfront),
      isNot(AmapMarkerIconFactory.colorFor(NearbyPlaceCategory.medical)),
    );
  });
}
