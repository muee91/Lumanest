import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/photography/opportunity_catalog.dart';

enum ManifestPanel { creative, safety }

class ManifestActionResolution {
  const ManifestActionResolution.route(this.route)
    : panel = null,
      externalUri = null;
  const ManifestActionResolution.panel(this.panel)
    : route = null,
      externalUri = null;
  const ManifestActionResolution.external(this.externalUri)
    : route = null,
      panel = null;
  const ManifestActionResolution.none()
    : route = null,
      panel = null,
      externalUri = null;

  final String? route;
  final ManifestPanel? panel;
  final Uri? externalUri;
}

abstract final class ManifestActionResolver {
  static ManifestActionResolution resolve(ManifestItem item) {
    return switch (item.action) {
      ManifestAction.openExplore => ManifestActionResolution.route(
        '/explore?focus=${_exploreFocus(item.id)}',
      ),
      ManifestAction.openShootingWindow => ManifestActionResolution.route(
        '/session/${Uri.encodeComponent(item.id)}',
      ),
      ManifestAction.openRoute => const ManifestActionResolution.route(
        '/route',
      ),
      ManifestAction.openPlaceDetail => ManifestActionResolution.route(
        '/place/${Uri.encodeComponent(item.id)}',
      ),
      ManifestAction.openAstronomyDetail =>
        item.authorityUri == null
            ? const ManifestActionResolution.none()
            : ManifestActionResolution.external(item.authorityUri),
      ManifestAction.openWildlifeDetail => const ManifestActionResolution.route(
        '/explore?focus=wildlife',
      ),
      ManifestAction.openSafetyDetail => const ManifestActionResolution.panel(
        ManifestPanel.safety,
      ),
      ManifestAction.openCreativeDetail => const ManifestActionResolution.panel(
        ManifestPanel.creative,
      ),
      ManifestAction.dismiss => const ManifestActionResolution.none(),
    };
  }

  static String _exploreFocus(String eventId) {
    if (eventId == 'regional-wildlife') return 'wildlife';
    return switch (OpportunityCatalog.current.byId[eventId]?.family) {
      OpportunityFamily.water => 'water',
      OpportunityFamily.ecology => 'wildlife',
      OpportunityFamily.humanityRoute => 'humanity',
      _ => 'photography',
    };
  }
}
