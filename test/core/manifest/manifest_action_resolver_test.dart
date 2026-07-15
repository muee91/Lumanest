import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/manifest/manifest_action_resolver.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';

void main() {
  test('creative explore actions resolve only to whitelisted focus routes', () {
    expect(
      ManifestActionResolver.resolve(
        const ManifestItem(
          id: 'reflection',
          title: '倒影',
          action: ManifestAction.openExplore,
        ),
      ).route,
      '/explore?focus=water',
    );
    expect(
      ManifestActionResolver.resolve(
        const ManifestItem(
          id: 'humanity-light',
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
          id: 'blue-hour',
          title: '蓝调',
          action: ManifestAction.openShootingWindow,
        ),
      ).route,
      '/shooting-window',
    );
    expect(
      ManifestActionResolver.resolve(
        const ManifestItem(
          id: 'mist',
          title: '雾',
          action: ManifestAction.openWeather,
        ),
      ).panel,
      ManifestPanel.weather,
    );
    expect(
      ManifestActionResolver.resolve(
        const ManifestItem(
          id: 'thunderstorm',
          title: '雷暴',
          action: ManifestAction.openSafety,
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
          action: ManifestAction.openAuthority,
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
          action: ManifestAction.openAuthority,
        ),
      ).externalUri,
      isNull,
    );
  });
}
