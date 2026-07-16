import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative.dart';
import 'package:luma_nest/src/core/photography/equipment_capability.dart';
import 'package:luma_nest/src/core/photography/inspiration_proposal.dart';
import 'package:luma_nest/src/core/photography/photography_opportunity.dart';

/// A short prompt in the inspiration bottle.
///
/// [factualOpportunity] notes are backed by an already-established context
/// opportunity. [creativePrompt] notes are local composition exercises: they
/// intentionally make no claim about current weather, wildlife, risk, or a
/// particular place being recommended.
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
    this.evidence = const <PhotographyEvidence>[],
    this.authorityUri,
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

  /// Present only for a factual note; used to preserve the link to the
  /// deterministic decision that established it.
  final String? opportunityId;
  final List<PhotographyEvidence> evidence;
  final Uri? authorityUri;

  bool get isFactual => kind == InspirationNoteKind.factualOpportunity;
  String get displayLabel => '$label$emoji';
}

enum InspirationCategory { light, weather, place, composition }

abstract final class InspirationNotes {
  static List<InspirationNote> build(
    ContextSnapshot snapshot, {
    ManifestNarrative? narrative,
    UiManifest? manifest,
    Iterable<EquipmentCapability> availableEquipment =
        const <EquipmentCapability>[],
  }) {
    // V3 opportunities are the canonical source for factual notes. A V2
    // manifest remains a display-compatible fallback until old snapshots age
    // out; safety and wildlife channels are never eligible either way.
    final factual = snapshot.photographyOpportunities.isNotEmpty
        ? _fromOpportunities(snapshot.photographyOpportunities, narrative)
        : _fromManifest(
            manifest ?? ManifestPolicy.build(snapshot),
            narrative: narrative,
          );
    final creative = _creativePrompts(
      snapshot,
      availableEquipment: availableEquipment,
    );
    return _deduplicate([...factual, ...creative]);
  }

  static List<InspirationNote> _fromOpportunities(
    Iterable<PhotographyOpportunity> opportunities,
    ManifestNarrative? narrative,
  ) {
    final proposals = PhotographyInspirationProposalBuilder.build(
      opportunities: opportunities,
    );
    return [
      for (final proposal in proposals)
        _fromProposal(proposal, opportunities, narrative),
    ];
  }

  static InspirationNote _fromProposal(
    PhotographyInspirationProposal proposal,
    Iterable<PhotographyOpportunity> opportunities,
    ManifestNarrative? narrative,
  ) {
    final opportunity = opportunities.firstWhere(
      (item) => item.id == proposal.opportunityId,
    );
    final labelOverride = narrative?.noteLabels[proposal.id];
    return InspirationNote(
      id: proposal.id,
      label: labelOverride?.trim().isNotEmpty == true
          ? labelOverride!.trim()
          : proposal.label,
      emoji: _emojiFor(opportunity.kind),
      category: _categoryFor(opportunity.kind),
      kind: InspirationNoteKind.factualOpportunity,
      action: _actionForOpportunity(opportunity),
      detail: proposal.detail.isEmpty ? opportunity.title : proposal.detail,
      priority: 200 + opportunity.score,
      ttl: opportunity.expiresAt.difference(opportunity.startsAt),
      opportunityId: opportunity.id,
      evidence: proposal.evidence,
    );
  }

  static List<InspirationNote> _fromManifest(
    UiManifest manifest, {
    ManifestNarrative? narrative,
  }) => [
    for (final item in manifest.creativeItems)
      // Old manifests only expose creative context events. Do not use the
      // legacy wildlife hint: historical wildlife records belong to Explore,
      // never a bottle prompt.
      if (item.id != 'regional-wildlife')
        _legacyFactual(item, labelOverride: narrative?.noteLabels[item.id]),
  ];

  static InspirationNote _legacyFactual(
    ManifestItem item, {
    String? labelOverride,
  }) {
    final template = _legacyTemplate(item.id);
    final label = labelOverride?.trim();
    return InspirationNote(
      id: item.id,
      label: label?.isNotEmpty == true ? label! : template.label,
      emoji: template.emoji,
      category: template.category,
      kind: InspirationNoteKind.factualOpportunity,
      action: item.action,
      detail: template.detail,
      priority: template.priority,
      ttl: template.ttl,
      authorityUri: item.authorityUri,
    );
  }

  static List<InspirationNote> _creativePrompts(
    ContextSnapshot snapshot, {
    required Iterable<EquipmentCapability> availableEquipment,
  }) {
    final scenePrompt = switch (snapshot.primaryScene) {
      SceneType.lake => _creative(
        'creative:lake-foreground',
        '压低机位',
        '🪞',
        '让一段近处岸线或石头先进入画面，再留出主体的呼吸空间。',
      ),
      SceneType.mountain => _creative(
        'creative:mountain-layer',
        '留出山脊',
        '⛰️',
        '把前、中、远三层分开，先决定哪一层承担画面的重量。',
      ),
      SceneType.village => _creative(
        'creative:village-frame',
        '借一扇门',
        '🏮',
        '用门、窗或屋檐收住画面边缘，给人物和环境留一点距离。',
      ),
      SceneType.desert => _creative(
        'creative:desert-line',
        '顺着线走',
        '🏜️',
        '找一条自然延伸的纹理或道路，让它带着视线进入画面。',
      ),
      SceneType.hiking => _creative(
        'creative:hiking-scale',
        '留一个尺度',
        '🥾',
        '在画面里保留一个人或物件，让空间感有可感知的尺度。',
      ),
      SceneType.driving => _creative(
        'creative:driving-window',
        '先定一扇窗',
        '🚗',
        '先决定画面边缘，再等待主体进入那块留白。',
      ),
      SceneType.city => _creative(
        'creative:city-rhythm',
        '等一拍节奏',
        '🌆',
        '固定一个构图，等人物、车流或光影把画面推到平衡。',
      ),
      SceneType.unknown => _creative(
        'creative:unknown-frame',
        '留一处边缘',
        '▱',
        '先用一个边缘收住画面，再决定主体要留在哪里。',
      ),
    };
    final lightPrompt = _creative(
      'creative:light-balance:${snapshot.dayPhase.name}',
      '先看明暗',
      '◐',
      '先让最亮和最暗的部分各有位置，再决定主体要不要居中。',
    );
    final equipmentPrompt = _equipmentPrompt(availableEquipment.toSet());
    return [scenePrompt, lightPrompt, ?equipmentPrompt];
  }

  static InspirationNote _creative(
    String id,
    String label,
    String emoji,
    String detail,
  ) => InspirationNote(
    id: id,
    label: label,
    emoji: emoji,
    category: InspirationCategory.composition,
    kind: InspirationNoteKind.creativePrompt,
    action: ManifestAction.openExplore,
    detail: detail,
    priority: 20,
    ttl: const Duration(hours: 24),
  );

  static InspirationNote? _equipmentPrompt(Set<EquipmentCapability> equipment) {
    if (equipment.contains(EquipmentCapability.telephoto)) {
      return _creative(
        'creative:equipment-telephoto',
        '压缩远景',
        '🔭',
        '用较长焦段靠后取景，把远处的形状和层次叠进同一个画面。',
      );
    }
    if (equipment.contains(EquipmentCapability.wideAngle)) {
      return _creative(
        'creative:equipment-wide-angle',
        '靠近前景',
        '◒',
        '用广角靠近一个明确前景，让它把视线带向主体。',
      );
    }
    if (equipment.contains(EquipmentCapability.tripod)) {
      return _creative(
        'creative:equipment-tripod',
        '固定一张',
        '△',
        '先固定构图，再只观察画面里会自行变化的部分。',
      );
    }
    return null;
  }

  static List<InspirationNote> _deduplicate(Iterable<InspirationNote> notes) {
    final unique = <String, InspirationNote>{};
    for (final note in notes) {
      unique.putIfAbsent(note.id, () => note);
    }
    return List.unmodifiable(unique.values);
  }

  static ManifestAction _actionForOpportunity(PhotographyOpportunity value) =>
      value.primaryAction == null
      ? ManifestAction.openShootingWindow
      : ManifestAction.fromContextAction(value.primaryAction!);

  static InspirationCategory _categoryFor(PhotographyOpportunityKind kind) =>
      switch (kind) {
        PhotographyOpportunityKind.reflection => InspirationCategory.place,
        PhotographyOpportunityKind.morningMist => InspirationCategory.weather,
        _ => InspirationCategory.light,
      };

  static String _emojiFor(PhotographyOpportunityKind kind) => switch (kind) {
    PhotographyOpportunityKind.reflection => '🪞',
    PhotographyOpportunityKind.blueHour => '🌆',
    PhotographyOpportunityKind.alpenglow => '⛰️',
    PhotographyOpportunityKind.morningMist => '🌫️',
    PhotographyOpportunityKind.sunsetGlow => '🌅',
    PhotographyOpportunityKind.astronomy => '🌙',
  };

  static _LegacyTemplate _legacyTemplate(String id) => switch (id) {
    'reflection' => const _LegacyTemplate(
      label: '找倒影',
      emoji: '🪞',
      category: InspirationCategory.place,
      detail: '风正在变小，去湖岸找一段干净的水面。',
      priority: 100,
      ttl: Duration(minutes: 30),
    ),
    'blue-hour' => const _LegacyTemplate(
      label: '蓝调了',
      emoji: '🌆',
      category: InspirationCategory.light,
      detail: '天色正在转蓝，适合留在有层次的城市或湖岸。',
      priority: 100,
      ttl: Duration(minutes: 35),
    ),
    'alpenglow' => const _LegacyTemplate(
      label: '金山',
      emoji: '⛰️',
      category: InspirationCategory.light,
      detail: '低角度光线正在靠近山体有效受光面。',
      priority: 100,
      ttl: Duration(minutes: 25),
    ),
    'mist' => const _LegacyTemplate(
      label: '起雾了',
      emoji: '🌫️',
      category: InspirationCategory.weather,
      detail: '雾气会拉开远近层次，先观察光线从哪里穿出来。',
      priority: 100,
      ttl: Duration(minutes: 40),
    ),
    'dust-light' => const _LegacyTemplate(
      label: '风沙光',
      emoji: '🏜️',
      category: InspirationCategory.light,
      detail: '风沙与低角度光线正在形成粗粝层次，注意保护器材。',
      priority: 90,
      ttl: Duration(minutes: 20),
    ),
    'humanity-light' => const _LegacyTemplate(
      label: '进巷子',
      emoji: '🏮',
      category: InspirationCategory.place,
      detail: '晨昏光线正在进入街巷，先观察人与环境再拍摄。',
      priority: 85,
      ttl: Duration(minutes: 25),
    ),
    _ => _LegacyTemplate(
      label: id,
      emoji: '✨',
      category: InspirationCategory.composition,
      detail: id,
      priority: 80,
      ttl: const Duration(minutes: 30),
    ),
  };
}

class _LegacyTemplate {
  const _LegacyTemplate({
    required this.label,
    required this.emoji,
    required this.category,
    required this.detail,
    required this.priority,
    required this.ttl,
  });

  final String label;
  final String emoji;
  final InspirationCategory category;
  final String detail;
  final int priority;
  final Duration ttl;
}
