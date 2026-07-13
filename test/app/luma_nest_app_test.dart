import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/app/luma_nest_app.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';

void main() {
  testWidgets('shows privacy-first entry and five destinations', (
    tester,
  ) async {
    await tester.pumpWidget(const LumaNestApp());

    expect(find.text('从当前位置开始'), findsOneWidget);
    expect(find.text('今日'), findsOneWidget);
    expect(find.text('探索'), findsOneWidget);
    expect(find.text('路线'), findsOneWidget);
    expect(find.text('灵感'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });

  testWidgets('accepts an injected context snapshot', (tester) async {
    await tester.pumpWidget(
      LumaNestApp(initialContext: ContextFixtures.lakeSunset()),
    );

    expect(find.text('倒影条件改善'), findsWidgets);
  });
}
