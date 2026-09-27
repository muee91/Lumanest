import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/presentation_v2/route/v2_route_page.dart';

void main() {
  test('route action verdict is not hidden by a Scout headline', () {
    const tooLate = ShootingExecutionDecision(
      state: ShootingExecutionState.tooLate,
      label: '查看下次窗口',
      reason: '按当前路程已无法在有效阶段开始前到达。',
    );

    expect(
      routeVerdictHeadline(
        decision: tooLate,
        hasReviewedTarget: true,
        scoutHeadline: '路线与拍摄时间窗口有重合',
        scoutCritical: false,
      ),
      '按当前路线已经赶不上',
    );
    expect(
      routeVerdictHeadline(
        decision: const ShootingExecutionDecision(
          state: ShootingExecutionState.departNow,
          label: '立即出发',
          reason: '已接近最晚出发时间。',
        ),
        hasReviewedTarget: true,
        scoutHeadline: '沿途有需要优先确认的天气风险',
        scoutCritical: true,
      ),
      '现在该出发',
    );
  });
}
