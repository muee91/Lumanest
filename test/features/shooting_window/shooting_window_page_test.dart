import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/shooting_window/presentation/shooting_window_page.dart';

void main() {
  testWidgets('renders calculated windows and the terrain limitation', (
    tester,
  ) async {
    final sunrise = DateTime.utc(2026, 7, 13, 21);
    final sunset = DateTime.utc(2026, 7, 14, 11);
    final snapshot = ContextSnapshot(
      id: 'window-page',
      observedAt: sunset.subtract(const Duration(minutes: 10)),
      expiresAt: sunset,
      primaryScene: SceneType.city,
      dayPhase: DayPhase.sunset,
      weather: WeatherType.clear,
      activeRoute: false,
      sunrise: sunrise,
      sunset: sunset,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ShootingWindowPage(snapshotAsync: AsyncData(snapshot)),
        ),
      ),
    );

    expect(find.text('晨光窗口'), findsOneWidget);
    expect(find.text('落日窗口'), findsOneWidget);
    expect(find.text('蓝调窗口'), findsOneWidget);
    expect(find.textContaining('不包含山体'), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);
  });
}
