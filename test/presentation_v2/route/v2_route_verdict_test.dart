import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/route/domain/route_scout_plan.dart';
import 'package:luma_nest/src/presentation_v2/route/v2_route_page.dart';

void main() {
  test('too late stays the action verdict without blocking safety', () {
    expect(
      routeVerdictHeadline(
        decision: _decision(ShootingExecutionState.tooLate),
        hasReviewedTarget: true,
        scoutHeadline: '路线与拍摄时间窗口有重合',
        blockingSafety: null,
        urgentSafety: null,
      ),
      '按当前路线已经赶不上',
    );
  });

  test('depart now remains primary with ordinary Scout information', () {
    expect(
      routeVerdictHeadline(
        decision: _decision(ShootingExecutionState.departNow),
        hasReviewedTarget: true,
        scoutHeadline: '路线与拍摄时间窗口有重合',
        blockingSafety: null,
        urgentSafety: null,
      ),
      '现在该出发',
    );
  });

  test('blocking authoritative closure outranks a departure verdict', () {
    final blocking = _node(
      actionSeverity: RouteScoutActionSeverity.blocking,
      title: '路线中段存在官方道路关闭信息',
    );

    for (final state in [
      ShootingExecutionState.departNow,
      ShootingExecutionState.waitToDepart,
    ]) {
      expect(
        routeVerdictHeadline(
          decision: _decision(state),
          hasReviewedTarget: true,
          scoutHeadline: '沿途有官方管制，先确认再出发',
          blockingSafety: blocking,
          urgentSafety: null,
        ),
        '沿途有官方管制，先确认再出发',
      );
    }
  });

  test('fresh thunder remains a visible urgent secondary signal', () {
    final urgent = _node(
      actionSeverity: RouteScoutActionSeverity.urgent,
      title: '路线中段可能出现雷暴',
    );

    expect(
      routeVerdictHeadline(
        decision: _decision(ShootingExecutionState.departNow),
        hasReviewedTarget: true,
        scoutHeadline: '沿途有需要优先确认的天气风险',
        blockingSafety: null,
        urgentSafety: urgent,
      ),
      '现在该出发',
    );
    expect(urgent.title, contains('雷暴'));
  });

  test('stale thunder is advisory and cannot become a current certainty', () {
    final stale = _node(
      actionSeverity: RouteScoutActionSeverity.advisory,
      title: '路线中段曾有雷暴风险，需要刷新确认',
      isStale: true,
    );

    expect(
      routeVerdictHeadline(
        decision: _decision(ShootingExecutionState.departNow),
        hasReviewedTarget: true,
        scoutHeadline: '路线可用，先看 1 条重点',
        blockingSafety: null,
        urgentSafety: null,
      ),
      '现在该出发',
    );
    expect(stale.title, contains('需要刷新确认'));
    expect(stale.isStale, isTrue);
  });

  test('blocking safety remains visible without a shooting intent', () {
    final blocking = _node(
      actionSeverity: RouteScoutActionSeverity.blocking,
      title: '路线前段存在官方道路关闭信息',
    );

    expect(
      routeVerdictHeadline(
        decision: null,
        hasReviewedTarget: false,
        scoutHeadline: '沿途有官方管制，先确认再出发',
        blockingSafety: blocking,
        urgentSafety: null,
      ),
      '沿途有官方管制，先确认再出发',
    );
  });

  test('photography Scout cannot override the shooting action verdict', () {
    expect(
      routeVerdictHeadline(
        decision: _decision(ShootingExecutionState.departNow),
        hasReviewedTarget: true,
        scoutHeadline: '路线与拍摄时间窗口有重合',
        blockingSafety: null,
        urgentSafety: null,
      ),
      '现在该出发',
    );
  });
}

ShootingExecutionDecision _decision(ShootingExecutionState state) =>
    ShootingExecutionDecision(state: state, label: state.name, reason: '测试判断');

RouteScoutNode _node({
  required RouteScoutActionSeverity actionSeverity,
  required String title,
  bool isStale = false,
}) => RouteScoutNode(
  id: 'test-node',
  kind: RouteScoutNodeKind.safety,
  priority:
      actionSeverity == RouteScoutActionSeverity.blocking ||
          actionSeverity == RouteScoutActionSeverity.urgent
      ? RouteScoutPriority.critical
      : RouteScoutPriority.high,
  actionSeverity: actionSeverity,
  title: title,
  detail: '测试详情',
  routeProgress: .5,
  expectedAt: DateTime.utc(2026, 9, 27, 4),
  source: 'test',
  isStale: isStale,
);
