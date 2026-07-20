import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/monitoring/app_logger.dart';
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
    this.failureBackoff = const Duration(minutes: 1),
    this.maximumCacheEntries = 64,
    this.logger,
  });

  final ManifestNarrativeModel? model;
  final DateTime Function() now;
  final Duration cacheTtl;
  final Duration failureBackoff;
  final int maximumCacheEntries;
  final AppLogger? logger;

  final _cache = <String, ManifestNarrative>{};
  final _failureUntil = <String, DateTime>{};
  final _inFlight = <String, Future<ManifestNarrative>>{};

  Future<ManifestNarrative> resolve({
    required ContextSnapshot snapshot,
    required UiManifest manifest,
    NarrativeTone tone = NarrativeTone.balanced,
    String preferenceFingerprint = 'neutral',
  }) {
    final evaluatedAt = now().toUtc();
    final fallback = _template(snapshot, manifest, evaluatedAt);
    if (snapshot.isStale) {
      _logTemplateFallback('staleSnapshot', tone, manifest);
      return Future.value(fallback);
    }
    if (model == null) {
      _logTemplateFallback('modelUnavailable', tone, manifest);
      return Future.value(fallback);
    }
    if (manifest.creativeItems.isEmpty) {
      _logTemplateFallback('noCreativeEvents', tone, manifest);
      return Future.value(fallback);
    }

    _prune(evaluatedAt);
    final key = _cacheKey(snapshot, manifest, preferenceFingerprint, tone);
    final cached = _cache[key];
    if (cached != null && !cached.isExpiredAt(evaluatedAt)) {
      logger?.debug(
        LogCategory.aiCall,
        'narrative.cache_hit',
        data: {
          LogDataKey.cache: 'hit',
          LogDataKey.tone: tone.name,
          LogDataKey.eventCount: manifest.creativeItems.length,
        },
      );
      return Future.value(cached);
    }
    final blockedUntil = _failureUntil[key];
    if (blockedUntil != null && blockedUntil.isAfter(evaluatedAt)) {
      _logTemplateFallback('requestFailure', tone, manifest);
      return Future.value(fallback);
    }
    final inFlight = _inFlight[key];
    if (inFlight != null) {
      logger?.debug(
        LogCategory.aiCall,
        'narrative.request_deduplicated',
        data: {LogDataKey.cache: 'inFlight', LogDataKey.tone: tone.name},
      );
      return inFlight;
    }
    final request = _generate(
      key: key,
      snapshot: snapshot,
      manifest: manifest,
      fallback: fallback,
      evaluatedAt: evaluatedAt,
      tone: tone,
    ).whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = request;
    return request;
  }

  Future<ManifestNarrative> _generate({
    required String key,
    required ContextSnapshot snapshot,
    required UiManifest manifest,
    required ManifestNarrative fallback,
    required DateTime evaluatedAt,
    required NarrativeTone tone,
  }) async {
    final creativeIds = manifest.creativeItems.map((item) => item.id).toList();
    logger?.info(
      LogCategory.aiCall,
      'narrative.request_started',
      data: {
        LogDataKey.tone: tone.name,
        LogDataKey.eventCount: creativeIds.length,
      },
    );
    try {
      final candidate = await model!.generate(
        ManifestNarrativeRequest(
          scene: snapshot.primaryScene,
          dayPhase: snapshot.dayPhase,
          weather: snapshot.weather,
          activeRoute: snapshot.activeRoute,
          creativeEventIds: creativeIds,
          templateSummary: manifest.summary,
          tone: tone,
        ),
      );
      if (!_isValid(candidate, creativeIds.toSet())) {
        _recordFailure(key, evaluatedAt);
        logger?.warning(
          LogCategory.aiCall,
          'narrative.invalid_output',
          data: const {LogDataKey.reason: 'schemaValidation'},
        );
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
      _failureUntil.remove(key);
      _putCache(key, narrative, evaluatedAt);
      logger?.info(
        LogCategory.aiCall,
        'narrative.model_used',
        data: {LogDataKey.source: 'model', LogDataKey.tone: tone.name},
      );
      return narrative;
    } catch (_) {
      _recordFailure(key, evaluatedAt);
      logger?.warning(
        LogCategory.aiCall,
        'narrative.request_failed',
        data: const {LogDataKey.reason: 'requestFailure'},
      );
      return fallback;
    }
  }

  void _recordFailure(String key, DateTime evaluatedAt) {
    _failureUntil[key] = evaluatedAt.add(failureBackoff);
  }

  void _putCache(
    String key,
    ManifestNarrative narrative,
    DateTime evaluatedAt,
  ) {
    _cache.remove(key);
    _cache[key] = narrative;
    _prune(evaluatedAt);
    while (_cache.length > maximumCacheEntries && _cache.isNotEmpty) {
      _cache.remove(_cache.keys.first);
    }
  }

  void _prune(DateTime evaluatedAt) {
    _cache.removeWhere((_, value) => value.isExpiredAt(evaluatedAt));
    _failureUntil.removeWhere((_, value) => !value.isAfter(evaluatedAt));
  }

  void _logTemplateFallback(
    String reason,
    NarrativeTone tone,
    UiManifest manifest,
  ) {
    logger?.debug(
      LogCategory.aiCall,
      'narrative.template_used',
      data: {
        LogDataKey.source: 'template',
        LogDataKey.reason: reason,
        LogDataKey.tone: tone.name,
        LogDataKey.eventCount: manifest.creativeItems.length,
      },
    );
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

  String _cacheKey(
    ContextSnapshot snapshot,
    UiManifest manifest,
    String preferenceFingerprint,
    NarrativeTone tone,
  ) {
    final ids = manifest.creativeItems.map((item) => item.id).join(',');
    final observedAt = snapshot.observedAt.toUtc().microsecondsSinceEpoch;
    final summary = manifest.summary.trim();
    return '${snapshot.id}|$observedAt|$ids|$summary|$preferenceFingerprint|${tone.name}';
  }

  DateTime _earliest(DateTime first, DateTime second) {
    return first.isBefore(second) ? first : second;
  }
}
