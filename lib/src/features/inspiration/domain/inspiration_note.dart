import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';

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
  static List<InspirationNote> build(ContextSnapshot snapshot) {
    final manifest = ManifestPolicy.build(snapshot);
    final notes = <InspirationNote>[
      for (final item in manifest.creativeItems) _fromManifest(item),
      ..._sceneCompanions(snapshot),
    ];

    final unique = <String, InspirationNote>{};
    for (final note in notes) {
      unique.putIfAbsent(note.id, () => note);
    }
    return unique.values.toList(growable: false)
      ..sort((a, b) => b.priority.compareTo(a.priority));
  }

  static InspirationNote _fromManifest(ManifestItem item) {
    return switch (item.id) {
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
  }

  static List<InspirationNote> _sceneCompanions(ContextSnapshot snapshot) {
    final sceneNote = switch (snapshot.primaryScene) {
      SceneType.lake => const InspirationNote(
        id: 'lake-companion',
        label: '去湖边',
        emoji: '🌊',
        category: InspirationCategory.place,
        action: ManifestAction.openExplore,
        detail: '沿岸走一小段，找出水面、岸线和远景的关系。',
        priority: 30,
        ttl: Duration(hours: 1),
      ),
      SceneType.mountain => const InspirationNote(
        id: 'mountain-companion',
        label: '长焦吧',
        emoji: '📷',
        category: InspirationCategory.composition,
        action: ManifestAction.openExplore,
        detail: '试试压缩山脊和云层，先找稳定的落脚点。',
        priority: 30,
        ttl: Duration(hours: 1),
      ),
      SceneType.village => const InspirationNote(
        id: 'village-companion',
        label: '慢一点',
        emoji: '🚶',
        category: InspirationCategory.composition,
        action: ManifestAction.openExplore,
        detail: '先观察街巷里的光和人的关系，再决定举起相机。',
        priority: 30,
        ttl: Duration(hours: 1),
      ),
      _ => const InspirationNote(
        id: 'look-back',
        label: '回头看',
        emoji: '👀',
        category: InspirationCategory.composition,
        action: ManifestAction.openExplore,
        detail: '先别急着赶路，回头看看光线正在落在哪里。',
        priority: 20,
        ttl: Duration(hours: 1),
      ),
    };
    return [sceneNote];
  }
}
