import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/manifest/manifest_providers.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative_providers.dart';
import 'package:luma_nest/src/core/photography/next_photography_window.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/location/application/environment_location_display.dart';
import 'package:luma_nest/src/features/location/presentation/manual_location_sheet.dart';
import 'package:luma_nest/src/features/sky_opportunity/application/sky_opportunity_providers.dart';
import 'package:luma_nest/src/features/sky_opportunity/domain/sky_opportunity.dart';
import 'package:luma_nest/src/features/sky_opportunity/presentation/sky_opportunity_detail_page.dart';
import 'package:luma_nest/src/shared/actions/manifest_action_handler.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_opportunity_object.dart';
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
          final evaluatedAt = ref.watch(currentTimeProvider)();
          final point = value.location;
          final daily = point == null
              ? null
              : ref
                    .watch(
                      dailySkyOpportunitiesProvider((
                        latitude: point.latitude,
                        longitude: point.longitude,
                        focus: skyOpportunityFocusForSnapshot(
                          value,
                          evaluatedAt,
                        ),
                      )),
                    )
                    .asData
                    ?.value;
          return _V2TodayContent(
            snapshot: value,
            manifest: ref.watch(personalizedManifestProvider(value)),
            narrative: ref
                .watch(manifestNarrativeProvider(value))
                .asData
                ?.value,
            skyOpportunity: daily?.activeHomeOpportunity(evaluatedAt),
            evaluatedAt: evaluatedAt,
            nextSunrise: _nextSunrise(ref, value, evaluatedAt),
            location: ref.watch(environmentLocationDisplayProvider),
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

  static DateTime? _nextSunrise(
    WidgetRef ref,
    ContextSnapshot snapshot,
    DateTime now,
  ) {
    final current = snapshot.sunrise;
    if (current != null && current.isAfter(now)) return current;
    final point = snapshot.location;
    if (point == null) return current?.add(const Duration(days: 1));
    return ref
        .read(solarServiceProvider)
        .calculate(
          point: point,
          moment: now.add(const Duration(hours: 12)),
          utcOffset: now.timeZoneOffset,
        )
        .sunrise;
  }
}

class _V2TodayContent extends StatelessWidget {
  const _V2TodayContent({
    required this.snapshot,
    required this.manifest,
    required this.narrative,
    required this.skyOpportunity,
    required this.evaluatedAt,
    required this.nextSunrise,
    required this.location,
    required this.onRefresh,
  });

  final ContextSnapshot snapshot;
  final UiManifest manifest;
  final ManifestNarrative? narrative;
  final SkyOpportunityForecast? skyOpportunity;
  final DateTime evaluatedAt;
  final DateTime? nextSunrise;
  final EnvironmentLocationDisplay location;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final now = evaluatedAt;
    final session = ShootingSessionSelector.select(
      snapshot.shootingSessions,
      now: now,
    );
    final safety = manifest.safety.firstOrNull;
    final nextWindow = NextPhotographyWindowResolver.resolve(
      snapshot: snapshot,
      now: now,
      nextSunrise: nextSunrise,
    );
    final quiet =
        safety == null &&
        session == null &&
        skyOpportunity == null &&
        nextWindow == null &&
        manifest.primary == null;
    final judgement = _resolveJudgement(
      safety: safety,
      narrative: narrative,
      skyOpportunity: skyOpportunity,
      session: session,
      nextWindow: nextWindow,
      fallback: manifest.summary,
    );
    final date = '${now.month}月${now.day}日 · ${_phaseLabel(snapshot.dayPhase)}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 670;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            V2TopLine(
              primary: location.description,
              secondary: date,
              action: onRefresh == null ? null : '更新',
              onAction: onRefresh == null
                  ? null
                  : () => unawaited(onRefresh!()),
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
                  judgement,
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
            Expanded(
              child: safety != null
                  ? _V2SafetyObject(
                      item: safety,
                      onTap: () => handleManifestAction(context, safety),
                    )
                  : _opportunity(
                      context,
                      session,
                      skyOpportunity,
                      nextWindow,
                      now,
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
        );
      },
    );
  }

  Widget _opportunity(
    BuildContext context,
    ShootingSession? session,
    SkyOpportunityForecast? skyOpportunity,
    NextPhotographyWindowDecision? nextWindow,
    DateTime now,
  ) {
    if (session != null) {
      final phase = session.primaryPhaseValue;
      return V2OpportunityObject(
        stableId: session.id,
        eyebrow: _sessionEyebrow(session.kind),
        title: _sessionTitle(session),
        detail: _sessionDetail(session),
        timeLabel:
            '${_time(phase.startsAt)}—${_time(phase.endsAt)} · ${_conditionLabel(session.conditionBand)}',
        actionLabel: session.targetCandidates.isEmpty ? '看时间轴' : '进入机会',
        accent: _sessionAccent(session),
        onTap: () =>
            context.push('/session/${Uri.encodeComponent(session.id)}'),
      );
    }
    if (skyOpportunity != null) {
      return V2OpportunityObject(
        stableId: skyOpportunity.id,
        eyebrow: skyOpportunity.dayOffset == 0
            ? '今日${skyOpportunity.eventLabel}'
            : '明日${skyOpportunity.eventLabel}',
        title: _skyTitle(skyOpportunity),
        detail:
            '双模型判断：${skyOpportunity.agreementLabel} · '
            '${skyOpportunity.clarityLabel}',
        timeLabel: skyOpportunity.eventTime == null
            ? '暂无可信时间'
            : '${_skyTime(skyOpportunity.eventTime!)} 前后'
                  '${skyOpportunity.isStale ? ' · 数据更新稍有延迟' : ''}',
        actionLabel: '查看拍摄建议',
        accent: skyOpportunity.confidence == SkyOpportunityConfidence.low
            ? V2Palette.mutedInk
            : V2Palette.ember,
        onTap: () => context.push(skyOpportunityLocation(skyOpportunity)),
      );
    }
    if (nextWindow != null) {
      return V2OpportunityObject(
        stableId: nextWindow.stableId,
        eyebrow: nextWindow.eyebrow,
        title: nextWindow.title,
        detail: nextWindow.detail,
        timeLabel: nextWindow.timeLabel,
        actionLabel: nextWindow.actionLabel,
        accent: nextWindow.kind == NextPhotographyWindowKind.nightSky
            ? V2Palette.night
            : V2Palette.ember,
        onTap: () => context.go(
          nextWindow.action == NextPhotographyWindowAction.exploreNightSky
              ? '/explore?focus=night-sky'
              : '/explore?focus=sunrise',
        ),
      );
    }
    final primary = manifest.primary;
    return V2OpportunityObject(
      stableId: primary?.id ?? snapshot.id,
      eyebrow: primary == null ? '安静观察' : '当前机会',
      title: primary?.title ?? _quietTitle(snapshot),
      detail: primary == null ? _quietDetail(snapshot) : manifest.summary,
      timeLabel: _solarLabel(snapshot, now, nextSunrise),
      actionLabel: primary == null ? '探索附近' : '查看',
      accent: V2Palette.sky,
      onTap: () => primary == null
          ? context.go('/explore')
          : handleManifestAction(context, primary),
    );
  }

  static String _resolveJudgement({
    required ManifestItem? safety,
    required ManifestNarrative? narrative,
    required SkyOpportunityForecast? skyOpportunity,
    required ShootingSession? session,
    required NextPhotographyWindowDecision? nextWindow,
    required String fallback,
  }) {
    if (safety != null) return '先把风险放在所有创作之前。';
    if (session != null) return _sessionJudgement(session);
    if (skyOpportunity != null) {
      return '${skyOpportunity.eventLabel}有机会，${skyOpportunity.primaryReason}。';
    }
    if (nextWindow != null) return nextWindow.judgement;
    final trimmed = narrative?.summary.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
    return fallback;
  }

  static String _sessionJudgement(ShootingSession session) =>
      switch (session.trend) {
        ShootingTrend.improving => '风与云正在把窗口慢慢打开。',
        ShootingTrend.stable => '光线条件稳定，可以围绕主阶段安排。',
        ShootingTrend.weakening => '机会正在收窄，先看时间再决定。',
      };

  static String _skyTitle(SkyOpportunityForecast value) {
    if (value.dayOffset == 0 &&
        value.eventType == SkyOpportunityEventType.sunset) {
      return '今晚可能有晚霞。';
    }
    if (value.dayOffset == 0) return '今日朝霞值得留意。';
    return value.eventType == SkyOpportunityEventType.sunrise
        ? '明日朝霞值得留意。'
        : '明日晚霞值得留意。';
  }

  static String _sessionTitle(ShootingSession session) =>
      switch ((session.conditionBand, session.confidenceBand)) {
        (_, ShootingConfidenceBand.limited) => '这次只适合观察，不建议出发。',
        (ShootingConditionBand.good, _) => '这个窗口值得你提前到场。',
        (ShootingConditionBand.fair, _) => '可以等待，但别急着出发。',
        (ShootingConditionBand.limited, _) => '条件有限，把它当作光线参考。',
      };

  static String _sessionDetail(ShootingSession session) {
    final factors = session.factors
        .take(2)
        .map((item) => '${item.label} ${item.value}');
    final target = session.targetCandidates.firstOrNull;
    return [
      if (target != null) target.name else '暂无验证机位',
      ...factors,
    ].join(' · ');
  }

  static String _sessionEyebrow(ShootingSessionKind kind) => switch (kind) {
    ShootingSessionKind.waterMorning => '水岸晨光',
    ShootingSessionKind.waterEvening => '水岸晚光',
    ShootingSessionKind.mountainMorning => '山地晨光',
    ShootingSessionKind.mountainEvening => '山地晚光',
    ShootingSessionKind.cityBlueHour => '城市蓝调',
    ShootingSessionKind.cityAfterRain => '城市雨后',
    ShootingSessionKind.desertSideLight => '荒漠侧光',
    ShootingSessionKind.routeLightWindow => '沿途光窗',
  };

  static Color _sessionAccent(ShootingSession session) =>
      switch (session.conditionBand) {
        ShootingConditionBand.good => V2Palette.moss,
        ShootingConditionBand.fair => V2Palette.ember,
        ShootingConditionBand.limited => V2Palette.mutedInk,
      };

  static String _conditionLabel(ShootingConditionBand value) => switch (value) {
    ShootingConditionBand.good => '条件较好',
    ShootingConditionBand.fair => '条件一般',
    ShootingConditionBand.limited => '条件有限',
  };

  static String _quietTitle(ContextSnapshot snapshot) =>
      snapshot.isStale ? '判断已经过期，先不要据此行动。' : '现在没有明确窗口，适合慢一点观察。';

  static String _quietDetail(ContextSnapshot snapshot) =>
      snapshot.isStale ? '刷新数据后再做出发判断' : '我会继续看风、云与光线的变化';

  static String _solarLabel(
    ContextSnapshot snapshot,
    DateTime now,
    DateTime? nextSunrise,
  ) {
    final sunset = snapshot.sunset;
    if (sunset != null && sunset.isAfter(now)) return '${_time(sunset)} 日落';
    final sunrise = snapshot.sunrise;
    if (sunrise != null && sunrise.isAfter(now)) {
      return '${_time(sunrise)} 日出';
    }
    if (nextSunrise != null && nextSunrise.isAfter(now)) {
      return '${_time(nextSunrise)} 下次日出';
    }
    return '暂无可信出发时间';
  }

  static String _time(DateTime value) =>
      '${value.toLocal().hour.toString().padLeft(2, '0')}:'
      '${value.toLocal().minute.toString().padLeft(2, '0')}';

  static String _skyTime(DateTime value) {
    final shanghai = value.toUtc().add(const Duration(hours: 8));
    return '${shanghai.hour.toString().padLeft(2, '0')}:'
        '${shanghai.minute.toString().padLeft(2, '0')}';
  }

  static String _phaseLabel(DayPhase value) => switch (value) {
    DayPhase.dawn => '晨光',
    DayPhase.day => '日间',
    DayPhase.sunset => '落日',
    DayPhase.blueHour => '蓝调',
    DayPhase.night => '夜间',
  };
}

class _V2SafetyObject extends StatelessWidget {
  const _V2SafetyObject({required this.item, required this.onTap});
  final ManifestItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => V2Pressable(
    key: const Key('v2-safety-object'),
    onTap: onTap,
    color: V2Palette.dangerSoft,
    child: Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            CupertinoIcons.shield_lefthalf_fill,
            color: V2Palette.danger,
            size: 34,
          ),
          const Spacer(),
          const Text(
            '安全提醒',
            style: TextStyle(
              color: V2Palette.danger,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: V2Palette.ink,
              fontSize: 29,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '查看官方依据与行动建议  →',
            style: TextStyle(
              color: V2Palette.ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
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
