import 'package:luma_nest/src/core/context/context_event.dart';

enum LayoutMode { quiet, opportunity, operation }

enum ManifestAction { openExplore, openShootingWindow, openWeather, openSafety }

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

  ManifestItem withEvent(ContextEvent? event) => event == null
      ? this
      : ManifestItem(
          id: id,
          title: title,
          action: action,
          source: event.source,
          confidence: event.confidence,
          expiresAt: event.expiresAt,
        );
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
