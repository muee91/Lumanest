import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/context/environment_consent.dart';
import '../../../core/context/environment_providers.dart';
import '../application/profile_preferences_controller.dart';
import '../application/environment_privacy_service.dart';
import '../domain/profile_preferences.dart';
import '../../library/application/user_library_controller.dart';
import '../../library/domain/user_library.dart';
import 'environment_diagnostics.dart';

/// Local profile settings surface.
///
/// Only groups backed by real local data are rendered. Saved places, recent
/// routes and imported GPX tracks appear on demand; no empty collection or
/// device placeholders reserve space.
///
/// Environment diagnostics appear only when a problem or stale fallback
/// exists; a healthy system reserves no space. Recovery action callbacks are
/// wired by default for the live app. Tests and alternate hosts can inject
/// [actions] to replace those platform callbacks deterministically.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key, this.actions});

  /// Optional recovery action override for tests or an embedding host.
  final EnvironmentDiagnosticsActions? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(profilePreferencesProvider);
    final controller = ref.read(profilePreferencesProvider.notifier);
    final diagnosticStatus = ref.watch(environmentDiagnosticStatusProvider);
    final library = ref.watch(userLibraryProvider).asData?.value;
    final environmentConsentGranted = ref.watch(environmentConsentProvider);

    final liveActions = EnvironmentDiagnosticsActions(
      onRetry: () => ref.read(environmentSnapshotProvider.notifier).refresh(),
      onOpenAppSettings: Geolocator.openAppSettings,
      onOpenLocationSettings: Geolocator.openLocationSettings,
      onOpenPrivacyConsent: () =>
          ref.read(environmentConsentProvider.notifier).grant(),
    );
    final effectiveActions = actions ?? liveActions;

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: [
          EnvironmentDiagnostics(
            status: diagnosticStatus,
            actions: effectiveActions,
          ),
          SwitchListTile(
            title: const Text('动态背景'),
            value: preferences.ambientBackgroundEnabled,
            onChanged: (_) => controller.toggleAmbientBackground(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<AmbientMotionMode>(
              segments: const [
                ButtonSegment(value: AmbientMotionMode.full, label: Text('完整')),
                ButtonSegment(
                  value: AmbientMotionMode.energySaver,
                  label: Text('节能'),
                ),
                ButtonSegment(
                  value: AmbientMotionMode.staticColor,
                  label: Text('静态'),
                ),
              ],
              selected: {preferences.ambientMotionMode},
              onSelectionChanged: preferences.ambientBackgroundEnabled
                  ? (selection) =>
                        controller.setAmbientMotionMode(selection.single)
                  : null,
            ),
          ),
          SwitchListTile(
            title: const Text('减少动效'),
            value: preferences.reduceMotion,
            onChanged: (_) => controller.toggleReduceMotion(),
          ),
          SwitchListTile(
            title: const Text('减少闪烁'),
            value: preferences.reduceFlashing,
            onChanged: (_) => controller.toggleReduceFlashing(),
          ),
          SwitchListTile(
            title: const Text('高对比度'),
            subtitle: const Text('增强文字、按钮和背景之间的区分'),
            value: preferences.highContrast,
            onChanged: (_) => controller.toggleHighContrast(),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text('摄影偏好', style: Theme.of(context).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              children: [
                for (final option in _photographyOptions)
                  FilterChip(
                    label: Text(option),
                    selected: preferences.photographyPreferences.contains(
                      option,
                    ),
                    onSelected: (_) =>
                        controller.togglePhotographyPreference(option),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text('活动偏好', style: Theme.of(context).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              children: [
                for (final option in _activityOptions)
                  FilterChip(
                    label: Text(option),
                    selected: preferences.activityPreferences.contains(option),
                    onSelected: (_) =>
                        controller.toggleActivityPreference(option),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text('设备', style: Theme.of(context).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _EquipmentField(
              initialValue: preferences.equipmentList,
              onChanged: controller.setEquipmentList,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(
              'AI 语气',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<AiTone>(
              segments: const [
                ButtonSegment(value: AiTone.concise, label: Text('简洁')),
                ButtonSegment(value: AiTone.balanced, label: Text('均衡')),
                ButtonSegment(value: AiTone.detailed, label: Text('详细')),
              ],
              selected: {preferences.aiTone},
              onSelectionChanged: (selection) =>
                  controller.setAiTone(selection.single),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Text('推荐强度', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Slider(
              value: preferences.recommendationIntensity,
              min: 0,
              max: 1,
              divisions: 10,
              label: '${(preferences.recommendationIntensity * 100).round()}%',
              onChanged: controller.setRecommendationIntensity,
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('环境数据与定位'),
            subtitle: Text(
              environmentConsentGranted ? '已启用当前位置、天气与场景分析' : '未启用环境数据',
            ),
            trailing: environmentConsentGranted
                ? TextButton(
                    onPressed: () =>
                        _confirmEnvironmentDataRemoval(context, ref),
                    child: const Text('停止并清除'),
                  )
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.dataset_outlined),
            title: const Text('数据来源与使用说明'),
            subtitle: const Text('天气、地图、高程和野生动物数据'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showDataSources(context),
          ),
          if (library?.recentRoute case final recent?) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('最近路线'),
              subtitle: Text(recent.name),
              trailing: const Icon(Icons.arrow_outward),
              onTap: () => context.go(_routeUri(recent).toString()),
            ),
          ],
          if (library?.importedTracks.isNotEmpty == true) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Text(
                '本地轨迹',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final track in library!.importedTracks)
              ListTile(
                leading: const Icon(Icons.hiking_outlined),
                title: Text(track.name),
                subtitle: const Text('GPX · 仅保存在本机'),
                trailing: IconButton(
                  tooltip: '删除轨迹',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => ref
                      .read(userLibraryProvider.notifier)
                      .deleteImportedTrack(track.id),
                ),
                onTap: () => context.go(
                  Uri(
                    path: '/route',
                    queryParameters: {'track': track.id},
                  ).toString(),
                ),
              ),
          ],
          if (library?.savedPlaces.isNotEmpty == true) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Text(
                '我的收藏',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final place in library!.savedPlaces)
              ListTile(
                leading: const Icon(Icons.bookmark),
                title: Text(place.name),
                trailing: IconButton(
                  tooltip: '取消收藏',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () =>
                      ref.read(userLibraryProvider.notifier).togglePlace(place),
                ),
                onTap: () {
                  final destination = SavedRouteDestination(
                    name: place.name,
                    latitude: place.latitude,
                    longitude: place.longitude,
                    travelMode: 'driving',
                  );
                  ref
                      .read(userLibraryProvider.notifier)
                      .saveRecentRoute(destination);
                  context.go(_routeUri(destination).toString());
                },
              ),
          ],
        ],
      ),
    );
  }

  static Uri _routeUri(SavedRouteDestination destination) => Uri(
    path: '/route',
    queryParameters: {
      'name': destination.name,
      'lat': '${destination.latitude}',
      'lon': '${destination.longitude}',
      'mode': destination.travelMode,
    },
  );

  static Future<void> _confirmEnvironmentDataRemoval(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('停止使用环境数据？'),
        content: const Text('将清除缓存的位置、天气、场景和手动地点。不会删除收藏与路线，也不会修改系统定位权限。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('停止并清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(environmentPrivacyServiceProvider).revokeAndClear();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('环境数据已停止使用并清除')));
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('清除失败，请重试')));
    }
  }
}

Future<void> _showDataSources(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('数据来源与使用说明'),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DataSourceEntry(
              title: '天气 · 和风天气',
              detail: '提供实况天气与相关气象字段。安全信息不能替代官方预警和现场判断。',
            ),
            _DataSourceEntry(
              title: '地图与路线 · 高德地图',
              detail: '提供国内地图、地点检索及驾车和步行路线。App 不承担逐向导航。',
            ),
            _DataSourceEntry(
              title: '路线高程 · Open-Meteo',
              detail: '基于最多 64 个路线采样点估算，仅供行程参考，不替代专业测绘或户外设备。',
            ),
            _DataSourceEntry(
              title: '野生动物 · GBIF',
              detail: '显示区域级公开历史记录，不代表实时位置或确定风险；敏感物种不展示精确坐标。',
            ),
            _DataSourceEntry(
              title: '太阳与拍摄窗口 · 本地计算',
              detail: '根据时间和 WGS84 位置计算；缺少地形遮挡数据时不会声称精确可见。',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('知道了')),
      ],
    ),
  );
}

class _DataSourceEntry extends StatelessWidget {
  const _DataSourceEntry({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

const _photographyOptions = ['风光', '人文', '星空', '城市'];

const _activityOptions = ['自驾', '轻徒步', '重装徒步', '小众探索'];

class _EquipmentField extends StatefulWidget {
  const _EquipmentField({required this.initialValue, required this.onChanged});

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<_EquipmentField> createState() => _EquipmentFieldState();
}

class _EquipmentFieldState extends State<_EquipmentField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _EquipmentField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        _controller.text != widget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: const InputDecoration(
        hintText: '相机、镜头、三脚架等',
        border: OutlineInputBorder(),
      ),
      onChanged: widget.onChanged,
    );
  }
}
