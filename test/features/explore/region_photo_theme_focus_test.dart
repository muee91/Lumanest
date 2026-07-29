import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';
import 'package:luma_nest/src/features/explore/domain/region_photo_theme_focus.dart';

void main() {
  test('humanity search covers street and cultural-space naming', () {
    expect(NearbyPlaceCategory.humanity.searchKeywords, contains('古镇'));
    expect(NearbyPlaceCategory.humanity.searchKeywords, contains('老街'));
    expect(NearbyPlaceCategory.humanity.searchKeywords, contains('博物馆'));
    expect(NearbyPlaceCategory.humanity.searchKeywords, contains('故居'));
  });

  test('regional street and architecture themes open humanity candidates', () {
    expect(
      focusForRegionPhotoTheme(
        const RegionPhotoTheme(id: 'theme_street', label: '人文街巷'),
      ),
      ExploreFocus.humanity,
    );
    expect(
      focusForRegionPhotoTheme(
        const RegionPhotoTheme(id: 'theme_architecture', label: '传统建筑'),
      ),
      ExploreFocus.humanity,
    );
  });

  test('water themes retain the water candidate layer', () {
    expect(
      focusForRegionPhotoTheme(
        const RegionPhotoTheme(id: 'theme_river', label: '江岸光影'),
      ),
      ExploreFocus.water,
    );
  });
}
