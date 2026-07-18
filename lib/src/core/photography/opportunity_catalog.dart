import 'dart:convert';

import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/generated/opportunity_catalog.g.dart';

enum CatalogTier { core, legacyOnly, reserved }

enum CoreCapabilityState { available, degraded, unavailable }

enum OpportunityModelType { shootingSession, factualEvent }

enum OpportunityFamily {
  water,
  mountain,
  city,
  landform,
  atmosphere,
  astronomy,
  ecology,
  humanityRoute,
}

enum EvidenceKind {
  light,
  weather,
  precipitation,
  wind,
  visibility,
  astronomy,
  authority,
  place,
  route,
  equipment,
  cloudLayers,
  directionalRain,
  humidityDewPoint,
  moonTrajectory,
  terrain,
  lineOfSight,
  legalStop,
  tide,
  lightPollution,
  snowCover,
  ecology,
}

enum PhotographyPreferenceId {
  mountainLandform,
  waterCoast,
  cityArchitecture,
  humanityStreet,
  astroCelestial,
  wildlifeEcology,
  forestDetail,
  aerialSpatial,
}

class OpportunityPresentation {
  const OpportunityPresentation({
    required this.name,
    required this.shortLabel,
    required this.emoji,
    this.degradedName,
    this.fallbackSummary,
  });

  final String name;
  final String shortLabel;
  final String emoji;
  final String? degradedName;
  final String? fallbackSummary;
}

class OpportunityDefinition {
  OpportunityDefinition({
    required this.id,
    required this.catalogTier,
    required this.coreCapability,
    required this.modelType,
    required this.family,
    required this.presentation,
    required Iterable<PrimaryScene> primaryScenes,
    required Iterable<SceneFacet> sceneFacets,
    required Iterable<EvidenceKind> requiredEvidence,
    required Iterable<EvidenceKind> optionalEvidence,
    required this.timingPolicyId,
    required this.primaryAction,
    required this.fallbackAction,
    required this.minimumConfidence,
    required this.dedupeGroup,
    required Iterable<String> suppresses,
    required Iterable<String> safetyConflicts,
    required Iterable<PhotographyPreferenceId> preferenceAffinities,
  }) : primaryScenes = Set.unmodifiable(primaryScenes),
       sceneFacets = Set.unmodifiable(sceneFacets),
       requiredEvidence = Set.unmodifiable(requiredEvidence),
       optionalEvidence = Set.unmodifiable(optionalEvidence),
       suppresses = Set.unmodifiable(suppresses),
       safetyConflicts = Set.unmodifiable(safetyConflicts),
       preferenceAffinities = Set.unmodifiable(preferenceAffinities);

  final String id;
  final CatalogTier catalogTier;
  final CoreCapabilityState? coreCapability;
  final OpportunityModelType modelType;
  final OpportunityFamily family;
  final OpportunityPresentation presentation;
  final Set<PrimaryScene> primaryScenes;
  final Set<SceneFacet> sceneFacets;
  final Set<EvidenceKind> requiredEvidence;
  final Set<EvidenceKind> optionalEvidence;
  final String? timingPolicyId;
  final ContextAction primaryAction;
  final ContextAction fallbackAction;
  final double? minimumConfidence;
  final String dedupeGroup;
  final Set<String> suppresses;
  final Set<String> safetyConflicts;
  final Set<PhotographyPreferenceId> preferenceAffinities;

  bool get isActiveCore =>
      catalogTier == CatalogTier.core &&
      coreCapability != CoreCapabilityState.unavailable;
}

class OpportunityTimingPolicy {
  const OpportunityTimingPolicy({
    required this.id,
    required this.catalogSpan,
    required this.actionableSpan,
    required this.advanceNotice,
    required this.farRefresh,
    required this.nearRefresh,
    required this.watchRefresh,
    required this.evidenceTtl,
    required this.windowRule,
  });

  final String id;
  final String catalogSpan;
  final String actionableSpan;
  final String advanceNotice;
  final String farRefresh;
  final String nearRefresh;
  final String watchRefresh;
  final Duration evidenceTtl;
  final String windowRule;
}

class OpportunityCatalog {
  OpportunityCatalog._({
    required this.version,
    required Iterable<OpportunityDefinition> definitions,
    required Iterable<OpportunityTimingPolicy> timingPolicies,
  }) : definitions = List.unmodifiable(definitions),
       timingPolicies = List.unmodifiable(timingPolicies),
       byId = Map.unmodifiable({for (final item in definitions) item.id: item}),
       timingById = Map.unmodifiable({
         for (final item in timingPolicies) item.id: item,
       });

  static final OpportunityCatalog current = _decodeGenerated();

  final int version;
  final List<OpportunityDefinition> definitions;
  final List<OpportunityTimingPolicy> timingPolicies;
  final Map<String, OpportunityDefinition> byId;
  final Map<String, OpportunityTimingPolicy> timingById;

  Iterable<OpportunityDefinition> get coreDefinitions =>
      definitions.where((item) => item.catalogTier == CatalogTier.core);

  static OpportunityCatalog _decodeGenerated() {
    final definitions = (jsonDecode(generatedOpportunityCatalogJson) as List)
        .cast<Map<String, Object?>>()
        .map(_definition)
        .toList(growable: false);
    final policies = (jsonDecode(generatedTimingPoliciesJson) as List)
        .cast<Map<String, Object?>>()
        .map(_timing)
        .toList(growable: false);
    return OpportunityCatalog._(
      version: opportunityCatalogVersion,
      definitions: definitions,
      timingPolicies: policies,
    );
  }

  static OpportunityDefinition _definition(Map<String, Object?> value) {
    final presentation = ((value['presentation'] as Map)['zhCN'] as Map)
        .cast<String, Object?>();
    return OpportunityDefinition(
      id: value['id']! as String,
      catalogTier: CatalogTier.values.byName(value['catalogTier']! as String),
      coreCapability: value['coreCapability'] == null
          ? null
          : CoreCapabilityState.values.byName(
              value['coreCapability']! as String,
            ),
      modelType: OpportunityModelType.values.byName(
        value['modelType']! as String,
      ),
      family: OpportunityFamily.values.byName(value['family']! as String),
      presentation: OpportunityPresentation(
        name: presentation['name']! as String,
        shortLabel: presentation['shortLabel']! as String,
        emoji: presentation['emoji']! as String,
        degradedName: presentation['degradedName'] as String?,
        fallbackSummary: presentation['fallbackSummary'] as String?,
      ),
      primaryScenes: _names(value, 'primaryScenes', PrimaryScene.values),
      sceneFacets: _names(value, 'sceneFacets', SceneFacet.values),
      requiredEvidence: _names(value, 'requiredEvidence', EvidenceKind.values),
      optionalEvidence: _names(value, 'optionalEvidence', EvidenceKind.values),
      timingPolicyId: value['timingPolicy'] as String?,
      primaryAction: ContextAction.values.byName(
        value['primaryAction']! as String,
      ),
      fallbackAction: ContextAction.values.byName(
        value['fallbackAction']! as String,
      ),
      minimumConfidence: (value['minimumConfidence'] as num?)?.toDouble(),
      dedupeGroup: value['dedupeGroup']! as String,
      suppresses: _strings(value, 'suppresses'),
      safetyConflicts: _strings(value, 'safetyConflicts'),
      preferenceAffinities: _names(
        value,
        'preferenceAffinities',
        PhotographyPreferenceId.values,
      ),
    );
  }

  static OpportunityTimingPolicy _timing(Map<String, Object?> value) {
    return OpportunityTimingPolicy(
      id: value['id']! as String,
      catalogSpan: value['catalogSpan']! as String,
      actionableSpan: value['actionableSpan']! as String,
      advanceNotice: value['advanceNotice']! as String,
      farRefresh: value['farRefresh']! as String,
      nearRefresh: value['nearRefresh']! as String,
      watchRefresh: value['watchRefresh']! as String,
      evidenceTtl: _minutes(value['evidenceTtl']! as String),
      windowRule: value['windowRule']! as String,
    );
  }

  static Iterable<T> _names<T extends Enum>(
    Map<String, Object?> value,
    String key,
    List<T> values,
  ) {
    return _strings(
      value,
      key,
    ).map((name) => values.firstWhere((item) => item.name == name));
  }

  static Iterable<String> _strings(Map<String, Object?> value, String key) =>
      (value[key]! as List).cast<String>();

  static Duration _minutes(String value) =>
      Duration(minutes: int.parse(value.substring(0, value.length - 1)));
}
