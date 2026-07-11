import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/app/luma_nest_app.dart';

void main() {
  testWidgets('shows the LumaNest brand and five destinations', (tester) async {
    await tester.pumpWidget(const LumaNestApp());

    expect(find.text('栖光'), findsOneWidget);
    expect(find.text('今日'), findsOneWidget);
    expect(find.text('探索'), findsOneWidget);
    expect(find.text('路线'), findsOneWidget);
    expect(find.text('灵感'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}
