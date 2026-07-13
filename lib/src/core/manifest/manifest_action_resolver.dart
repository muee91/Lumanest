import 'package:luma_nest/src/core/manifest/ui_manifest.dart';

enum ManifestPanel { weather, safety }

class ManifestActionResolution {
  const ManifestActionResolution.route(this.route) : panel = null;
  const ManifestActionResolution.panel(this.panel) : route = null;

  final String? route;
  final ManifestPanel? panel;
}

abstract final class ManifestActionResolver {
  static ManifestActionResolution resolve(ManifestItem item) {
    return switch (item.action) {
      ManifestAction.openExplore => ManifestActionResolution.route(
        '/explore?focus=${_exploreFocus(item.id)}',
      ),
      ManifestAction.openShootingWindow => const ManifestActionResolution.route(
        '/shooting-window',
      ),
      ManifestAction.openWeather => const ManifestActionResolution.panel(
        ManifestPanel.weather,
      ),
      ManifestAction.openSafety => const ManifestActionResolution.panel(
        ManifestPanel.safety,
      ),
    };
  }

  static String _exploreFocus(String eventId) => switch (eventId) {
    'reflection' => 'water',
    'humanity-light' => 'humanity',
    'regional-wildlife' => 'wildlife',
    _ => 'photography',
  };
}
