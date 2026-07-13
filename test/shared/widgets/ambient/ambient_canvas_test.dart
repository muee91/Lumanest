import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_canvas.dart';

void main() {
  testWidgets('renders a static non-interactive environment color layer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AmbientCanvas())),
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

  testWidgets('reduceMotion true produces no continuously ticking animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AmbientCanvas(reduceMotion: true)),
      ),
    );

    expect(find.byType(AmbientCanvas), findsOneWidget);

    // Pump several frames — with reduceMotion: true, no animation
    // controller exists, so the widget tree should not tick.
    final callbackCount = tester.binding.transientCallbackCount;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    // transientCallbackCount should not have grown from a new ticker.
    expect(tester.binding.transientCallbackCount, callbackCount);
  });

  testWidgets('runtime reduceMotion toggle stops and starts animation', (
    tester,
  ) async {
    // Start with animation enabled.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AmbientCanvas(reduceMotion: false)),
      ),
    );

    // With reduceMotion false, an AnimationController is active.
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    final initialCount = tester.binding.transientCallbackCount;

    // Toggle reduceMotion to true — animation should stop.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AmbientCanvas(reduceMotion: true)),
      ),
    );
    await tester.pump();

    expect(tester.binding.transientCallbackCount, lessThan(initialCount));

    // Toggle reduceMotion back to false — animation should restart.
    final stoppedCount = tester.binding.transientCallbackCount;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AmbientCanvas(reduceMotion: false)),
      ),
    );
    await tester.pump();

    expect(tester.binding.transientCallbackCount, greaterThan(stoppedCount));
  });

  testWidgets('static mode can suppress weather texture independently', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AmbientCanvas(reduceMotion: true, showWeatherTexture: false),
        ),
      ),
    );

    expect(
      tester
          .widget<AmbientCanvas>(find.byType(AmbientCanvas))
          .showWeatherTexture,
      isFalse,
    );
    expect(tester.binding.transientCallbackCount, 0);
  });
}
