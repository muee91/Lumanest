import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_opportunity_object.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';

class V2OpportunityPage extends ConsumerWidget {
  const V2OpportunityPage({
    super.key,
    required this.sessionId,
    this.initialSnapshot,
  });

  final String sessionId;
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
          return _V2OpportunityStage(snapshot: value, session: session);
        },
      ),
    );
  }
}

class _V2OpportunityStage extends ConsumerStatefulWidget {
  const _V2OpportunityStage({required this.snapshot, required this.session});
  final ContextSnapshot snapshot;
  final ShootingSession session;

  @override
  ConsumerState<_V2OpportunityStage> createState() =>
      _V2OpportunityStageState();
}

class _V2OpportunityStageState extends ConsumerState<_V2OpportunityStage> {
  bool _evidenceOpen = true;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final target = session.targetCandidates.firstOrNull;
    final decision = ShootingExecutionResolver.resolve(
      session: session,
      now: DateTime.now(),
      target: target,
    );
    final library = ref.watch(userLibraryProvider).asData?.value;
    final watched =
        library?.watchedSessions.any((item) => item.sessionId == session.id) ==
        true;
    final hasResult =
        library?.sessionResults.any((item) => item.sessionId == session.id) ==
        true;

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
                  _condition(session.conditionBand),
                  style: const TextStyle(
                    color: V2Palette.moss,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 130),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  V2OpportunityObject(
                    stableId: session.id,
                    eyebrow: _eyebrow(session.kind),
                    title: session.title,
                    detail: decision.reason,
                    timeLabel:
                        '${_time(session.startsAt)}—${_time(session.endsAt)}',
                    actionLabel: decision.label,
                    accent: _accent(session.conditionBand),
                    expanded: true,
                    onTap: () => setState(() => _evidenceOpen = !_evidenceOpen),
                  ),
                  const SizedBox(height: 25),
                  _V2Timeline(phases: session.phases),
                  const SizedBox(height: 24),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 360),
                    curve: Curves.easeOutCubic,
                    child: _evidenceOpen
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '为什么这样判断',
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
                                  for (final factor in session.factors.take(6))
                                    _V2FactorObject(factor: factor),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _V2TargetObject(target: target),
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
                if (session.canStartWatchingAt(DateTime.now()) && !watched) ...[
                  V2RoundAction(
                    icon: CupertinoIcons.bell,
                    label: '开始守候',
                    onTap: _watch,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: V2Pressable(
                    onTap:
                        hasResult ||
                            decision.state == ShootingExecutionState.ended
                        ? _recordResult
                        : () => _primaryAction(decision, target),
                    color: V2Palette.moss,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        hasResult
                            ? '再次记录结果'
                            : decision.state == ShootingExecutionState.ended
                            ? '记录结果'
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

  Future<void> _watch() => ref
      .read(userLibraryProvider.notifier)
      .watchSession(
        session: widget.session,
        snapshotId: widget.snapshot.id,
        targetId: widget.session.targetCandidates.firstOrNull?.id,
      );

  void _primaryAction(
    ShootingExecutionDecision decision,
    ShootingTarget? target,
  ) {
    if (target != null &&
        (decision.state == ShootingExecutionState.planRoute ||
            decision.state == ShootingExecutionState.departNow ||
            decision.state == ShootingExecutionState.waitToDepart)) {
      context.go(
        '/route?name=${Uri.encodeQueryComponent(target.name)}'
        '&lat=${target.coordinate.latitude}'
        '&lon=${target.coordinate.longitude}'
        '&mode=${target.accessModes.contains(ShootingTravelMode.walking) ? 'walking' : 'driving'}',
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
          targetId: widget.session.targetCandidates.firstOrNull?.id,
        );
  }

  static String _outcome(ShootingSessionOutcome value) => switch (value) {
    ShootingSessionOutcome.captured => '拍到了',
    ShootingSessionOutcome.conditionsDidNotAppear => '条件没有出现',
    ShootingSessionOutcome.arrivedLate => '到晚了',
    ShootingSessionOutcome.didNotGo => '没有去',
  };

  static String _eyebrow(ShootingSessionKind kind) => switch (kind) {
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

class _V2Timeline extends StatelessWidget {
  const _V2Timeline({required this.phases});
  final List<ShootingSessionPhase> phases;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '时间在对象内部展开',
        style: TextStyle(
          color: V2Palette.ink,
          fontSize: 19,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 94,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < phases.length; index++) ...[
              Expanded(child: _V2PhaseNode(phase: phases[index])),
              if (index < phases.length - 1)
                Container(
                  width: 14,
                  height: 2,
                  margin: const EdgeInsets.only(top: 9),
                  color: V2Palette.line,
                ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _V2PhaseNode extends StatelessWidget {
  const _V2PhaseNode({required this.phase});
  final ShootingSessionPhase phase;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: _color(phase.conditionBand),
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(height: 9),
      Text(
        _label(phase.kind),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: V2Palette.ink,
          fontSize: 11,
          height: 1.2,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        '${phase.startsAt.toLocal().hour.toString().padLeft(2, '0')}:'
        '${phase.startsAt.toLocal().minute.toString().padLeft(2, '0')}',
        style: const TextStyle(color: V2Palette.mutedInk, fontSize: 10),
      ),
    ],
  );

  static Color _color(ShootingConditionBand value) => switch (value) {
    ShootingConditionBand.good => V2Palette.moss,
    ShootingConditionBand.fair => V2Palette.ember,
    ShootingConditionBand.limited => V2Palette.line,
  };

  static String _label(ShootingPhaseKind value) => switch (value) {
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
