import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/context/environment_consent.dart';
import '../../../core/context/environment_providers.dart';
import '../../../core/context/route_context_state.dart';
import '../application/profile_preferences_controller.dart';
import '../application/environment_privacy_service.dart';
import '../application/environment_cache_maintenance_service.dart';
import '../domain/profile_preferences.dart';
import '../../library/application/user_library_controller.dart';
import '../../library/domain/user_library.dart';
import '../../location/application/base_region_controller.dart';
import '../../location/application/manual_location_providers.dart';
import '../../location/presentation/manual_location_sheet.dart';
import '../../notifications/application/route_reminder_service.dart';
import '../../../shared/actions/manifest_action_handler.dart';
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
    final baseRegion = ref.watch(baseRegionProvider).asData?.value;
    final cacheStatus = ref.watch(environmentCacheStatusProvider);
    final routeReminderEnabled = ref.watch(routeReminderEnabledProvider);
    final hasLibraryContent =
        library != null &&
        (library.recentRoute != null ||
            library.savedRoutes.isNotEmpty ||
            library.journeys.isNotEmpty ||
            library.importedTracks.isNotEmpty ||
            library.savedNotes.isNotEmpty ||
            library.savedPlaces.isNotEmpty);

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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const _ProfileHero(),
          const SizedBox(height: 18),
          EnvironmentDiagnostics(
            status: diagnosticStatus,
            actions: effectiveActions,
          ),
          const _ProfileSectionTitle(
            icon: Icons.tune_rounded,
            title: '体验与个性',
            subtitle: '只影响本机呈现与推荐顺序',
          ),
          _ProfileSurface(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('动态背景'),
                  value: preferences.ambientBackgroundEnabled,
                  onChanged: (_) => controller.toggleAmbientBackground(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: SegmentedButton<AmbientMotionMode>(
                    segments: const [
                      ButtonSegment(
                        value: AmbientMotionMode.full,
                        label: Text('完整'),
                      ),
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
                  child: Text(
                    '摄影偏好',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
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
                  child: Text(
                    '活动偏好',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final option in _activityOptions)
                        FilterChip(
                          label: Text(option),
                          selected: preferences.activityPreferences.contains(
                            option,
                          ),
                          onSelected: (_) =>
                              controller.toggleActivityPreference(option),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Text(
                    '设备',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
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
                      Text(
                        '推荐强度',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
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
                    label:
                        '${(preferences.recommendationIntensity * 100).round()}%',
                    onChanged: controller.setRecommendationIntensity,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _ProfileSectionTitle(
            icon: Icons.lock_outline_rounded,
            title: '本机与隐私',
            subtitle: '位置、缓存与记录由你控制',
          ),
          _ProfileSurface(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('常驻地区'),
                  subtitle: Text(
                    baseRegion == null
                        ? '未设置'
                        : [
                            baseRegion.name,
                            baseRegion.address,
                          ].whereType<String>().join(' · '),
                  ),
                  trailing: baseRegion == null
                      ? const Icon(Icons.chevron_right)
                      : TextButton(
                          onPressed: () =>
                              _confirmBaseRegionRemoval(context, ref),
                          child: const Text('清除'),
                        ),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) =>
                        const ManualLocationSheet(saveAsBaseRegion: true),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.offline_bolt_outlined),
                  title: const Text('离线环境数据'),
                  subtitle: Text(_cacheSubtitle(cacheStatus)),
                  trailing: TextButton(
                    onPressed: cacheStatus.isLoading
                        ? null
                        : () => _confirmCacheClear(context, ref),
                    child: const Text('清除缓存'),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: const Text('徒步返程提醒'),
                  subtitle: Text(
                    routeReminderEnabled.when(
                      data: (enabled) => enabled
                          ? '开始徒步行程后，按最晚返程时间安排本地通知'
                          : '关闭；不会在后台持续获取位置或天气',
                      loading: () => '正在读取本机设置',
                      error: (_, _) => '暂时无法读取通知设置',
                    ),
                  ),
                  value: routeReminderEnabled.asData?.value ?? false,
                  onChanged: routeReminderEnabled.isLoading
                      ? null
                      : (value) async {
                          try {
                            final enabled = await ref
                                .read(routeReminderEnabledProvider.notifier)
                                .setEnabled(value);
                            if (!value || enabled || !context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('未获得系统通知权限，返程提醒保持关闭'),
                              ),
                            );
                          } on Object {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('通知设置未能更新，请稍后重试')),
                            );
                          }
                        },
                ),
                const Divider(height: 1),
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
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.dataset_outlined),
                  title: const Text('数据来源与使用说明'),
                  subtitle: const Text('天气、地图、高程和野生动物数据'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showDataSources(context),
                ),
              ],
            ),
          ),
          if (hasLibraryContent) ...[
            const SizedBox(height: 20),
            const _ProfileSectionTitle(
              icon: Icons.inventory_2_outlined,
              title: '本机收藏',
              subtitle: '路线、行程、纸条与地点',
            ),
          ],
          if (library?.recentRoute case final recent?) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('最近路线'),
              subtitle: Text(recent.name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '清除最近路线',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmLibraryClear(
                      context,
                      ref,
                      type: _LibraryClearType.recentRoute,
                    ),
                  ),
                  const Icon(Icons.arrow_outward),
                ],
              ),
              onTap: () => context.go(_routeUri(recent).toString()),
            ),
          ],
          if (library?.savedRoutes.isNotEmpty == true) ...[
            const Divider(),
            _LibrarySectionHeader(
              title: '已保存路线',
              clearLabel: '清空路线',
              onClear: () => _confirmLibraryClear(
                context,
                ref,
                type: _LibraryClearType.savedRoutes,
              ),
            ),
            for (final route in library!.savedRoutes)
              ListTile(
                leading: const Icon(Icons.bookmark_outline),
                title: Text(route.destination.name),
                subtitle: Text(
                  '${route.destination.travelMode == 'walking' ? '徒步' : '自驾'} · 仅保存在本机',
                ),
                trailing: IconButton(
                  tooltip: '删除已保存路线',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => ref
                      .read(userLibraryProvider.notifier)
                      .deleteSavedRoute(route.id),
                ),
                onTap: () =>
                    context.go(_routeUri(route.destination).toString()),
              ),
          ],
          if (library?.journeys.isNotEmpty == true) ...[
            const Divider(),
            _LibrarySectionHeader(
              title: '行程记录',
              clearLabel: '清空行程',
              onClear: () => _confirmLibraryClear(
                context,
                ref,
                type: _LibraryClearType.journeys,
              ),
            ),
            for (final journey in library!.journeys)
              ListTile(
                leading: Icon(
                  journey.isActive
                      ? Icons.play_circle_outline
                      : Icons.check_circle_outline,
                ),
                title: Text(journey.destination.name),
                subtitle: Text(
                  journey.isActive
                      ? '进行中 · 仅保存在本机'
                      : '${journey.destination.travelMode == 'walking' ? '徒步' : '自驾'} · ${_dateTime(journey.startedAt)}',
                ),
                trailing: IconButton(
                  tooltip: '删除行程记录',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteJourney(context, ref, journey),
                ),
                onTap: () => context.go(_journeyUri(journey).toString()),
              ),
          ],
          if (library?.importedTracks.isNotEmpty == true) ...[
            const Divider(),
            _LibrarySectionHeader(
              title: '本地轨迹',
              clearLabel: '清空轨迹',
              onClear: library?.activeJourney?.routeKey == null
                  ? () => _confirmLibraryClear(
                      context,
                      ref,
                      type: _LibraryClearType.importedTracks,
                    )
                  : () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请先结束正在进行的本地轨迹行程')),
                    ),
            ),
            for (final track in library!.importedTracks)
              ListTile(
                leading: const Icon(Icons.hiking_outlined),
                title: Text(track.name),
                subtitle: Text(
                  library.activeJourney?.routeKey == track.id
                      ? 'GPX · 进行中行程正在使用'
                      : 'GPX · 仅保存在本机',
                ),
                trailing: IconButton(
                  tooltip: library.activeJourney?.routeKey == track.id
                      ? '进行中行程正在使用'
                      : '删除轨迹',
                  icon: Icon(
                    library.activeJourney?.routeKey == track.id
                        ? Icons.lock_outline
                        : Icons.delete_outline,
                  ),
                  onPressed: library.activeJourney?.routeKey == track.id
                      ? null
                      : () => ref
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
          if (library?.savedNotes.isNotEmpty == true) ...[
            const Divider(),
            _LibrarySectionHeader(
              title: '收藏纸条',
              clearLabel: '清空纸条',
              onClear: () => _confirmLibraryClear(
                context,
                ref,
                type: _LibraryClearType.savedNotes,
              ),
            ),
            for (final note in library!.savedNotes)
              Builder(
                builder: (context) {
                  final actionItem = note.manifestItem;
                  return ListTile(
                    leading: const Icon(Icons.bookmark_outline),
                    title: Text(note.displayLabel),
                    subtitle: Text(note.detail),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '删除纸条',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => ref
                              .read(userLibraryProvider.notifier)
                              .deleteSavedNote(note.id),
                        ),
                        if (actionItem != null)
                          const Icon(Icons.arrow_outward, size: 18),
                      ],
                    ),
                    onTap: actionItem == null
                        ? null
                        : () => handleManifestAction(
                            context,
                            actionItem,
                            detailOverride: note.detail,
                          ),
                  );
                },
              ),
          ],
          if (library?.savedPlaces.isNotEmpty == true) ...[
            const Divider(),
            _LibrarySectionHeader(
              title: '我的收藏',
              clearLabel: '清空收藏',
              onClear: () => _confirmLibraryClear(
                context,
                ref,
                type: _LibraryClearType.savedPlaces,
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

  static Uri _journeyUri(SavedJourney journey) => journey.routeKey == null
      ? _routeUri(journey.destination)
      : Uri(path: '/route', queryParameters: {'track': journey.routeKey});

  static String _dateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.month}月${local.day}日 '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static Future<void> _deleteJourney(
    BuildContext context,
    WidgetRef ref,
    SavedJourney journey,
  ) async {
    if (journey.isActive) {
      try {
        await ref.read(routeReminderServiceProvider).cancel(journey.id);
      } on Object {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('系统返程提醒未能取消，行程记录仍保留')));
        return;
      }
      ref.read(routeContextStateProvider.notifier).end();
    }
    await ref.read(userLibraryProvider.notifier).deleteJourney(journey.id);
  }

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

  static String _cacheSubtitle(AsyncValue<EnvironmentCacheStatus> status) {
    return status.when(
      loading: () => '正在读取本机缓存',
      error: (_, _) => '暂时无法读取缓存状态',
      data: (value) => switch (value.availability) {
        EnvironmentCacheAvailability.absent => '本机没有可用的环境缓存',
        EnvironmentCacheAvailability.current =>
          '${value.snapshot!.primaryScene.name} · 可离线使用至 ${_time(value.snapshot!.expiresAt)}',
        EnvironmentCacheAvailability.stale =>
          '${value.snapshot!.primaryScene.name} · 已过期（${_time(value.snapshot!.observedAt)}）',
      },
    );
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.month}月${local.day}日 ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  static Future<void> _confirmCacheClear(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除离线环境数据？'),
        content: const Text('只会清除本机缓存的天气、场景和路线环境快照；不会删除常驻地区、收藏、路线或系统权限。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清除缓存'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(environmentCacheMaintenanceServiceProvider).clear();
      ref.invalidate(environmentCacheStatusProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('离线环境缓存已清除')));
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('清除失败，请重试')));
      }
    }
  }

  static Future<void> _confirmBaseRegionRemoval(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除常驻地区？'),
        content: const Text('将恢复使用设备当前位置；不会清除离线环境缓存、收藏或路线。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final baseRegion = ref.read(baseRegionProvider).asData?.value;
    final manualLocation = ref.read(manualLocationProvider);
    await ref.read(baseRegionProvider.notifier).clear();
    if (baseRegion != null &&
        manualLocation != null &&
        manualLocation.location.point.latitude ==
            baseRegion.location.point.latitude &&
        manualLocation.location.point.longitude ==
            baseRegion.location.point.longitude) {
      ref.read(manualLocationProvider.notifier).clear();
    }
    ref.invalidate(environmentSnapshotProvider);
  }

  static Future<void> _confirmLibraryClear(
    BuildContext context,
    WidgetRef ref, {
    required _LibraryClearType type,
  }) async {
    final (title, content, action) = switch (type) {
      _LibraryClearType.savedPlaces => (
        '清空收藏？',
        '将永久删除本机收藏的地点；不会删除路线、轨迹或环境数据。',
        '清空收藏',
      ),
      _LibraryClearType.recentRoute => (
        '清除最近路线？',
        '将删除本机保存的最近路线；不会删除收藏、导入轨迹或环境数据。',
        '清除',
      ),
      _LibraryClearType.savedRoutes => (
        '清空已保存路线？',
        '将永久删除本机主动保存的路线；不会删除最近路线、导入轨迹、收藏或环境数据。',
        '清空路线',
      ),
      _LibraryClearType.journeys => (
        '清空行程记录？',
        '将永久删除本机的进行中和已结束行程；不会删除保存路线、轨迹、收藏或环境数据。',
        '清空行程',
      ),
      _LibraryClearType.importedTracks => (
        '清空本地轨迹？',
        '将永久删除本机导入的 GPX 轨迹；不会删除收藏、路线或环境数据。',
        '清空轨迹',
      ),
      _LibraryClearType.savedNotes => (
        '清空收藏纸条？',
        '将永久删除本机收藏的灵感纸条；不会删除收藏地点、路线、轨迹或环境数据。',
        '清空纸条',
      ),
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final controller = ref.read(userLibraryProvider.notifier);
    switch (type) {
      case _LibraryClearType.savedPlaces:
        await controller.clearSavedPlaces();
      case _LibraryClearType.recentRoute:
        await controller.clearRecentRoute();
      case _LibraryClearType.savedRoutes:
        await controller.clearSavedRoutes();
      case _LibraryClearType.journeys:
        try {
          await ref.read(routeReminderServiceProvider).cancelAll();
        } on Object {
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('系统返程提醒未能取消，行程记录仍保留')));
          return;
        }
        ref.read(routeContextStateProvider.notifier).end();
        await controller.clearJourneys();
      case _LibraryClearType.importedTracks:
        await controller.clearImportedTracks();
      case _LibraryClearType.savedNotes:
        await controller.clearSavedNotes();
    }
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.secondaryContainer.withValues(alpha: .92),
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: .84),
          ],
        ),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: .22),
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary.withValues(alpha: .14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.camera_outlined,
              color: theme.colorScheme.secondary,
              size: 25,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('只属于你的栖光', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  '无账号，偏好与创作记录优先留在本机。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: .74),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text('本机', style: theme.textTheme.labelSmall),
          ),
        ],
      ),
    );
  }
}

class _ProfileSectionTitle extends StatelessWidget {
  const _ProfileSectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 9),
    child: Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ProfileSurface extends StatelessWidget {
  const _ProfileSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(
      context,
    ).colorScheme.surfaceContainerLow.withValues(alpha: .88),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

enum _LibraryClearType {
  savedPlaces,
  recentRoute,
  savedRoutes,
  journeys,
  importedTracks,
  savedNotes,
}

class _LibrarySectionHeader extends StatelessWidget {
  const _LibrarySectionHeader({
    required this.title,
    required this.clearLabel,
    required this.onClear,
  });

  final String title;
  final String clearLabel;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          TextButton(onPressed: onClear, child: Text(clearLabel)),
        ],
      ),
    );
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
