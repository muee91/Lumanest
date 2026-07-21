import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/entry/entry_payload.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/core/scenario/scenario_providers.dart';
import 'package:luma_nest/src/core/scenario/surface_composition.dart';
import 'package:luma_nest/src/features/location/application/environment_location_display.dart';
import 'package:luma_nest/src/features/location/presentation/manual_location_sheet.dart';
import 'package:luma_nest/src/presentation_v2/entry/entry_action_dispatcher.dart';
import 'package:luma_nest/src/presentation_v2/entry/entry_card_registry.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';

class V2TodayPage extends ConsumerWidget {
  const V2TodayPage({super.key, this.initialSnapshot});

  final ContextSnapshot? initialSnapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initialSnapshot == null && !ref.watch(environmentConsentProvider)) {
      return V2PageStage(
        child: V2EmptyObject(
          icon: CupertinoIcons.location,
          title: '从此刻的位置开始',
          detail: '位置只用来理解附近天气与光线，不会形成服务端轨迹。',
          action: '允许位置并继续',
          onAction: () => ref.read(environmentConsentProvider.notifier).grant(),
        ),
      );
    }

    final snapshot = initialSnapshot == null
        ? ref.watch(environmentSnapshotProvider)
        : AsyncData(initialSnapshot!);
    return V2PageStage(
      backgroundColor: Colors.transparent,
      child: snapshot.when(
        loading: () => const V2LoadingObject(label: '正在理解此刻的光'),
        error: (error, _) => _V2TodayError(
          onRetry: initialSnapshot == null
              ? () => ref.read(environmentSnapshotProvider.notifier).refresh()
              : null,
          onSettings: Geolocator.openAppSettings,
          onManualLocation: () => _openManualLocation(context),
        ),
        data: (value) {
          return _V2TodayContent(
            snapshot: value,
            composition: ref.watch(todaySurfaceCompositionProvider(value)),
            location: _V2TodayContent._todayLocationDisplay(
              ref
                      .watch(
                        environmentLocationDisplayForSnapshotProvider(value),
                      )
                      .asData
                      ?.value ??
                  ref.read(environmentLocationDisplayProvider),
            ),
            onRefresh: initialSnapshot == null
                ? () => ref.read(environmentSnapshotProvider.notifier).refresh()
                : null,
          );
        },
      ),
    );
  }

  static Future<void> _openManualLocation(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const ManualLocationSheet(),
      );
}

class _V2TodayContent extends StatefulWidget {
  const _V2TodayContent({
    required this.snapshot,
    required this.composition,
    required this.location,
    required this.onRefresh,
  });

  final ContextSnapshot snapshot;
  final SurfaceComposition composition;
  final EnvironmentLocationDisplay location;
  final Future<void> Function()? onRefresh;

  static EnvironmentLocationDisplay _todayLocationDisplay(
    EnvironmentLocationDisplay value,
  ) => value.description == '当前位置'
      ? EnvironmentLocationDisplay(label: '附近', source: value.source)
      : value;

  @override
  State<_V2TodayContent> createState() => _V2TodayContentState();
}

class _V2TodayContentState extends State<_V2TodayContent> {
  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final composition = widget.composition;
    final location = widget.location;
    final now = composition.generatedAt;
    final safety = composition[CompositionSlot.blockingSafety];
    final primary = composition[CompositionSlot.primary]!;
    final quiet =
        primary.presentation.variant == EntryPresentationVariant.quiet;
    final date = '${now.month}月${now.day}日 · ${_phaseLabel(snapshot.dayPhase)}';
    final sessionId = primary.payload is OpportunityEntryPayload
        ? (primary.payload as OpportunityEntryPayload).sessionId
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 670;
        return RefreshIndicator(
          color: V2Palette.moss,
          backgroundColor: V2Palette.paper,
          edgeOffset: 8,
          onRefresh: widget.onRefresh ?? () async {},
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  V2TopLine(
                    primary: location.description,
                    secondary: date,
                    trailing: safety == null
                        ? null
                        : _V2SafetyAlertButton(
                            entry: safety,
                            onTap: () =>
                                EntryActionDispatcher.dispatch(context, safety),
                          ),
                  ),
                  SizedBox(height: compact ? 20 : 30),
                  Text(
                    '栖光此刻看到',
                    style: TextStyle(
                      color: V2Palette.moss.withValues(alpha: .9),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: compact ? 34 : 38,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        key: const Key('v2-today-judgement'),
                        composition.judgement,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: V2Palette.ink,
                          fontSize: compact ? 27 : 32,
                          height: 1.12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.1,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 18 : 26),
                  SizedBox(
                    height: compact ? 250 : 310,
                    child: EntryCardRegistry.build(
                      context,
                      primary,
                      CompositionSlot.primary,
                    ),
                  ),
                  _V2OpportunityRail(
                    sessions: snapshot.shootingSessions,
                    primaryId: sessionId,
                    now: now,
                    onOpen: (session) => context.push(
                      '/session/${Uri.encodeComponent(session.id)}',
                    ),
                  ),
                  SizedBox(height: compact ? 14 : 18),
                  Row(
                    children: [
                      Expanded(
                        child: _V2LightEntry(
                          icon: quiet
                              ? CupertinoIcons.location
                              : CupertinoIcons.compass,
                          label: quiet ? '选择参考地点' : '换个方向看看',
                          onTap: quiet
                              ? () => V2TodayPage._openManualLocation(context)
                              : () => context.go('/explore'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _V2LightEntry(
                          icon: CupertinoIcons.sparkles,
                          label: '抽一张灵感',
                          onTap: () => context.go('/inspiration'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _phaseLabel(DayPhase value) => switch (value) {
    DayPhase.dawn => '晨光',
    DayPhase.day => '日间',
    DayPhase.sunset => '落日',
    DayPhase.blueHour => '蓝调',
    DayPhase.night => '夜间',
  };
}

class _V2SafetyAlertButton extends StatelessWidget {
  const _V2SafetyAlertButton({required this.entry, required this.onTap});

  final ContextEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '查看当前预警：${entry.presentation.title}',
    child: V2Pressable(
      key: const Key('v2-safety-alert-button'),
      semanticLabel: '查看当前预警：${entry.presentation.title}',
      onTap: onTap,
      compact: true,
      color: V2Palette.dangerSoft,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              color: V2Palette.danger,
              size: 16,
            ),
            SizedBox(width: 6),
            Text(
              '预警',
              style: TextStyle(
                color: V2Palette.danger,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _V2OpportunityRail extends StatelessWidget {
  const _V2OpportunityRail({
    required this.sessions,
    required this.primaryId,
    required this.now,
    required this.onOpen,
  });

  final List<ShootingSession> sessions;
  final String? primaryId;
  final DateTime now;
  final ValueChanged<ShootingSession> onOpen;

  @override
  Widget build(BuildContext context) {
    final moment = now.toUtc();
    final items =
        sessions
            .where(
              (item) =>
                  item.id != primaryId &&
                  !item.isEvidenceExpiredAt(moment) &&
                  item.canStartWatchingAt(moment),
            )
            .toList()
          ..sort((left, right) => left.startsAt.compareTo(right.startsAt));
    if (items.length > 3) items.removeRange(3, items.length);
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        key: const Key('v2-secondary-opportunity-rail'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '接下来还可以看',
            style: TextStyle(
              color: V2Palette.mutedInk,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: .4,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return V2Pressable(
                  key: Key('v2-secondary-session-${item.id}'),
                  onTap: () => onOpen(item),
                  compact: true,
                  color: V2Palette.paper.withValues(alpha: .82),
                  child: SizedBox(
                    width: 216,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: V2Palette.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _phaseNames(item),
                            maxLines: 1,
                            style: const TextStyle(
                              color: V2Palette.mutedInk,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          SizedBox(
                            height: 16,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${_sessionTime(item, now)} · ${_condition(item.conditionBand)}',
                                key: Key(
                                  'v2-secondary-session-time-${item.id}',
                                ),
                                maxLines: 1,
                                softWrap: false,
                                style: const TextStyle(
                                  color: V2Palette.mutedInk,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _sessionTime(ShootingSession session, DateTime now) {
    final start = session.startsAt.toLocal();
    final end = session.endsAt.toLocal();
    final localNow = now.toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final sessionDay = DateTime(start.year, start.month, start.day);
    final dayOffset = sessionDay.difference(today).inDays;
    final prefix = switch (dayOffset) {
      0 => '',
      1 => '明天 ',
      _ => '${start.month}月${start.day}日 ',
    };
    String f(DateTime value) =>
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return '$prefix${f(start)}—${f(end)}';
  }

  static String _condition(ShootingConditionBand value) => switch (value) {
    ShootingConditionBand.good => '条件较好',
    ShootingConditionBand.fair => '值得观察',
    ShootingConditionBand.limited => '条件有限',
  };

  static String _phaseNames(ShootingSession session) => session.phases.isEmpty
      ? '拍摄窗口'
      : session.phases.take(2).map(_phaseLabel).join(' · ');

  static String _phaseLabel(ShootingSessionPhase phase) => switch (phase.kind) {
    ShootingPhaseKind.morningBlueHour => '晨间蓝调',
    ShootingPhaseKind.sunrise => '日出',
    ShootingPhaseKind.morningMist => '晨雾',
    ShootingPhaseKind.reflection => '倒影',
    ShootingPhaseKind.warmLight => '暖光',
    ShootingPhaseKind.sunset => '日落',
    ShootingPhaseKind.blueHour => '蓝调',
    ShootingPhaseKind.artificialLights => '灯光',
    ShootingPhaseKind.rainEnding => '雨停',
    ShootingPhaseKind.wetReflection => '湿地反光',
    ShootingPhaseKind.desertSideLight => '沙地侧光',
    ShootingPhaseKind.texture => '地表纹理',
    ShootingPhaseKind.approach => '抵达',
    ShootingPhaseKind.safeStop => '合法停靠',
    ShootingPhaseKind.shoot => '拍摄',
    ShootingPhaseKind.rejoinRoute => '回到路线',
    ShootingPhaseKind.returnWindow => '返程光线',
    ShootingPhaseKind.sessionEnd => '窗口结束',
  };
}

class _V2LightEntry extends StatelessWidget {
  const _V2LightEntry({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => V2Pressable(
    onTap: onTap,
    compact: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: V2Palette.ink, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: V2Palette.ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _V2TodayError extends StatelessWidget {
  const _V2TodayError({
    required this.onRetry,
    required this.onSettings,
    required this.onManualLocation,
  });

  final VoidCallback? onRetry;
  final VoidCallback onSettings;
  final VoidCallback onManualLocation;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        V2EmptyObject(
          icon: CupertinoIcons.location_slash,
          title: '暂时拿不到此刻位置',
          detail: '可以重试，也可以选择一个地点作为非实时参考。',
          action: onRetry == null ? '打开位置设置' : '重试',
          onAction: onRetry ?? onSettings,
        ),
        const SizedBox(height: 14),
        TextButton(onPressed: onManualLocation, child: const Text('手动选择地点')),
      ],
    ),
  );
}
