import 'package:flutter_test/flutter_test.dart';
import 'package:qiguang/src/app/qiguang_app.dart';

void main() {
  testWidgets('shows the Qiguang brand and five destinations', (tester) async {
    await tester.pumpWidget(const QiguangApp());

    expect(find.text('栖光'), findsOneWidget);
    expect(find.text('今日'), findsOneWidget);
    expect(find.text('探索'), findsOneWidget);
    expect(find.text('路线'), findsOneWidget);
    expect(find.text('灵感'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}
