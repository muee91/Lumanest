import 'dart:collection';

import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';

enum ManifestNarrativeSource { template, model }

class ManifestNarrative {
  ManifestNarrative({
    required this.summary,
    Map<String, String> noteLabels = const {},
    required this.source,
    required this.generatedAt,
    required this.expiresAt,
  }) : noteLabels = UnmodifiableMapView(Map.of(noteLabels));

  final String summary;
  final Map<String, String> noteLabels;
  final ManifestNarrativeSource source;
  final DateTime generatedAt;
  final DateTime expiresAt;

  bool isExpiredAt(DateTime moment) => !moment.toUtc().isBefore(expiresAt);
}

class ManifestNarrativeCandidate {
  const ManifestNarrativeCandidate({
    required this.summary,
    this.noteLabels = const {},
  });

  final String summary;
  final Map<String, String> noteLabels;
}

class ManifestNarrativeRequest {
  ManifestNarrativeRequest({
    required this.scene,
    required this.dayPhase,
    required this.weather,
    required this.activeRoute,
    required List<String> creativeEventIds,
    required this.templateSummary,
    this.tone = NarrativeTone.balanced,
  }) : creativeEventIds = List.unmodifiable(creativeEventIds);

  final SceneType scene;
  final DayPhase dayPhase;
  final WeatherType weather;
  final bool activeRoute;
  final List<String> creativeEventIds;
  final String templateSummary;
  final NarrativeTone tone;

  @override
  String toString() =>
      'ManifestNarrativeRequest('
      'scene: ${scene.name}, '
      'dayPhase: ${dayPhase.name}, '
      'weather: ${weather.name}, '
      'activeRoute: $activeRoute, '
      'creativeEventIds: $creativeEventIds)';
}

abstract interface class ManifestNarrativeModel {
  Future<ManifestNarrativeCandidate> generate(ManifestNarrativeRequest request);
}
