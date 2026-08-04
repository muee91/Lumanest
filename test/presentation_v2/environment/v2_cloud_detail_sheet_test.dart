import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/today/application/environment_visualization.dart';
import 'package:luma_nest/src/presentation_v2/environment/v2_cloud_detail_sheet.dart';

void main() {
  testWidgets('cloud detail renders professional layered structure', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 4, 10);
    final cloud = CloudVisualization(
      totalCloudCoverPercent: 91,
      lowCloudCoverPercent: 82,
      middleCloudCoverPercent: 46,
      highCloudCoverPercent: 18,
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 20)),
      isStale: false,
      sourceLabel: 'Open-Meteo 分层云量 · 7Timer 辅助校验',
      weatherAgreement: 'strong',
      scene: SceneType.lake,
      dayPhase: DayPhase.sunset,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: V2CloudDetailSheet(cloud: cloud)),
      ),
    );

    expect(find.byKey(const Key('v2-cloud-layer-chart')), findsOneWidget);
    expect(find.byKey(const Key('v2-cloud-total')), findsOneWidget);
    expect(find.text('垂直云层结构'), findsOneWidget);
    expect(find.textContaining('低云可能遮挡'), findsOneWidget);
    expect(find.text('模型一致性'), findsOneWidget);
  });

  testWidgets('cloud detail does not fabricate missing layers', (tester) async {
    final now = DateTime.utc(2026, 8, 4, 10);
    final cloud = CloudVisualization(
      totalCloudCoverPercent: 64,
      lowCloudCoverPercent: null,
      middleCloudCoverPercent: null,
      highCloudCoverPercent: null,
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 20)),
      isStale: false,
      sourceLabel: 'Context 当前天气',
      weatherAgreement: null,
      scene: SceneType.city,
      dayPhase: DayPhase.day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: V2CloudDetailSheet(cloud: cloud)),
      ),
    );

    expect(find.byKey(const Key('v2-cloud-layer-chart')), findsNothing);
    expect(find.text('分层云量暂不可用'), findsOneWidget);
    expect(find.textContaining('未补齐缺失'), findsOneWidget);
  });
}
