import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative.dart';

/// Adds optional model wording after deterministic facts have been selected.
///
/// The model never receives coordinates, safety events or action definitions.
/// Its output can only replace the summary and labels of creative event IDs
/// that already exist in the manifest. Invalid, stale or failed output falls
/// back to the deterministic template without surfacing an error to the UI.
class ManifestNarrativeCoordinator {
  ManifestNarrativeCoordinator({
    this.model,
    required this.now,
    this.cacheTtl = const Duration(minutes: 15),
  });

  final ManifestNarrativeModel? model;
  final DateTime Function() now;
  final Duration cacheTtl;

  final _cache = <String, ManifestNarrative>{};
  final _inFlight = <String, Future<ManifestNarrative>>{};

  Future<ManifestNarrative> resolve({
    required ContextSnapshot snapshot,
    required UiManifest manifest,
  }) {
    final evaluatedAt = now().toUtc();
    final fallback = _template(snapshot, manifest, evaluatedAt);
    if (snapshot.isStale || model == null || manifest.creativeItems.isEmpty) {
      return Future.value(fallback);
    }

    final key = _cacheKey(snapshot, manifest);
    final cached = _cache[key];
    if (cached != null && !cached.isExpiredAt(evaluatedAt)) {
      return Future.value(cached);
    }
    return _inFlight[key] ??=
        _generate(
          key: key,
          snapshot: snapshot,
          manifest: manifest,
          fallback: fallback,
          evaluatedAt: evaluatedAt,
        ).whenComplete(() {
          _inFlight.remove(key);
        });
  }

  Future<ManifestNarrative> _generate({
    required String key,
    required ContextSnapshot snapshot,
    required UiManifest manifest,
    required ManifestNarrative fallback,
    required DateTime evaluatedAt,
  }) async {
    final creativeIds = manifest.creativeItems.map((item) => item.id).toList();
    try {
      final candidate = await model!.generate(
        ManifestNarrativeRequest(
          scene: snapshot.primaryScene,
          dayPhase: snapshot.dayPhase,
          weather: snapshot.weather,
          activeRoute: snapshot.activeRoute,
          creativeEventIds: creativeIds,
          templateSummary: manifest.summary,
        ),
      );
      if (!_isValid(candidate, creativeIds.toSet())) {
        _cache[key] = fallback;
        return fallback;
      }
      final narrative = ManifestNarrative(
        summary: candidate.summary.trim(),
        noteLabels: {
          for (final entry in candidate.noteLabels.entries)
            entry.key: entry.value.trim(),
        },
        source: ManifestNarrativeSource.model,
        generatedAt: evaluatedAt,
        expiresAt: _earliest(
          snapshot.expiresAt.toUtc(),
          evaluatedAt.add(cacheTtl),
        ),
      );
      _cache[key] = narrative;
      return narrative;
    } catch (_) {
      _cache[key] = fallback;
      return fallback;
    }
  }

  ManifestNarrative _template(
    ContextSnapshot snapshot,
    UiManifest manifest,
    DateTime evaluatedAt,
  ) {
    return ManifestNarrative(
      summary: manifest.summary,
      source: ManifestNarrativeSource.template,
      generatedAt: evaluatedAt,
      expiresAt: _earliest(
        snapshot.expiresAt.toUtc(),
        evaluatedAt.add(cacheTtl),
      ),
    );
  }

  bool _isValid(
    ManifestNarrativeCandidate candidate,
    Set<String> allowedCreativeIds,
  ) {
    final summary = candidate.summary.trim();
    if (!_validText(summary, minRunes: 1, maxRunes: 80)) return false;
    for (final entry in candidate.noteLabels.entries) {
      if (!allowedCreativeIds.contains(entry.key)) return false;
      if (!_validText(entry.value.trim(), minRunes: 2, maxRunes: 8)) {
        return false;
      }
    }
    return true;
  }

  bool _validText(
    String value, {
    required int minRunes,
    required int maxRunes,
  }) {
    final length = value.runes.length;
    return length >= minRunes &&
        length <= maxRunes &&
        !value.contains(RegExp(r'[\r\n]')) &&
        !value.contains(RegExp(r'https?://', caseSensitive: false));
  }

  String _cacheKey(ContextSnapshot snapshot, UiManifest manifest) {
    final ids = manifest.creativeItems.map((item) => item.id).join(',');
    return '${snapshot.id}|$ids';
  }

  DateTime _earliest(DateTime first, DateTime second) {
    return first.isBefore(second) ? first : second;
  }
}
