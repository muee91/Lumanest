import 'package:luma_nest/src/core/context/context_event.dart';

enum LayoutMode {
  quiet,
  opportunity,
  operation;
}

enum ManifestAction {
  openShootingWindow,
  openExplore,
  openRoute,
  openPlaceDetail,
  openAstronomyDetail,
  openWildlifeDetail,
  openSafetyDetail,
  openCreativeDetail,
  dismiss;

  /// Maps a structured [ContextAction] to its UI [ManifestAction].
  static ManifestAction fromContextAction(ContextAction action) =>
      switch (action) {
        ContextAction.openShootingWindow => ManifestAction.openShootingWindow,
        ContextAction.openExplore => ManifestAction.openExplore,
        ContextAction.openRoute => ManifestAction.openRoute,
        ContextAction.openPlaceDetail => ManifestAction.openPlaceDetail,
        ContextAction.openAstronomyDetail => ManifestAction.openAstronomyDetail,
        ContextAction.openWildlifeDetail => ManifestAction.openWildlifeDetail,
        ContextAction.openSafetyDetail => ManifestAction.openSafetyDetail,
        ContextAction.openCreativeDetail => ManifestAction.openCreativeDetail,
        ContextAction.dismiss => ManifestAction.dismiss,
      };
}

class ManifestItem {
  const ManifestItem({
    required this.id,
    required this.title,
    required this.action,
    this.source,
    this.observedAt,
    this.confidence,
    this.expiresAt,
    this.geoScope,
    this.safetyLevel,
    this.authorityUri,
  });

  final String id;
  final String title;
  final ManifestAction action;
  final ContextEventSource? source;
  final DateTime? observedAt;
  final double? confidence;
  final DateTime? expiresAt;
  final ContextGeoScope? geoScope;
  final ContextSafetyLevel? safetyLevel;
  final Uri? authorityUri;

  /// Enriches this item with metadata from a structured [ContextEvent].
  ///
  /// When the event carries an [ContextEvent.allowedAction], it overrides the
  /// template action — structured events always author their own action.
  ManifestItem withEvent(ContextEvent? event) {
    if (event == null) return this;
    return ManifestItem(
      id: id,
      title: event.title ?? title,
      action: event.allowedAction != null
          ? ManifestAction.fromContextAction(event.allowedAction!)
          : action,
      source: event.source,
      observedAt: event.observedAt,
      confidence: event.confidence,
      expiresAt: event.expiresAt,
      geoScope: event.geoScope,
      safetyLevel: event.safetyLevel,
      authorityUri: event.sourceUri,
    );
  }
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
