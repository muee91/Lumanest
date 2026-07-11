import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/features/explore/infrastructure/amap_initializer.dart';
import 'package:luma_nest/src/features/explore/presentation/explore_page.dart';

import 'map_consent_test_harness.dart';

Widget wrapExplorePage({
  required String amapKey,
  FakeAmapInitializerGateway? gateway,
  MapSurfaceBuilder? mapBuilder,
}) {
  return ProviderScope(
    overrides: [
      environmentConfigProvider.overrideWithValue(
        EnvironmentConfig(amapAndroidKey: amapKey),
      ),
      amapInitializerGatewayProvider.overrideWithValue(
        gateway ?? FakeAmapInitializerGateway(),
      ),
    ],
    child: MaterialApp(home: ExplorePage(mapBuilder: mapBuilder)),
  );
}

Widget fakeMapSurface() => const SizedBox(
      key: Key('map-surface'),
      child: Text('map-placeholder'),
    );

void main() {
  testWidgets('missing key shows configuration state, not map widget', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapExplorePage(amapKey: '', mapBuilder: fakeMapSurface),
    );

    expect(find.byKey(const Key('map-surface')), findsNothing);
    expect(find.text('地图尚未配置'), findsOneWidget);
  });

  testWidgets('configured key without consent shows prompt, not map', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapExplorePage(amapKey: 'test-key', mapBuilder: fakeMapSurface),
    );

    expect(find.byKey(const Key('map-surface')), findsNothing);
    expect(find.text('同意并开启地图'), findsOneWidget);
  });

  testWidgets('accepting consent calls privacy before init and shows map', (
    tester,
  ) async {
    final gateway = FakeAmapInitializerGateway();
    await tester.pumpWidget(
      wrapExplorePage(
        amapKey: 'test-key',
        gateway: gateway,
        mapBuilder: fakeMapSurface,
      ),
    );

    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();

    expect(gateway.privacyAgreed, isTrue);
    expect(gateway.initialized, isTrue);
    expect(gateway.privacyCallIndex, lessThan(gateway.initCallIndex));
    expect(find.byKey(const Key('map-surface')), findsOneWidget);
  });

  testWidgets('map api key is passed from environment config on init', (
    tester,
  ) async {
    final gateway = FakeAmapInitializerGateway();
    await tester.pumpWidget(
      wrapExplorePage(
        amapKey: 'env-key-789',
        gateway: gateway,
        mapBuilder: fakeMapSurface,
      ),
    );

    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();

    expect(gateway.lastApiKey?.androidKey, 'env-key-789');
  });

  testWidgets('consent prompt disappears after acceptance', (tester) async {
    await tester.pumpWidget(
      wrapExplorePage(amapKey: 'test-key', mapBuilder: fakeMapSurface),
    );

    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();

    expect(find.text('同意并开启地图'), findsNothing);
  });
}
