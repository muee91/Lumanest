import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_controller.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/context/remote_context_repository.dart';
import 'package:luma_nest/src/presentation_v2/today/v2_today_page.dart';

void main() {
  testWidgets('weather failure is not presented as a location failure', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        environmentConsentStoreProvider.overrideWithValue(
          _GrantedConsentStore(),
        ),
        environmentSnapshotProvider.overrideWith(_WeatherFailureController.new),
      ],
    );
    addTearDown(container.dispose);
    container.read(environmentConsentProvider.notifier).grant();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: V2TodayPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('环境数据暂时没有更新'), findsOneWidget);
    expect(find.textContaining('位置已取得'), findsOneWidget);
    expect(find.text('暂时拿不到此刻位置'), findsNothing);
    expect(find.text('手动选择地点'), findsNothing);
    expect(find.text('重试'), findsOneWidget);
  });
}

class _WeatherFailureController extends LiveEnvironmentController {
  @override
  Future<ContextSnapshot> build() => Future.error(
    const EnvironmentLoadFailure(
      EnvironmentFailureKind.weather,
      cause: RemoteContextFailure(RemoteContextFailureKind.network),
    ),
  );
}

class _GrantedConsentStore implements EnvironmentConsentStore {
  @override
  Future<bool?> readGranted() async => true;

  @override
  Future<void> writeGranted(bool granted) async {}
}
