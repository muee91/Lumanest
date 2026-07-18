import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/manifest/manifest_action_resolver.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';

void main() {
  test('creative explore actions resolve only to whitelisted focus routes', () {
    expect(
      ManifestActionResolver.resolve(
        const ManifestItem(
          id: 'session.water.evening',
          title: '倒影',
          action: ManifestAction.openExplore,
        ),
      ).route,
      '/explore?focus=water',
    );
    expect(
      ManifestActionResolver.resolve(
        const ManifestItem(
          id: 'session.route.light_window',
          title: '人文',
          action: ManifestAction.openExplore,
        ),
      ).route,
      '/explore?focus=humanity',
    );
    expect(
      ManifestActionResolver.resolve(
        const ManifestItem(
          id: 'regional-wildlife',
          title: '动物',
          action: ManifestAction.openExplore,
        ),
      ).route,
      '/explore?focus=wildlife',
    );
  });

  test('shooting routes to timeline while weather and safety use panels', () {
    expect(
      ManifestActionResolver.resolve(
        const ManifestItem(
          id: 'session.city.blue_hour',
          title: '蓝调',
          action: ManifestAction.openShootingWindow,
        ),
      ).route,
      '/session/session.city.blue_hour',
    );
    expect(
      ManifestActionResolver.resolve(
        const ManifestItem(
          id: 'event.atmosphere.morning_mist',
          title: '雾',
          action: ManifestAction.openCreativeDetail,
        ),
      ).panel,
      ManifestPanel.creative,
    );
    expect(
      ManifestActionResolver.resolve(
        const ManifestItem(
          id: 'thunderstorm',
          title: '雷暴',
          action: ManifestAction.openSafetyDetail,
        ),
      ).panel,
      ManifestPanel.safety,
    );
  });

  test('authority action resolves only the validated event URL', () {
    final uri = Uri.parse('https://science.nasa.gov/meteor-showers/');
    expect(
      ManifestActionResolver.resolve(
        ManifestItem(
          id: 'astronomy-event',
          title: '流星雨',
          action: ManifestAction.openAstronomyDetail,
          authorityUri: uri,
        ),
      ).externalUri,
      uri,
    );
    expect(
      ManifestActionResolver.resolve(
        const ManifestItem(
          id: 'missing-authority',
          title: '缺少来源',
          action: ManifestAction.openAstronomyDetail,
        ),
      ).externalUri,
      isNull,
    );
  });
}
