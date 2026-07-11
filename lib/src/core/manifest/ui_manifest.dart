enum LayoutMode { quiet, opportunity, operation }

enum ManifestAction { openExplore, openShootingWindow, openWeather, openSafety }

class ManifestItem {
  const ManifestItem({
    required this.id,
    required this.title,
    required this.action,
  });

  final String id;
  final String title;
  final ManifestAction action;
}

class UiManifest {
  UiManifest({
    required this.layoutMode,
    required this.summary,
    required this.primary,
    List<ManifestItem> secondary = const [],
    List<ManifestItem> safety = const [],
    required this.inspirationPreview,
  }) : secondary = List.unmodifiable(secondary),
       safety = List.unmodifiable(safety);

  final LayoutMode layoutMode;
  final String summary;
  final ManifestItem? primary;
  final List<ManifestItem> secondary;
  final List<ManifestItem> safety;
  final String inspirationPreview;

  List<ManifestItem> get creativeItems =>
      List.unmodifiable([?primary, ...secondary]);
}
