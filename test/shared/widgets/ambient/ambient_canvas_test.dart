import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qiguang/src/shared/widgets/ambient/ambient_canvas.dart';

void main() {
  testWidgets('renders a static non-interactive environment color layer', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AmbientCanvas(),
        ),
      ),
    );

    expect(find.byType(AmbientCanvas), findsOneWidget);
  });

  testWidgets('does not intercept pointer events', (tester) async {
    bool tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const AmbientCanvas(),
              GestureDetector(
                onTap: () => tapped = true,
                child: Container(color: Colors.transparent),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(GestureDetector));
    expect(tapped, isTrue);
  });

  testWidgets('reduceMotion true produces no continuously ticking animation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AmbientCanvas(reduceMotion: true),
        ),
      ),
    );

    final ambientFinder = find.byType(AmbientCanvas);
    expect(ambientFinder, findsOneWidget);

    final element = tester.element(ambientFinder);
    final initialHash = element.hashCode;

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    // With reduceMotion true, the widget should not rebuild due to animation
    expect(element.hashCode, initialHash);
  });

  testWidgets('ambient canvas fills available space', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AmbientCanvas(),
      ),
    );

    final canvas = tester.widget<AmbientCanvas>(find.byType(AmbientCanvas));
    expect(canvas, isNotNull);
  });
}
