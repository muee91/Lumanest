import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative.dart';

/// A short, actionable creative prompt shown in the inspiration bottle.
///
/// Facts and routing intent are produced by deterministic context rules. AI can
/// later refine the wording, but it must not invent the underlying event.
class InspirationNote {
  const InspirationNote({
    required this.id,
    required this.label,
    required this.emoji,
    required this.category,
    required this.action,
    required this.detail,
    required this.priority,
    required this.ttl,
  });

  final String id;
  final String label;
  final String emoji;
  final InspirationCategory category;
  final ManifestAction action;
  final String detail;
  final int priority;
  final Duration ttl;

  String get displayLabel => '$label$emoji';
}

enum InspirationCategory { light, weather, place, wildlife, composition }

abstract final class InspirationNotes {
  static List<InspirationNote> build(
    ContextSnapshot snapshot, {
    ManifestNarrative? narrative,
  }) {
    final manifest = ManifestPolicy.build(snapshot);
    final notes = <InspirationNote>[
      for (final item in manifest.creativeItems)
        _fromManifest(item, labelOverride: narrative?.noteLabels[item.id]),
    ];

    final unique = <String, InspirationNote>{};
    for (final note in notes) {
      unique.putIfAbsent(note.id, () => note);
    }
    return unique.values.toList(growable: false)
      ..sort((a, b) => b.priority.compareTo(a.priority));
  }

  static InspirationNote _fromManifest(
    ManifestItem item, {
    String? labelOverride,
  }) {
    final note = switch (item.id) {
      'reflection' => const InspirationNote(
        id: 'reflection',
        label: '找倒影',
        emoji: '🪞',
        category: InspirationCategory.place,
        action: ManifestAction.openExplore,
        detail: '风正在变小，去湖岸找一段干净的水面。',
        priority: 100,
        ttl: Duration(minutes: 30),
      ),
      'blue-hour' => const InspirationNote(
        id: 'blue-hour',
        label: '蓝调了',
        emoji: '🌆',
        category: InspirationCategory.light,
        action: ManifestAction.openShootingWindow,
        detail: '天色正在转蓝，适合留在有层次的城市或湖岸。',
        priority: 100,
        ttl: Duration(minutes: 35),
      ),
      'alpenglow' => const InspirationNote(
        id: 'alpenglow',
        label: '金山',
        emoji: '⛰️',
        category: InspirationCategory.light,
        action: ManifestAction.openShootingWindow,
        detail: '低角度光线正在靠近山体有效受光面。',
        priority: 100,
        ttl: Duration(minutes: 25),
      ),
      'mist' => const InspirationNote(
        id: 'mist',
        label: '起雾了',
        emoji: '🌫️',
        category: InspirationCategory.weather,
        action: ManifestAction.openWeather,
        detail: '雾气会拉开远近层次，先观察光线从哪里穿出来。',
        priority: 100,
        ttl: Duration(minutes: 40),
      ),
      'regional-wildlife' => const InspirationNote(
        id: 'regional-wildlife',
        label: '野外线索',
        emoji: '🦌',
        category: InspirationCategory.wildlife,
        action: ManifestAction.openExplore,
        detail: '来自 GBIF 区域公开记录。保持距离，不追逐或投喂野生动物。',
        priority: 95,
        ttl: Duration(hours: 2),
      ),
      'dust-light' => const InspirationNote(
        id: 'dust-light',
        label: '风沙光',
        emoji: '🏜️',
        category: InspirationCategory.light,
        action: ManifestAction.openShootingWindow,
        detail: '风沙与低角度光线正在形成粗粝层次，注意保护器材。',
        priority: 90,
        ttl: Duration(minutes: 20),
      ),
      'humanity-light' => const InspirationNote(
        id: 'humanity-light',
        label: '进巷子',
        emoji: '🏮',
        category: InspirationCategory.place,
        action: ManifestAction.openExplore,
        detail: '晨昏光线正在进入街巷，先观察人与环境再拍摄。',
        priority: 85,
        ttl: Duration(minutes: 25),
      ),
      _ => InspirationNote(
        id: item.id,
        label: item.title,
        emoji: '✨',
        category: InspirationCategory.composition,
        action: item.action,
        detail: item.title,
        priority: 80,
        ttl: const Duration(minutes: 30),
      ),
    };
    if (labelOverride == null || labelOverride.isEmpty) return note;
    return InspirationNote(
      id: note.id,
      label: labelOverride,
      emoji: note.emoji,
      category: note.category,
      action: note.action,
      detail: note.detail,
      priority: note.priority,
      ttl: note.ttl,
    );
  }
}
