part of '../v2_route_page.dart';

/// The action-first route conclusion. The class is public so the exact text
/// hierarchy can be regression-tested without booting an AMap surface.
class V2RouteVerdict extends StatelessWidget {
  const V2RouteVerdict({
    super.key,
    required this.route,
    required this.destination,
    required this.snapshot,
    required this.scout,
    this.activeShootingIntent,
    this.now,
  });
  final DrivingRoute route;
  final RouteDestination destination;
  final ContextSnapshot? snapshot;
  final RouteScoutPlan? scout;
  final ActiveShootingIntent? activeShootingIntent;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final currentTime = now ?? DateTime.now();
    final arrival = currentTime.add(Duration(seconds: route.durationSeconds));
    final freshSnapshot =
        snapshot != null &&
            !snapshot!.isStale &&
            snapshot!.dataFreshness != ContextDataFreshness.stale &&
            snapshot!.expiresAt.toUtc().isAfter(currentTime.toUtc())
        ? snapshot
        : null;
    final selection = freshSnapshot == null
        ? null
        : ShootingSessionSelector.selectForDestination(
            freshSnapshot.shootingSessions,
            destination: destination.point,
            now: currentTime,
            requestedSessionId: activeShootingIntent?.sessionId,
            requestedTargetId: activeShootingIntent?.targetId,
          );
    // A route to an arbitrary place must not inherit the current session's
    // timing verdict. Only a reviewed target tied to this destination can
    // produce a catchability or latest-departure statement.
    final session = selection?.session;
    final target = selection?.target;
    final decision = session == null
        ? null
        : ShootingExecutionResolver.resolve(
            session: session,
            now: currentTime,
            target: target,
            routeDuration: Duration(seconds: route.durationSeconds),
          );
    final canCatch = switch (decision?.state) {
      ShootingExecutionState.waitToDepart ||
      ShootingExecutionState.departNow ||
      ShootingExecutionState.waitAtTarget ||
      ShootingExecutionState.shootNow => true,
      ShootingExecutionState.tooLate => false,
      _ => null,
    };
    final blockingSafety = scout?.primaryBlockingNode;
    final urgentSafety = scout?.primaryUrgentNode;
    final advisorySafety = scout?.primaryAdvisorySafety;
    final safetyNode = blockingSafety ?? urgentSafety ?? advisorySafety;
    final headline = routeVerdictHeadline(
      decision: decision,
      hasReviewedTarget: target != null,
      scoutHeadline: scout?.headline,
      blockingSafety: blockingSafety,
      urgentSafety: urgentSafety,
    );
    final urgent =
        blockingSafety != null ||
        urgentSafety != null ||
        canCatch == false ||
        decision?.state == ShootingExecutionState.departNow ||
        decision?.state == ShootingExecutionState.tooLate;
    return Material(
      color: V2Palette.paper,
      elevation: 10,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 17, 20, 16),
        child: Row(
          children: [
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: urgent ? V2Palette.ember : V2Palette.moss,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: const TextStyle(
                      color: V2Palette.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.4,
                    ),
                  ),
                  if (safetyNode != null && safetyNode.title != headline) ...[
                    const SizedBox(height: 3),
                    Text(
                      safetyNode.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: V2Palette.ember,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${_duration(route.durationSeconds)} · ${_distance(route.distanceMeters)}',
                    style: const TextStyle(
                      color: V2Palette.mutedInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (decision?.departureDeadline != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '最晚 ${_time(decision!.departureDeadline!)} 出发',
                      style: TextStyle(
                        color: urgent ? V2Palette.ember : V2Palette.moss,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              '${_time(arrival)} 抵达',
              style: const TextStyle(
                color: V2Palette.ink,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _duration(int seconds) {
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return '$minutes 分钟';
    return '${minutes ~/ 60}小时${minutes % 60}分';
  }

  static String _distance(int meters) =>
      meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '$meters m';

  static String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

/// Route conclusions are deliberately action-first. Scout is useful context,
/// but its generic headline must never replace a verified departure verdict.
@visibleForTesting
String routeVerdictHeadline({
  required ShootingExecutionDecision? decision,
  required bool hasReviewedTarget,
  required String? scoutHeadline,
  required RouteScoutNode? blockingSafety,
  required RouteScoutNode? urgentSafety,
}) {
  if (blockingSafety != null) return '沿途有官方管制，先确认再出发';
  if (decision == null && urgentSafety != null) return urgentSafety.title;
  switch (decision?.state) {
    case ShootingExecutionState.tooLate:
      return '按当前路线已经赶不上';
    case ShootingExecutionState.departNow:
      return '现在该出发';
    case ShootingExecutionState.waitToDepart:
    case ShootingExecutionState.waitAtTarget:
    case ShootingExecutionState.shootNow:
      return '按当前路线赶得上';
    case ShootingExecutionState.observe:
      return hasReviewedTarget ? '当前条件不足以判断' : (scoutHeadline ?? '路线已经准备好');
    case ShootingExecutionState.planRoute:
      return hasReviewedTarget ? '路线已经准备好' : (scoutHeadline ?? '路线已经准备好');
    case ShootingExecutionState.ended:
      return scoutHeadline ?? '路线已经准备好';
    case null:
      return scoutHeadline ?? '路线已经准备好';
  }
}
