import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/explore/application/map_consent_controller.dart';

import 'map_consent_test_harness.dart';

void main() {
  test('missing amap key returns configuration-missing state', () {
    final container = createMapTestContainer(amapKey: '');

    final state = container.read(mapConsentControllerProvider);

    expect(state, isA<MapConsentConfigurationMissing>());
  });

  test('configured key without consent returns awaiting-consent state', () {
    final container = createMapTestContainer(amapKey: 'test-key');

    final state = container.read(mapConsentControllerProvider);

    expect(state, isA<MapConsentAwaiting>());
  });

  test('granting consent updates privacy agreement and enters ready', () {
    final gateway = FakeAmapInitializerGateway();
    final container = createMapTestContainer(
      amapKey: 'test-key',
      gateway: gateway,
    );

    container.read(mapConsentControllerProvider.notifier).grantConsent();

    expect(gateway.privacyAgreed, isTrue);
    expect(gateway.initialized, isFalse);
    expect(
      container.read(mapConsentControllerProvider),
      isA<MapConsentReady>(),
    );
  });

  test('privacy statement has all three flags set to true on consent', () {
    final gateway = FakeAmapInitializerGateway();
    final container = createMapTestContainer(
      amapKey: 'test-key',
      gateway: gateway,
    );

    container.read(mapConsentControllerProvider.notifier).grantConsent();

    expect(gateway.lastStatement?.hasContains, isTrue);
    expect(gateway.lastStatement?.hasShow, isTrue);
    expect(gateway.lastStatement?.hasAgree, isTrue);
  });

  test('granting consent when already ready is idempotent', () {
    final gateway = FakeAmapInitializerGateway();
    final container = createMapTestContainer(
      amapKey: 'test-key',
      gateway: gateway,
    );

    container.read(mapConsentControllerProvider.notifier).grantConsent();
    final callCountAfterFirst = gateway.totalCalls;
    container.read(mapConsentControllerProvider.notifier).grantConsent();

    expect(gateway.totalCalls, callCountAfterFirst);
    expect(
      container.read(mapConsentControllerProvider),
      isA<MapConsentReady>(),
    );
  });

  test('amap api key from environment config is used for init', () {
    final gateway = FakeAmapInitializerGateway();
    final container = createMapTestContainer(
      amapKey: 'config-key-123',
      gateway: gateway,
    );

    container.read(mapConsentControllerProvider.notifier).grantConsent();
    container.read(mapConsentControllerProvider.notifier).ensureInitialized(
      FakeBuildContext(),
    );

    expect(gateway.lastApiKey?.androidKey, 'config-key-123');
  });

  test('init is called after privacy agree when flow is triggered correctly', () {
    final gateway = FakeAmapInitializerGateway();
    final container = createMapTestContainer(
      amapKey: 'test-key',
      gateway: gateway,
    );

    container.read(mapConsentControllerProvider.notifier).grantConsent();
    container.read(mapConsentControllerProvider.notifier).ensureInitialized(
      FakeBuildContext(),
    );

    expect(gateway.privacyCallIndex, lessThan(gateway.initCallIndex));
    expect(gateway.initialized, isTrue);
  });
}
