import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/server_manifest.dart';

enum LayoutMode {
  quiet,
  opportunity,
  operation;

  /// Maps the server's [ServerManifestLayout] to a client [LayoutMode].
  ///
  /// The mapping is exhaustive: `quiet`→[quiet], `opportunity`→[opportunity],
  /// `safety`→[operation]. The client has no dedicated `safety` layout, so the
  /// server's `safety` mode collapses to [operation]. Unknown values never
  /// reach this method — [ServerManifestLayout] is already a validated enum.
  static LayoutMode fromServerLayout(ServerManifestLayout layout) =>
      switch (layout) {
        ServerManifestLayout.quiet => LayoutMode.quiet,
        ServerManifestLayout.opportunity => LayoutMode.opportunity,
        ServerManifestLayout.safety => LayoutMode.operation,
      };
}

enum ManifestAction {
  openExplore,
  openShootingWindow,
  openWeather,
  openSafety,
  openRoute;

  /// Maps a structured [ContextAction] to its UI [ManifestAction].
  static ManifestAction fromContextAction(ContextAction action) =>
      switch (action) {
        ContextAction.openExplore => ManifestAction.openExplore,
        ContextAction.openShootingWindow => ManifestAction.openShootingWindow,
        ContextAction.openWeather => ManifestAction.openWeather,
        ContextAction.openSafety => ManifestAction.openSafety,
        ContextAction.openRoute => ManifestAction.openRoute,
      };
}

class ManifestItem {
  const ManifestItem({
    required this.id,
    required this.title,
    required this.action,
    this.source,
    this.confidence,
    this.expiresAt,
  });

  final String id;
  final String title;
  final ManifestAction action;
  final ContextEventSource? source;
  final double? confidence;
  final DateTime? expiresAt;

  /// Enriches this item with metadata from a structured [ContextEvent].
  ///
  /// When the event carries an [ContextEvent.allowedAction], it overrides the
  /// template action — structured events always author their own action.
  ManifestItem withEvent(ContextEvent? event) {
    if (event == null) return this;
    return ManifestItem(
      id: id,
      title: title,
      action: event.allowedAction != null
          ? ManifestAction.fromContextAction(event.allowedAction!)
          : action,
      source: event.source,
      confidence: event.confidence,
      expiresAt: event.expiresAt,
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
