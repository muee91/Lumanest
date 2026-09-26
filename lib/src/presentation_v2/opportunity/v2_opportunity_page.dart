import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/photography/active_shooting_intent.dart';
import 'package:luma_nest/src/core/photography/equipment_capability.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/core/photography/target_arrival_state.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/notifications/application/photography_watch_notification_service.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';

class V2OpportunityPage extends ConsumerWidget {
  const V2OpportunityPage({
    super.key,
    required this.sessionId,
    this.activeShootingIntent,
    this.initialSnapshot,
  });

  final String sessionId;
  final ActiveShootingIntent? activeShootingIntent;
  final ContextSnapshot? initialSnapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = initialSnapshot == null
        ? ref.watch(environmentSnapshotProvider)
        : AsyncData(initialSnapshot!);
    return Scaffold(
      backgroundColor: V2Palette.canvas,
      body: snapshot.when(
        loading: () => const V2LoadingObject(label: '正在展开同一个机会'),
        error: (_, _) => V2PageStage(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: V2EmptyObject(
            icon: CupertinoIcons.exclamationmark_triangle,
            title: '机会依据暂时不可用',
            detail: '不要依据旧内容出发，刷新环境后再看。',
            action: '返回',
            onAction: () => context.pop(),
          ),
        ),
        data: (value) {
          final session = ShootingSessionSelector.select(
            value.shootingSessions,
            now: DateTime.now(),
            requestedId: sessionId,
          );
          if (session == null) {
            return V2PageStage(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
              child: V2EmptyObject(
                icon: CupertinoIcons.clock,
                title: '这个机会已经结束',
                detail: '回到今日查看仍然成立的窗口。',
                action: '回到今日',
                onAction: () => context.go('/today'),
              ),
            );
          }
          if (session.id != sessionId) {
            return V2PageStage(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
              child: V2EmptyObject(
                icon: CupertinoIcons.search,
                title: '没有找到该机会',
                detail: '回到今日查看当前可用的窗口。',
                action: '回到今日',
                onAction: () => context.go('/today'),
              ),
            );
          }
          return _V2OpportunityStage(
            snapshot: value,
            session: session,
            activeShootingIntent: activeShootingIntent,
          );
        },
      ),
    );
  }
}

class _V2OpportunityStage extends ConsumerStatefulWidget {
  const _V2OpportunityStage({
    required this.snapshot,
    required this.session,
    this.activeShootingIntent,
  });
  final ContextSnapshot snapshot;
  final ShootingSession session;
  final ActiveShootingIntent? activeShootingIntent;

  @override
  ConsumerState<_V2OpportunityStage> createState() =>
      _V2OpportunityStageState();
}

class _V2OpportunityStageState extends ConsumerState<_V2OpportunityStage> {
  bool _evidenceOpen = false;
  bool? _arrivalOverride;
  bool _locationRefreshing = false;
  int _selectedPhaseIndex = 0;
  DateTime _fieldNow = DateTime.now();
  LocationReading? _locationReading;
  Timer? _fieldClock;
  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    if (widget.activeShootingIntent?.targetId == null) return;
    unawaited(_refreshFieldLocation());
    _locationTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) unawaited(_refreshFieldLocation());
    });
    _fieldClock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        setState(() => _fieldNow = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _fieldClock?.cancel();
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshFieldLocation() async {
    if (_locationRefreshing ||
        widget.activeShootingIntent?.targetId == null) {
      return;
    }
    _locationRefreshing = true;
    try {
      // Field arrival must use a real foreground device fix. Manual/base-region
      // fallbacks are valid for environment lookup but must never auto-confirm
      // physical arrival at a reviewed shooting target.
      final reading = await ref.read(locationRepositoryProvider).current();
      if (!mounted) return;
      setState(() {
        _locationReading = reading;
        _fieldNow = DateTime.now();
      });
    } on Object {
      // Keep the last reading; the pure resolver expires it after two minutes.
      // The periodic foreground poll retries transient location failures.
    } finally {
      _locationRefreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final target = _targetForIntent();
    final now = widget.activeShootingIntent?.targetId == null
        ? DateTime.now()
        : _fieldNow;
    final liveSnapshot = widget.activeShootingIntent?.targetId == null
        ? null
        : ref.watch(environmentSnapshotProvider).asData?.value;
    final freshLiveSnapshot = _freshFieldSnapshot(liveSnapshot, now);
    final fieldSnapshot = freshLiveSnapshot ??
        _freshFieldSnapshot(widget.snapshot, now);
    final arrivalAssessment = target == null
        ? null
        : TargetArrivalStateResolver.assess(
            reading: _locationReading,
            target: target,
            now: now,
          );
    final distanceMeters = arrivalAssessment?.distanceMeters;
    final automaticArrival = arrivalAssessment?.isArrived ?? false;
    final atTarget = _arrivalOverride ?? automaticArrival;
    final refreshedSession = fieldSnapshot?.shootingSessions
        .where((candidate) => candidate.id == session.id)
        .firstOrNull;
    final liveSessionMissing =
        freshLiveSnapshot != null && refreshedSession == null;
    final executionSession = refreshedSession ?? session;
    final decision = liveSessionMissing
        ? const ShootingExecutionDecision(
            state: ShootingExecutionState.observe,
            label: '查看依据',
            reason: '这个机会已不在最新环境判断中，暂不据此行动。',
          )
        : ShootingExecutionResolver.resolve(
            session: executionSession,
            now: now,
            target: target,
            atTarget: atTarget,
          );
    final planB = ShootingSessionFallback.selectPlanB(
      fieldSnapshot?.shootingSessions ?? widget.snapshot.shootingSessions,
      primary: executionSession,
      now: now,
    );
    final planBTarget = planB?.targetCandidates
        .where(
          (candidate) =>
              candidate.arrivalRadiusMeters > 0 &&
              candidate.supportedSessions.contains(planB.kind),
        )
        .firstOrNull;
    final fieldFacts = _fieldFacts(executionSession, fieldSnapshot);
    final intentTargetId = widget.activeShootingIntent?.targetId;
    final library = ref.watch(userLibraryProvider).asData?.value;
    final watchedEntry = library?.watchedSessions
        .where(
          (item) =>
              item.sessionId == session.id &&
              (intentTargetId == null || item.targetId == intentTargetId),
        )
        .firstOrNull;
    final watched = watchedEntry != null;
    final hasResult =
        library?.sessionResults.any(
          (item) =>
              item.sessionId == session.id &&
              (intentTargetId == null || item.targetId == intentTargetId),
        ) ==
        true;
    final selectedPhase = executionSession.phases.isEmpty
        ? null
        : executionSession.phases[_selectedPhaseIndex.clamp(
            0,
            executionSession.phases.length - 1,
          )];

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
            child: Row(
              children: [
                V2BackButton(onTap: () => context.pop()),
                const Spacer(),
                Text(
                  _condition(executionSession.conditionBand),
                  style: const TextStyle(
                    color: V2Palette.moss,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 130),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _V2SessionSummary(
                    stableId: session.id,
                    eyebrow: _eyebrow(executionSession.kind),
                    title: executionSession.title,
                    detail: decision.reason,
                    timeLabel:
                        '${_time(executionSession.presentationStartsAt)}—'
                        '${_time(executionSession.presentationEndsAt)}',
                    accent: _accent(executionSession.conditionBand),
                  ),
                  const SizedBox(height: 20),
                  if (selectedPhase != null) ...[
                    _V2Timeline(
                      phases: executionSession.phases,
                      selectedIndex: _selectedPhaseIndex,
                      onSelected: (index) =>
                          setState(() => _selectedPhaseIndex = index),
                    ),
                    const SizedBox(height: 18),
                    _V2ShootingAdvice(
                      phase: selectedPhase,
                      capabilities: session.recommendedCapabilities,
                      target: target,
                    ),
                  ],
                  if (target != null) ...[
                    const SizedBox(height: 18),
                    _V2FieldModeObject(
                      atTarget: atTarget,
                      automaticArrival: automaticArrival,
                      distanceMeters: distanceMeters,
                      decision: decision,
                      target: target,
                      facts: fieldFacts,
                      dataObservedAt: fieldSnapshot?.observedAt,
                      directionDegrees:
                          decision.phase?.directionDegrees ??
                          target.viewBearingDegrees,
                      onToggle: () =>
                          setState(() => _arrivalOverride = !atTarget),
                    ),
                  ],
                  if (planB != null && planBTarget != null) ...[
                    const SizedBox(height: 18),
                    _V2PlanBObject(
                      primary: executionSession,
                      alternative: planB,
                      onOpen: () {
                        final intent = ActiveShootingIntent(
                          sessionId: planB.id,
                          targetId: planBTarget.id,
                          createdAt: DateTime.now(),
                        );
                        context.push(
                          Uri(
                            path: '/session/${Uri.encodeComponent(planB.id)}',
                            queryParameters: intent.queryParameters,
                          ).toString(),
                          extra: fieldSnapshot ?? widget.snapshot,
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (decision.state != ShootingExecutionState.observe) ...[
                    _V2EvidenceToggle(
                      open: _evidenceOpen,
                      onTap: () =>
                          setState(() => _evidenceOpen = !_evidenceOpen),
                    ),
                    const SizedBox(height: 14),
                  ],
                  AnimatedSize(
                    duration: const Duration(milliseconds: 360),
                    curve: Curves.easeOutCubic,
                    child: _evidenceOpen
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '判断依据',
                                style: TextStyle(
                                  color: V2Palette.ink,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final factor
                                      in executionSession.factors.take(6))
                                    _V2FactorObject(factor: factor),
                                ],
                              ),
                              if (target != null) ...[
                                const SizedBox(height: 18),
                                _V2TargetObject(target: target),
                              ],
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Row(
              children: [
                if (watched ||
                    executionSession.canStartWatchingAt(now)) ...[
                  V2Pressable(
                    key: const Key('v2-watch-session-action'),
                    onTap: () =>
                        _toggleWatch(watchedEntry?.id, executionSession),
                    compact: true,
                    color: watched ? V2Palette.mossSoft : V2Palette.paper,
                    semanticLabel: watched ? '取消守候提醒' : '开启守候提醒',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 15,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            watched
                                ? CupertinoIcons.bell_fill
                                : CupertinoIcons.bell,
                            color: watched ? V2Palette.moss : V2Palette.ink,
                            size: 18,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            watched ? '已守候' : '守候提醒',
                            style: const TextStyle(
                              color: V2Palette.ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: V2Pressable(
                    onTap:
                        hasResult ||
                            decision.state == ShootingExecutionState.ended
                        ? _recordResult
                        : decision.state == ShootingExecutionState.observe
                        ? () => setState(() => _evidenceOpen = !_evidenceOpen)
                        : () => _primaryAction(decision, target),
                    color: V2Palette.moss,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        hasResult
                            ? '再次记录结果'
                            : decision.state == ShootingExecutionState.ended
                            ? '记录结果'
                            : decision.state == ShootingExecutionState.observe
                            ? _evidenceOpen
                                  ? '收起依据'
                                  : '查看依据'
                            : decision.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleWatch(
    String? watchedId,
    ShootingSession session,
  ) async {
    if (watchedId == null) {
      // Permission is requested at the moment the user asks to be reminded, not
      // at launch. A denial still keeps the watch itself, so the failure mode is
      // a missing reminder rather than a lost bookmark.
      final remindersEnabled = await ref
          .read(shootingSessionNotificationsEnabledProvider.notifier)
          .setEnabled(true);
      await ref
          .read(userLibraryProvider.notifier)
          .watchSession(
            session: session,
            snapshotId: widget.snapshot.id,
            targetId: _targetForIntent()?.id,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            remindersEnabled
                ? '已开启守候提醒'
                : '通知权限未开启，窗口到达时不会提醒。可在「我的 — 隐私与感受」重新开启。',
          ),
        ),
      );
    } else {
      await ref.read(userLibraryProvider.notifier).unwatchSession(watchedId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已取消守候提醒')),
      );
    }
  }

  void _primaryAction(
    ShootingExecutionDecision decision,
    ShootingTarget? target,
  ) {
    if (decision.state == ShootingExecutionState.shootNow ||
        decision.state == ShootingExecutionState.waitAtTarget) {
      setState(() => _evidenceOpen = true);
      return;
    }
    if (target != null &&
        (decision.state == ShootingExecutionState.planRoute ||
            decision.state == ShootingExecutionState.departNow ||
            decision.state == ShootingExecutionState.waitToDepart)) {
      final intent = ActiveShootingIntent(
        sessionId: widget.session.id,
        targetId: target.id,
        createdAt: DateTime.now(),
      );
      final queryParameters = <String, String>{
        'name': target.name,
        'lat': target.coordinate.latitude.toString(),
        'lon': target.coordinate.longitude.toString(),
        'system': target.coordinate.coordinateSystem.name,
        'mode': target.accessModes.contains(ShootingTravelMode.walking)
            ? 'walking'
            : 'driving',
        'session': widget.session.id,
        ...intent.queryParameters,
      };
      context.go(
        Uri(path: '/route', queryParameters: queryParameters).toString(),
      );
      return;
    }
    setState(() => _evidenceOpen = true);
  }

  Future<void> _recordResult() async {
    final outcome = await showModalBottomSheet<ShootingSessionOutcome>(
      context: context,
      backgroundColor: V2Palette.canvas,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '这次发生了什么？',
              style: TextStyle(
                color: V2Palette.ink,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            for (final value in ShootingSessionOutcome.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: V2Pressable(
                  onTap: () => Navigator.of(context).pop(value),
                  compact: true,
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Text(
                      _outcome(value),
                      style: const TextStyle(
                        color: V2Palette.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (outcome == null) return;
    await ref
        .read(userLibraryProvider.notifier)
        .recordShootingSessionResult(
          session: widget.session,
          snapshotId: widget.snapshot.id,
          outcome: outcome,
          targetId: _targetForIntent()?.id,
        );
  }

  ShootingTarget? _targetForIntent() {
    final targetId = widget.activeShootingIntent?.targetId;
    if (targetId == null) return widget.session.targetCandidates.firstOrNull;
    return widget.session.targetCandidates
        .where((candidate) => candidate.id == targetId)
        .firstOrNull;
  }

  static ContextSnapshot? _freshFieldSnapshot(
    ContextSnapshot? snapshot,
    DateTime now,
  ) {
    if (snapshot == null ||
        snapshot.isStale ||
        !snapshot.expiresAt.toUtc().isAfter(now.toUtc())) {
      return null;
    }
    return snapshot;
  }

  static List<_V2FieldFact> _fieldFacts(
    ShootingSession session,
    ContextSnapshot? snapshot,
  ) {
    if (snapshot == null) return const [];
    final preferred = switch (session.kind) {
      ShootingSessionKind.waterMorning ||
      ShootingSessionKind.waterEvening => const [
        'wind',
        'precipitation',
        'cloud',
      ],
      ShootingSessionKind.mountainMorning ||
      ShootingSessionKind.mountainEvening => const [
        'visibility',
        'cloud',
        'wind',
      ],
      ShootingSessionKind.cityAfterRain => const [
        'precipitation',
        'cloud',
        'visibility',
      ],
      ShootingSessionKind.desertSideLight => const [
        'visibility',
        'wind',
        'cloud',
      ],
      ShootingSessionKind.generalMorning ||
      ShootingSessionKind.generalEvening ||
      ShootingSessionKind.cityBlueHour => const [
        'cloud',
        'visibility',
        'wind',
      ],
      ShootingSessionKind.routeLightWindow => const [
        'cloud',
        'wind',
        'precipitation',
      ],
    };
    final facts = <_V2FieldFact>[];
    for (final id in preferred) {
      final fact = switch (id) {
        'cloud' when snapshot.cloudCoverPercent != null => _V2FieldFact(
            label: '云量',
            value: '${snapshot.cloudCoverPercent!.round()}%',
          ),
        'wind' when snapshot.windSpeedMetersPerSecond != null => _V2FieldFact(
            label: '风速',
            value:
                '${snapshot.windSpeedMetersPerSecond!.toStringAsFixed(1)}m/s',
          ),
        'precipitation'
            when snapshot.precipitationMillimeters != null => _V2FieldFact(
            label: '降水',
            value:
                '${snapshot.precipitationMillimeters!.toStringAsFixed(1)}mm',
          ),
        'visibility' when snapshot.visibilityKilometers != null => _V2FieldFact(
            label: '能见度',
            value: '${snapshot.visibilityKilometers!.round()}km',
          ),
        _ => null,
      };
      if (fact != null) facts.add(fact);
    }
    if (facts.length < 3) {
      for (final factor in session.factors) {
        if (facts.any((fact) => fact.label == factor.label)) continue;
        facts.add(_V2FieldFact(label: factor.label, value: factor.value));
        if (facts.length == 3) break;
      }
    }
    return List.unmodifiable(facts.take(3));
  }

  static String _outcome(ShootingSessionOutcome value) => switch (value) {
    ShootingSessionOutcome.captured => '拍到了',
    ShootingSessionOutcome.conditionsDidNotAppear => '条件没有出现',
    ShootingSessionOutcome.arrivedLate => '到晚了',
    ShootingSessionOutcome.didNotGo => '没有去',
  };

  static String _eyebrow(ShootingSessionKind kind) => switch (kind) {
    ShootingSessionKind.generalMorning => '晨间光线',
    ShootingSessionKind.generalEvening => '晚间光线',
    ShootingSessionKind.waterMorning => '水岸晨光',
    ShootingSessionKind.waterEvening => '水岸晚光',
    ShootingSessionKind.mountainMorning => '山地晨光',
    ShootingSessionKind.mountainEvening => '山地晚光',
    ShootingSessionKind.cityBlueHour => '城市蓝调',
    ShootingSessionKind.cityAfterRain => '城市雨后',
    ShootingSessionKind.desertSideLight => '荒漠侧光',
    ShootingSessionKind.routeLightWindow => '沿途光窗',
  };

  static String _condition(ShootingConditionBand value) => switch (value) {
    ShootingConditionBand.good => '条件较好',
    ShootingConditionBand.fair => '条件一般',
    ShootingConditionBand.limited => '条件有限',
  };

  static Color _accent(ShootingConditionBand value) => switch (value) {
    ShootingConditionBand.good => V2Palette.moss,
    ShootingConditionBand.fair => V2Palette.ember,
    ShootingConditionBand.limited => V2Palette.mutedInk,
  };

  static String _time(DateTime value) =>
      '${value.toLocal().hour.toString().padLeft(2, '0')}:'
      '${value.toLocal().minute.toString().padLeft(2, '0')}';
}

class _V2SessionSummary extends StatelessWidget {
  const _V2SessionSummary({
    required this.stableId,
    required this.eyebrow,
    required this.title,
    required this.detail,
    required this.timeLabel,
    required this.accent,
  });

  final String stableId;
  final String eyebrow;
  final String title;
  final String detail;
  final String timeLabel;
  final Color accent;

  @override
  Widget build(BuildContext context) => Hero(
    tag: 'v2-opportunity:$stableId',
    transitionOnUserGestures: true,
    child: Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        decoration: BoxDecoration(
          color: V2Palette.paper,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: V2Palette.line.withValues(alpha: .72)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 5,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  eyebrow,
                  style: const TextStyle(
                    color: V2Palette.mutedInk,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: V2Palette.ink,
                fontSize: 30,
                height: 1.08,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              detail,
              style: const TextStyle(
                color: V2Palette.mutedInk,
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(CupertinoIcons.clock, color: accent, size: 18),
                const SizedBox(width: 8),
                Text(
                  timeLabel,
                  style: const TextStyle(
                    color: V2Palette.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _V2Timeline extends StatelessWidget {
  const _V2Timeline({
    required this.phases,
    required this.selectedIndex,
    required this.onSelected,
  });
  final List<ShootingSessionPhase> phases;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '拍摄时间轴',
        style: TextStyle(
          color: V2Palette.ink,
          fontSize: 19,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 98,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final minimumWidth = phases.length * 88.0;
            final contentWidth = minimumWidth > constraints.maxWidth
                ? minimumWidth
                : constraints.maxWidth;
            final lineInset = contentWidth / phases.length / 2;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth,
                height: 98,
                child: Stack(
                  children: [
                    Positioned(
                      left: lineInset,
                      right: lineInset,
                      top: 11,
                      child: Container(height: 2, color: V2Palette.line),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var index = 0; index < phases.length; index++)
                          Expanded(
                            child: _V2PhaseNode(
                              key: Key('v2-phase-node-$index'),
                              phase: phases[index],
                              selected: index == selectedIndex,
                              onTap: () => onSelected(index),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

class _V2PhaseNode extends StatelessWidget {
  const _V2PhaseNode({
    super.key,
    required this.phase,
    required this.selected,
    required this.onTap,
  });
  final ShootingSessionPhase phase;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${label(phase.kind)}，${_time(phase.startsAt)}',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: selected ? 24 : 20,
            height: selected ? 24 : 20,
            decoration: BoxDecoration(
              color: _color(phase.conditionBand),
              shape: BoxShape.circle,
              border: Border.all(color: V2Palette.canvas, width: 3),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x24000000),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label(phase.kind),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: V2Palette.ink,
              fontSize: 11,
              height: 1.2,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _time(phase.startsAt),
            style: const TextStyle(color: V2Palette.mutedInk, fontSize: 10),
          ),
        ],
      ),
    ),
  );

  static Color _color(ShootingConditionBand value) => switch (value) {
    ShootingConditionBand.good => V2Palette.moss,
    ShootingConditionBand.fair => V2Palette.ember,
    ShootingConditionBand.limited => V2Palette.line,
  };

  static String _time(DateTime value) =>
      '${value.toLocal().hour.toString().padLeft(2, '0')}:'
      '${value.toLocal().minute.toString().padLeft(2, '0')}';

  static String label(ShootingPhaseKind value) => switch (value) {
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
    ShootingPhaseKind.desertSideLight => '侧光',
    ShootingPhaseKind.texture => '纹理',
    ShootingPhaseKind.approach => '接近',
    ShootingPhaseKind.safeStop => '安全停车',
    ShootingPhaseKind.shoot => '拍摄',
    ShootingPhaseKind.rejoinRoute => '返回路线',
    ShootingPhaseKind.returnWindow => '返程窗口',
    ShootingPhaseKind.sessionEnd => '结束',
  };
}

class _V2FieldFact {
  const _V2FieldFact({required this.label, required this.value});

  final String label;
  final String value;
}

class _V2FieldModeObject extends StatefulWidget {
  const _V2FieldModeObject({
    required this.atTarget,
    required this.automaticArrival,
    required this.distanceMeters,
    required this.decision,
    required this.target,
    required this.facts,
    required this.dataObservedAt,
    required this.directionDegrees,
    required this.onToggle,
  });

  final bool atTarget;
  final bool automaticArrival;
  final double? distanceMeters;
  final ShootingExecutionDecision decision;
  final ShootingTarget target;
  final List<_V2FieldFact> facts;
  final DateTime? dataObservedAt;
  final double directionDegrees;
  final VoidCallback onToggle;

  @override
  State<_V2FieldModeObject> createState() => _V2FieldModeObjectState();
}

class _V2FieldModeObjectState extends State<_V2FieldModeObject> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _V2FieldModeObject oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.atTarget != widget.atTarget ||
        oldWidget.decision.phase != widget.decision.phase ||
        oldWidget.decision.state != widget.decision.state) {
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    _ticker?.cancel();
    if (!widget.atTarget || widget.decision.phase == null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final countdown = _countdownLabel();
    final distance = widget.distanceMeters == null
        ? null
        : widget.distanceMeters! < 1000
        ? '${widget.distanceMeters!.round()}m'
        : '${(widget.distanceMeters! / 1000).toStringAsFixed(1)}km';
    return V2Pressable(
      key: const Key('v2-arrived-at-target'),
      onTap: widget.onToggle,
      color: widget.atTarget ? V2Palette.mossSoft : V2Palette.paper,
      semanticLabel: widget.atTarget ? '已到达机位，关闭现场模式' : '已到达机位，进入现场模式',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  widget.atTarget
                      ? CupertinoIcons.location_fill
                      : CupertinoIcons.location,
                  color: widget.atTarget
                      ? V2Palette.moss
                      : V2Palette.mutedInk,
                  size: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.atTarget
                            ? '现场模式 · ${widget.decision.label}'
                            : '到达机位后再判断',
                        style: const TextStyle(
                          color: V2Palette.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.atTarget
                            ? '${widget.target.name} · 朝 ${widget.directionDegrees.round()}° 观察'
                            : distance == null
                            ? '由你确认已经抵达 ${widget.target.name}'
                            : '距 ${widget.target.name} $distance · 到达后进入现场模式',
                        style: const TextStyle(
                          color: V2Palette.mutedInk,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  widget.atTarget
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.circle,
                  color: widget.atTarget
                      ? V2Palette.moss
                      : V2Palette.mutedInk,
                ),
              ],
            ),
            if (widget.atTarget && countdown != null) ...[
              const SizedBox(height: 13),
              Text(
                countdown,
                style: const TextStyle(
                  color: V2Palette.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.5,
                ),
              ),
            ],
            if (widget.atTarget && widget.facts.isNotEmpty) ...[
              const SizedBox(height: 13),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final fact in widget.facts)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: V2Palette.paper,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: V2Palette.line),
                      ),
                      child: Text(
                        '${fact.label} ${fact.value}',
                        style: const TextStyle(
                          color: V2Palette.ink,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (widget.atTarget) ...[
              const SizedBox(height: 10),
              Text(
                <String>[
                  widget.automaticArrival ? '已按实时位置识别到达' : '由你手动确认到达',
                  if (widget.dataObservedAt != null)
                    '环境 ${_time(widget.dataObservedAt!)} 更新',
                ].join(' · '),
                style: const TextStyle(
                  color: V2Palette.mutedInk,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? _countdownLabel() {
    final phase = widget.decision.phase;
    if (phase == null) return null;
    final now = DateTime.now();
    final target = widget.decision.state == ShootingExecutionState.shootNow
        ? phase.endsAt
        : phase.startsAt;
    final remaining = target.difference(now);
    if (remaining <= Duration.zero) return null;
    final prefix = widget.decision.state == ShootingExecutionState.shootNow
        ? '${_V2PhaseNode.label(phase.kind)}还剩'
        : '距${_V2PhaseNode.label(phase.kind)}';
    return '$prefix ${_duration(remaining)}';
  }

  static String _duration(Duration value) {
    final seconds = value.inSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainder = seconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${remainder.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${remainder.toString().padLeft(2, '0')}';
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _V2PlanBObject extends StatelessWidget {
  const _V2PlanBObject({
    required this.primary,
    required this.alternative,
    required this.onOpen,
  });

  final ShootingSession primary;
  final ShootingSession alternative;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => V2Pressable(
    key: const Key('v2-opportunity-plan-b'),
    onTap: onOpen,
    color: V2Palette.paper,
    semanticLabel: '查看备选拍摄机会 ${alternative.title}',
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.arrow_right,
            color: V2Palette.ember,
            size: 20,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '条件变化 · 有备选',
                  style: TextStyle(
                    color: V2Palette.ember,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alternative.title,
                  style: const TextStyle(
                    color: V2Palette.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${primary.title}正在减弱；这个窗口仍有已成立依据。',
                  style: const TextStyle(
                    color: V2Palette.mutedInk,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            CupertinoIcons.chevron_right,
            color: V2Palette.mutedInk,
            size: 17,
          ),
        ],
      ),
    ),
  );
}

class _V2ShootingAdvice extends StatelessWidget {
  const _V2ShootingAdvice({
    required this.phase,
    required this.capabilities,
    required this.target,
  });

  final ShootingSessionPhase phase;
  final Set<EquipmentCapability> capabilities;
  final ShootingTarget? target;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '拍摄建议',
        style: TextStyle(
          color: V2Palette.ink,
          fontSize: 19,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: V2Palette.paper,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: V2Palette.line),
        ),
        child: Column(
          children: [
            _V2AdviceRow(
              label: '重点阶段',
              value:
                  '${_V2PhaseNode.label(phase.kind)} · ${_time(phase.startsAt)}—${_time(phase.endsAt)}',
            ),
            const SizedBox(height: 12),
            _V2AdviceRow(
              label: '观察方向',
              value: '${phase.directionDegrees.round()}°',
            ),
            if (target != null) ...[
              const SizedBox(height: 12),
              _V2AdviceRow(label: '审核机位', value: target!.name),
            ],
            if (capabilities.isNotEmpty) ...[
              const SizedBox(height: 12),
              _V2AdviceRow(
                label: '可用器材',
                value: capabilities.map(_capabilityLabel).join('、'),
              ),
            ],
          ],
        ),
      ),
    ],
  );

  static String _time(DateTime value) =>
      '${value.toLocal().hour.toString().padLeft(2, '0')}:'
      '${value.toLocal().minute.toString().padLeft(2, '0')}';

  static String _capabilityLabel(EquipmentCapability value) => switch (value) {
    EquipmentCapability.camera => '相机',
    EquipmentCapability.phoneCamera => '手机',
    EquipmentCapability.tripod => '三脚架',
    EquipmentCapability.wideAngle => '广角',
    EquipmentCapability.telephoto => '长焦',
    EquipmentCapability.fastLens => '大光圈',
    EquipmentCapability.filter => '滤镜',
    EquipmentCapability.drone => '无人机',
    EquipmentCapability.weatherProtection => '防雨',
    EquipmentCapability.headlamp => '照明',
  };
}

class _V2AdviceRow extends StatelessWidget {
  const _V2AdviceRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 72,
        child: Text(
          label,
          style: const TextStyle(
            color: V2Palette.mutedInk,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: V2Palette.ink,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}

class _V2EvidenceToggle extends StatelessWidget {
  const _V2EvidenceToggle({required this.open, required this.onTap});
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => V2Pressable(
    key: const Key('v2-evidence-toggle'),
    onTap: onTap,
    compact: true,
    color: V2Palette.paper,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.checkmark_shield,
            color: V2Palette.moss,
            size: 18,
          ),
          const SizedBox(width: 9),
          Text(
            open ? '收起判断依据' : '查看判断依据',
            style: const TextStyle(
              color: V2Palette.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Icon(
            open ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
            color: V2Palette.mutedInk,
            size: 16,
          ),
        ],
      ),
    ),
  );
}

class _V2FactorObject extends StatelessWidget {
  const _V2FactorObject({required this.factor});
  final ShootingSessionFactor factor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color: switch (factor.effect) {
        ShootingFactorEffect.supporting => V2Palette.mossSoft,
        ShootingFactorEffect.neutral => V2Palette.paper,
        ShootingFactorEffect.limiting => V2Palette.emberSoft,
      },
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: V2Palette.line),
    ),
    child: Text(
      '${factor.label} ${factor.value}',
      style: const TextStyle(
        color: V2Palette.ink,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _V2TargetObject extends StatelessWidget {
  const _V2TargetObject({required this.target});
  final ShootingTarget? target;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: target == null ? V2Palette.canvas : V2Palette.skySoft,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: V2Palette.line),
    ),
    child: Row(
      children: [
        Icon(
          target == null ? CupertinoIcons.location_slash : CupertinoIcons.scope,
          color: target == null ? V2Palette.mutedInk : V2Palette.sky,
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                target?.name ?? '暂无经过审核的推荐机位',
                style: const TextStyle(
                  color: V2Palette.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                target == null ? '只展示时间与条件，不绑定最近 POI。' : '方向、到场提前量与来源已通过审核。',
                style: const TextStyle(color: V2Palette.mutedInk, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
