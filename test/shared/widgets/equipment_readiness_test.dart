import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/photography/equipment_capability.dart';
import 'package:luma_nest/src/shared/widgets/photography/shooting_session_widgets.dart';

void main() {
  testWidgets('shows readiness separately from the environmental verdict', (
    tester,
  ) async {
    const recommended = {EquipmentCapability.tripod};
    final match = EquipmentCapabilityParser.match('相机、24mm、三脚架', recommended);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EquipmentReadiness(recommended: recommended, match: match),
        ),
      ),
    );

    expect(find.text('器材准备 · 齐全'), findsOneWidget);
    expect(find.textContaining('已识别 三脚架'), findsOneWidget);
    expect(find.textContaining('不改变环境判断'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });
}
