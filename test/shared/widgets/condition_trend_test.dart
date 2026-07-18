import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/shared/widgets/photography/shooting_session_widgets.dart';

void main() {
  testWidgets('trend explains axes and exposes an accessible change summary', (
    tester,
  ) async {
    final start = DateTime.utc(2026, 7, 18, 10);
    final samples = [
      ShootingSessionTrendSample(
        at: start,
        conditionIndex: 45,
        cloudCoverPercent: 70,
        windSpeedMps: 4,
        precipitationMm: 0,
      ),
      ShootingSessionTrendSample(
        at: start.add(const Duration(minutes: 30)),
        conditionIndex: 72,
        cloudCoverPercent: 55,
        windSpeedMps: 2,
        precipitationMm: 0,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConditionTrend(samples: samples)),
      ),
    );

    expect(find.textContaining('不是发生概率'), findsOneWidget);
    final semantics = tester.getSemantics(find.byType(ConditionTrend));
    expect(semantics.label, contains('从 45 变化到 72'));
    expect(semantics.label, contains('增强'));
  });
}
