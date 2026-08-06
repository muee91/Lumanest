import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/presentation_v2/intelligence/assistant_decision_summary.dart';

void main() {
  test('parses the explicit decision-first answer contract', () {
    final summary = AssistantDecisionSummaryData.parse(
      '结论｜现在不值得专程出发\n'
      '依据｜云量偏多\n'
      '依据｜能见度正在下降\n'
      '限制｜仍需现场确认局地云层\n'
      '下一步｜22:05 前 15 分钟重新检查',
    );

    expect(summary.conclusion, '现在不值得专程出发');
    expect(summary.keyPoints, ['云量偏多', '能见度正在下降']);
    expect(summary.limitations, ['仍需现场确认局地云层']);
    expect(summary.nextAction, '22:05 前 15 分钟重新检查');
  });

  test('promotes the decision from a legacy prose answer', () {
    final summary = AssistantDecisionSummaryData.parse(
      '当前多云，风速约4.2 m/s。今天优先拍「湖岸晚间窗口」。'
      '打开机会详情可以查看依据和行动安排。',
    );

    expect(summary.conclusion, contains('优先拍'));
    expect(summary.keyPoints.single, contains('当前多云'));
    expect(summary.nextAction, contains('打开机会详情'));
  });

  testWidgets(
    'renders conclusion, evidence, limitation and action distinctly',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AssistantDecisionSummary(
              text:
                  '结论｜先不要专程出发\n'
                  '依据｜云量偏多\n'
                  '限制｜区域预报不能代替现场观察\n'
                  '下一步｜日落前重新确认',
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('assistant-decision-conclusion')), findsOne);
      expect(find.byKey(const Key('assistant-decision-key-points')), findsOne);
      expect(find.byKey(const Key('assistant-decision-limitations')), findsOne);
      expect(find.byKey(const Key('assistant-decision-next-action')), findsOne);
    },
  );

  testWidgets('keeps an unfinished stream as stable plain text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AssistantDecisionSummary(text: '正在生成', loading: true),
        ),
      ),
    );

    expect(find.text('正在生成'), findsOne);
    expect(
      find.byKey(const Key('assistant-decision-conclusion')),
      findsNothing,
    );
  });
}
