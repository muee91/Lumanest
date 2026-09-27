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
import 'package:luma_nest/src/core/photography/field_environment_selector.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/core/photography/target_arrival_state.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/notifications/application/photography_watch_notification_service.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';

part 'widgets/v2_session_summary.dart';
part 'widgets/v2_shooting_timeline.dart';
part 'widgets/v2_field_mode_object.dart';
part 'widgets/v2_plan_b_object.dart';
part 'widgets/v2_shooting_advice.dart';
part 'widgets/v2_opportunity_evidence.dart';

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
    if (_locationRefreshing || widget.activeShootingIntent?.targetId == null) {
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
    final initialTarget = _targetForIntent();
    final now = widget.activeShootingIntent?.targetId == null
        ? DateTime.now()
        : _fieldNow;
    final liveSnapshot = widget.activeShootingIntent?.targetId == null
        ? null
        : ref.watch(environmentSnapshotProvider).asData?.value;
    final freshLiveSnapshot = _freshFieldSnapshot(liveSnapshot, now);
    final fieldSnapshot =
        freshLiveSnapshot ?? _freshFieldSnapshot(widget.snapshot, now);
    final refreshedSession = fieldSnapshot?.shootingSessions
        .where((candidate) => candidate.id == session.id)
        .firstOrNull;
    final executionSession = refreshedSession ?? session;
    final requestedTargetId = widget.activeShootingIntent?.targetId;
    final refreshedTarget = requestedTargetId == null
        ? null
        : refreshedSession?.targetCandidates
              .where((candidate) => candidate.id == requestedTargetId)
              .firstOrNull;
    final target = refreshedTarget ?? initialTarget;
    final liveIdentityMissing =
        freshLiveSnapshot != null &&
        (refreshedSession == null ||
            requestedTargetId != null && refreshedTarget == null);
    final arrivalAssessment = target == null
        ? null
        : TargetArrivalStateResolver.assess(
            reading: _locationReading,
            target: target,
            now: now,
          );
    final distanceMeters = arrivalAssessment?.distanceMeters;
    final automaticArrival =
        !liveIdentityMissing && (arrivalAssessment?.isArrived ?? false);
    final atTarget = _arrivalOverride ?? automaticArrival;
    final decision = liveIdentityMissing
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
    // Plan B is valid only when the current snapshot is fresh. The route
    // detail may still render the selected session from its navigation extra,
    // but an expired snapshot must never promote an old alternative.
    final planB = fieldSnapshot == null
        ? null
        : ShootingSessionFallback.selectPlanB(
            fieldSnapshot.shootingSessions,
            primary: executionSession,
            now: now,
            currentLocation: _locationReading?.point ?? fieldSnapshot.location,
          );
    final selectedPlanBTarget = planB?.target;
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
                      capabilities: executionSession.recommendedCapabilities,
                      target: target,
                    ),
                  ],
                  if (target != null && requestedTargetId != null) ...[
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
                  if (planB != null && selectedPlanBTarget != null) ...[
                    const SizedBox(height: 18),
                    _V2PlanBObject(
                      primary: executionSession,
                      alternative: planB.session,
                      onOpen: () {
                        final intent = ActiveShootingIntent(
                          sessionId: planB.session.id,
                          targetId: selectedPlanBTarget.id,
                          createdAt: DateTime.now(),
                        );
                        context.push(
                          Uri(
                            path:
                                '/session/${Uri.encodeComponent(planB.session.id)}',
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
                if (watched || executionSession.canStartWatchingAt(now)) ...[
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
                    onTap: decision.state == ShootingExecutionState.observe
                        ? () => setState(() => _evidenceOpen = !_evidenceOpen)
                        : () => _primaryAction(decision, target),
                    color: V2Palette.moss,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        decision.state == ShootingExecutionState.observe
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

  Future<void> _toggleWatch(String? watchedId, ShootingSession session) async {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已取消守候提醒')));
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

  ShootingTarget? _targetForIntent() {
    final targetId = widget.activeShootingIntent?.targetId;
    return ShootingTargetSelector.selectForSession(
      widget.session,
      requestedId: targetId,
    );
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
    // Field Mode surfaces only factors already attached to the session. The
    // selector owns the deterministic priority; [snapshot] is kept in the
    // signature so callers can continue passing the evidence timestamp.
    return FieldEnvironmentSelector.select(session)
        .map((factor) => _V2FieldFact(label: factor.label, value: factor.value))
        .toList(growable: false);
  }

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
