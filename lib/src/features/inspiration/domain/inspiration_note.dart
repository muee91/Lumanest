import 'dart:convert';

import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative.dart';
import 'package:luma_nest/src/core/photography/equipment_capability.dart';
import 'package:luma_nest/src/core/photography/opportunity_catalog.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/generated/opportunity_catalog.g.dart';
import 'package:luma_nest/src/features/sky_opportunity/domain/sky_opportunity.dart';

enum InspirationNoteKind { factualOpportunity, creativePrompt }

class InspirationNote {
  const InspirationNote({
    required this.id,
    required this.label,
    required this.emoji,
    required this.category,
    required this.kind,
    required this.action,
    required this.detail,
    required this.priority,
    required this.ttl,
    this.opportunityId,
    this.evidence = const <String>[],
    this.authorityUri,
    this.routeLocation,
  });

  final String id;
  final String label;
  final String emoji;
  final InspirationCategory category;
  final InspirationNoteKind kind;
  final ManifestAction action;
  final String detail;
  final int priority;
  final Duration ttl;
  final String? opportunityId;
  final List<String> evidence;
  final Uri? authorityUri;
  final String? routeLocation;

  bool get isFactual => kind == InspirationNoteKind.factualOpportunity;
  String get displayLabel => '$label$emoji';
}

enum InspirationCategory { light, weather, place, composition }

abstract final class InspirationNotes {
  static final List<_CreativeDefinition> _creativeCatalog =
      _decodeCreativeCatalog();

  static List<InspirationNote> build(
    ContextSnapshot snapshot, {
    ManifestNarrative? narrative,
    Iterable<EquipmentCapability> availableEquipment =
        const <EquipmentCapability>[],
    Iterable<SkyOpportunityForecast> skyOpportunities =
        const <SkyOpportunityForecast>[],
  }) {
    final sessionNotes = snapshot.shootingSessions
        .map((session) => _fromSession(session, narrative))
        .toList(growable: false);
    final skyNotes = skyOpportunities
        .where((item) => item.presentation.paperEligible)
        .map(_fromSkyOpportunity)
        .toList(growable: false);
    final factual = [...skyNotes, ...sessionNotes];
    final creative = _creativePrompts(
      snapshot,
      availableEquipment: availableEquipment.toSet(),
      maximum: 36 - factual.length,
    );
    return List.unmodifiable([...factual, ...creative]);
  }

  static InspirationNote _fromSkyOpportunity(SkyOpportunityForecast value) {
    final strong = {'excellent', 'rare', 'exceptional'}.contains(value.level);
    final label = strong
        ? '大烧预备'
        : value.eventType == SkyOpportunityEventType.sunset
        ? '今晚有戏'
        : '朝霞将至';
    return InspirationNote(
      id: value.id,
      label: label,
      emoji: value.eventType == SkyOpportunityEventType.sunset ? '🌇' : '🌅',
      category: InspirationCategory.light,
      kind: InspirationNoteKind.factualOpportunity,
      action: ManifestAction.openCreativeDetail,
      detail: '${value.primaryReason} · ${value.clarityLabel}',
      priority: strong ? 380 : 330,
      ttl: const Duration(hours: 6),
      opportunityId: value.id,
      evidence: [value.primaryReason, value.clarityLabel],
      routeLocation:
          '/sky-opportunity/${value.eventType.name}/${value.dayOffset}',
    );
  }

  static InspirationNote _fromSession(
    ShootingSession session,
    ManifestNarrative? narrative,
  ) {
    final definitionId = _definitionId(session.kind);
    final definition = OpportunityCatalog.current.byId[definitionId]!;
    final labelOverride =
        narrative?.noteLabels[session.id] ??
        narrative?.noteLabels[definitionId];
    final evidence = session.factors
        .take(3)
        .map((item) => '${item.label} ${item.value}')
        .toList(growable: false);
    return InspirationNote(
      id: session.id,
      label: labelOverride?.trim().isNotEmpty == true
          ? labelOverride!.trim()
          : definition.presentation.shortLabel,
      emoji: definition.presentation.emoji,
      category: _categoryForFamily(definition.family),
      kind: InspirationNoteKind.factualOpportunity,
      action: ManifestAction.openShootingWindow,
      detail: evidence.isEmpty ? session.title : evidence.join(' · '),
      priority: switch (session.conditionBand) {
        ShootingConditionBand.good => 300,
        ShootingConditionBand.fair => 250,
        ShootingConditionBand.limited => 180,
      },
      ttl: session.endsAt.difference(session.startsAt),
      opportunityId: session.id,
      evidence: evidence,
    );
  }

  static List<InspirationNote> _creativePrompts(
    ContextSnapshot snapshot, {
    required Set<EquipmentCapability> availableEquipment,
    required int maximum,
  }) {
    if (maximum <= 0) return const [];
    final scene = snapshot.resolvedSceneContext.primaryScene.name;
    final equipment = _equipmentTags(availableEquipment);
    final ranked = _creativeCatalog.toList(growable: false)
      ..sort((left, right) {
        final score = _creativeScore(
          right,
          scene,
          equipment,
        ).compareTo(_creativeScore(left, scene, equipment));
        return score != 0 ? score : left.id.compareTo(right.id);
      });
    return List.unmodifiable(
      ranked
          .take(maximum)
          .map(
            (definition) => InspirationNote(
              id: definition.id,
              label: definition.shortLabel,
              emoji: _creativeEmoji(definition.id),
              category: _creativeCategory(definition.id),
              kind: InspirationNoteKind.creativePrompt,
              action: ManifestAction.openCreativeDetail,
              detail: definition.guide,
              priority: 100 + _creativeScore(definition, scene, equipment),
              ttl: Duration(hours: definition.cooldownHours),
            ),
          ),
    );
  }

  static int _creativeScore(
    _CreativeDefinition definition,
    String scene,
    Set<String> equipment,
  ) {
    var score = definition.sceneAffinity.contains(scene)
        ? 20
        : definition.sceneAffinity.contains('all')
        ? 10
        : 0;
    if (definition.equipmentRequirement.isEmpty) {
      score += 4;
    } else if (equipment.containsAll(definition.equipmentRequirement)) {
      score += 8;
    }
    return score;
  }

  static Set<String> _equipmentTags(Set<EquipmentCapability> values) {
    final result = <String>{};
    for (final value in values) {
      switch (value) {
        case EquipmentCapability.tripod:
          result.add('tripod');
        case EquipmentCapability.wideAngle:
          result.add('wide_angle_lens');
        case EquipmentCapability.telephoto:
          result.add('telephoto_lens');
        case EquipmentCapability.filter:
          result.addAll(const {'nd_filter', 'gnd_filter', 'polarizer'});
        case EquipmentCapability.drone:
          result.add('drone');
        case EquipmentCapability.weatherProtection:
          result.add('rain_cover');
        case EquipmentCapability.headlamp:
          result.add('headlamp');
        case EquipmentCapability.camera:
        case EquipmentCapability.phoneCamera:
        case EquipmentCapability.fastLens:
          break;
      }
    }
    return result;
  }

  static String _definitionId(ShootingSessionKind kind) => switch (kind) {
    ShootingSessionKind.waterMorning => 'session.water.morning',
    ShootingSessionKind.waterEvening => 'session.water.evening',
    ShootingSessionKind.mountainMorning => 'session.mountain.morning',
    ShootingSessionKind.mountainEvening => 'session.mountain.evening',
    ShootingSessionKind.cityBlueHour => 'session.city.blue_hour',
    ShootingSessionKind.cityAfterRain => 'session.city.after_rain',
    ShootingSessionKind.desertSideLight => 'session.desert.side_light',
    ShootingSessionKind.routeLightWindow => 'session.route.light_window',
  };

  static InspirationCategory _categoryForFamily(OpportunityFamily family) =>
      switch (family) {
        OpportunityFamily.atmosphere => InspirationCategory.weather,
        OpportunityFamily.astronomy => InspirationCategory.light,
        OpportunityFamily.water ||
        OpportunityFamily.mountain ||
        OpportunityFamily.city ||
        OpportunityFamily.landform ||
        OpportunityFamily.ecology ||
        OpportunityFamily.humanityRoute => InspirationCategory.place,
      };

  static InspirationCategory _creativeCategory(String id) {
    if (id.startsWith('creative.light.') || id.startsWith('creative.color.')) {
      return InspirationCategory.light;
    }
    return InspirationCategory.composition;
  }

  static String _creativeEmoji(String id) {
    if (id.startsWith('creative.light.')) return '◐';
    if (id.startsWith('creative.motion.')) return '〰️';
    if (id.startsWith('creative.story.')) return '◫';
    if (id.startsWith('creative.color.')) return '◒';
    if (id.startsWith('creative.experiment.')) return '✦';
    if (id.startsWith('creative.angle.')) return '⌞';
    return '▱';
  }

  static List<_CreativeDefinition> _decodeCreativeCatalog() {
    final raw = jsonDecode(generatedCreativePromptsJson) as List;
    return List.unmodifiable(
      raw.cast<Map<String, Object?>>().map(
        (item) => _CreativeDefinition(
          id: item['id']! as String,
          shortLabel: item['shortLabel']! as String,
          guide: item['guide']! as String,
          sceneAffinity: Set.unmodifiable(
            (item['sceneAffinity']! as List).cast<String>(),
          ),
          equipmentRequirement: Set.unmodifiable(
            (item['equipmentRequirement']! as List).cast<String>(),
          ),
          cooldownHours: item['cooldownHours']! as int,
        ),
      ),
    );
  }
}

class _CreativeDefinition {
  const _CreativeDefinition({
    required this.id,
    required this.shortLabel,
    required this.guide,
    required this.sceneAffinity,
    required this.equipmentRequirement,
    required this.cooldownHours,
  });

  final String id;
  final String shortLabel;
  final String guide;
  final Set<String> sceneAffinity;
  final Set<String> equipmentRequirement;
  final int cooldownHours;
}
