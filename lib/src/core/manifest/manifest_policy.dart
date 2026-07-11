import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';

abstract final class ManifestPolicy {
  static UiManifest build(ContextSnapshot snapshot) {
    final creative = [
      ...snapshot.opportunityIds.map(_creativeItem),
      ...snapshot.wildlifeEventIds.map(_wildlifeCreativeItem),
    ].whereType<ManifestItem>().toList(growable: false);
    final safety = [
      ...snapshot.safetyEventIds.map(_safetyItem),
      ...snapshot.wildlifeEventIds.map(_wildlifeSafetyItem),
    ].whereType<ManifestItem>().toList(growable: false);
    final primary = creative.firstOrNull;

    return UiManifest(
      layoutMode: primary == null
          ? LayoutMode.quiet
          : snapshot.activeRoute
          ? LayoutMode.operation
          : LayoutMode.opportunity,
      summary: _summaryFor(snapshot, primary),
      primary: primary,
      secondary: creative.skip(1).take(2).toList(growable: false),
      safety: safety,
      inspirationPreview: _inspirationFor(primary),
    );
  }

  static ManifestItem? _creativeItem(String id) {
    return switch (id) {
      'reflection' => const ManifestItem(
        id: 'reflection',
        title: '倒影条件改善',
        action: ManifestAction.openExplore,
      ),
      'blue-hour' => const ManifestItem(
        id: 'blue-hour',
        title: '蓝调窗口将近',
        action: ManifestAction.openShootingWindow,
      ),
      'alpenglow' => const ManifestItem(
        id: 'alpenglow',
        title: '金山条件正在形成',
        action: ManifestAction.openShootingWindow,
      ),
      'mist' => const ManifestItem(
        id: 'mist',
        title: '雾气带来层次',
        action: ManifestAction.openWeather,
      ),
      _ => null,
    };
  }

  static ManifestItem? _safetyItem(String id) {
    return switch (id) {
      'thunderstorm' => const ManifestItem(
        id: 'thunderstorm',
        title: '雷暴正在接近',
        action: ManifestAction.openSafety,
      ),
      _ => null,
    };
  }

  static ManifestItem? _wildlifeCreativeItem(String id) {
    return switch (id) {
      'migratory-birds' => const ManifestItem(
        id: 'migratory-birds',
        title: '候鸟活动可能性较高',
        action: ManifestAction.openExplore,
      ),
      _ => null,
    };
  }

  static ManifestItem? _wildlifeSafetyItem(String id) {
    return switch (id) {
      'bear-risk' => const ManifestItem(
        id: 'bear-risk',
        title: '进入熊类历史活动区域',
        action: ManifestAction.openSafety,
      ),
      _ => null,
    };
  }

  static String _summaryFor(ContextSnapshot snapshot, ManifestItem? primary) {
    final opportunitySummary = switch (primary?.id) {
      'reflection' => '风正在变小，湖面倒影条件开始改善。',
      'blue-hour' => '天色即将进入蓝调，城市光线会更干净。',
      'alpenglow' => '低角度光线与山体条件正在靠近有效窗口。',
      'mist' => '雾气正在为画面增加层次。',
      'migratory-birds' => '当前季节与环境适合留意候鸟活动。',
      _ => null,
    };
    if (opportunitySummary != null) return opportunitySummary;

    return switch (snapshot.primaryScene) {
      SceneType.city => '光线平静，适合观察线条与人流。',
      SceneType.lake => '湖面暂时没有明显拍摄窗口。',
      SceneType.mountain => '山体光线条件暂不突出。',
      SceneType.desert => '留意地表纹理与远处层次。',
      SceneType.village => '慢下来观察街巷与人的关系。',
      SceneType.driving => '沿途暂时没有需要停靠的拍摄机会。',
      SceneType.hiking => '按当前节奏前进，留意环境变化。',
    };
  }

  static String _inspirationFor(ManifestItem? primary) {
    return switch (primary?.id) {
      'reflection' => '找倒影🪞',
      'blue-hour' => '蓝调了🌆',
      'alpenglow' => '金山⛰️',
      'mist' => '起雾了🌫️',
      'migratory-birds' => '候鸟来了🦅',
      _ => '回头看👀',
    };
  }
}
