import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_debug_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Debug Studio exposes the full ambient scenario controls', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AmbientDebugPage()));
    for (var index = 0; index < 10; index += 1) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.textContaining('preset=').evaluate().isNotEmpty) break;
    }
    expect(find.text('动态背景实验室'), findsOneWidget);
    expect(find.text('晴朗日间 · 标准动效（30 帧）'), findsOneWidget);
    expect(find.text('模拟低电量节能模式'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -360));
    await tester.pump();
    expect(find.text('高级参数（可选）'), findsOneWidget);
  });
}
