import 'dart:async';

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

  test('granting consent updates privacy agreement and enters ready', () async {
    final gateway = FakeAmapInitializerGateway();
    final store = FakeMapConsentStore();
    final container = createMapTestContainer(
      amapKey: 'test-key',
      gateway: gateway,
      consentStore: store,
    );

    await container.read(mapConsentControllerProvider.notifier).grantConsent();

    expect(gateway.privacyAgreed, isTrue);
    expect(store.granted, isTrue);
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

  test('revoking consent gates the map and persists the choice', () async {
    final gateway = FakeAmapInitializerGateway();
    final store = FakeMapConsentStore();
    final container = createMapTestContainer(
      amapKey: 'test-key',
      gateway: gateway,
      consentStore: store,
    );
    addTearDown(container.dispose);
    final controller = container.read(mapConsentControllerProvider.notifier);
    await controller.grantConsent();

    await controller.revokeConsent();

    expect(gateway.lastStatement?.hasAgree, isFalse);
    expect(store.granted, isFalse);
    expect(
      container.read(mapConsentControllerProvider),
      isA<MapConsentAwaiting>(),
    );
  });

  test('restores consent and updates SDK before entering ready', () async {
    final gateway = FakeAmapInitializerGateway();
    final store = FakeMapConsentStore(granted: true);
    final container = createMapTestContainer(
      amapKey: 'test-key',
      gateway: gateway,
      consentStore: store,
    );

    final states = <MapConsentState>[];
    container.listen(mapConsentControllerProvider, (_, next) {
      states.add(next);
    }, fireImmediately: true);
    await Future<void>.delayed(Duration.zero);

    expect(gateway.lastStatement?.hasAgree, isTrue);
    expect(states.first, isA<MapConsentAwaiting>());
    expect(states.last, isA<MapConsentReady>());
  });

  test('session revoke wins over an in-flight restore', () async {
    final restoreMayFinish = Completer<void>();
    final gateway = FakeAmapInitializerGateway();
    final store = FakeMapConsentStore(
      granted: true,
      readBarrier: restoreMayFinish.future,
    );
    final container = createMapTestContainer(
      amapKey: 'test-key',
      gateway: gateway,
      consentStore: store,
    );
    final controller = container.read(mapConsentControllerProvider.notifier);

    await controller.revokeConsent();
    restoreMayFinish.complete();
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(mapConsentControllerProvider),
      isA<MapConsentAwaiting>(),
    );
    expect(gateway.lastStatement?.hasAgree, isFalse);
    expect(store.granted, isFalse);
  });

  test('revoke persistence follows an in-flight grant persistence', () async {
    final store = _DelayedGrantMapConsentStore();
    final container = createMapTestContainer(
      amapKey: 'test-key',
      consentStore: store,
    );
    final controller = container.read(mapConsentControllerProvider.notifier);

    final grant = controller.grantConsent();
    await store.grantWriteStarted.future;
    final revoke = controller.revokeConsent();
    store.allowGrantWriteToFinish.complete();
    await Future.wait([grant, revoke]);

    expect(store.writes, [true, false]);
    expect(store.granted, isFalse);
    expect(
      container.read(mapConsentControllerProvider),
      isA<MapConsentAwaiting>(),
    );
  });

  test('amap api key from environment config is used for init', () {
    final gateway = FakeAmapInitializerGateway();
    final container = createMapTestContainer(
      amapKey: 'config-key-123',
      gateway: gateway,
    );

    container.read(mapConsentControllerProvider.notifier).grantConsent();
    container
        .read(mapConsentControllerProvider.notifier)
        .ensureInitialized(FakeBuildContext());

    expect(gateway.lastApiKey?.androidKey, 'config-key-123');
  });

  test(
    'init is called after privacy agree when flow is triggered correctly',
    () {
      final gateway = FakeAmapInitializerGateway();
      final container = createMapTestContainer(
        amapKey: 'test-key',
        gateway: gateway,
      );

      container.read(mapConsentControllerProvider.notifier).grantConsent();
      container
          .read(mapConsentControllerProvider.notifier)
          .ensureInitialized(FakeBuildContext());

      expect(gateway.privacyCallIndex, lessThan(gateway.initCallIndex));
      expect(gateway.initialized, isTrue);
    },
  );

  test('grantConsent when config is missing does not enter ready', () {
    final gateway = FakeAmapInitializerGateway();
    final container = createMapTestContainer(amapKey: '', gateway: gateway);

    container.read(mapConsentControllerProvider.notifier).grantConsent();

    expect(gateway.privacyAgreed, isFalse);
    expect(
      container.read(mapConsentControllerProvider),
      isA<MapConsentConfigurationMissing>(),
    );
  });

  test('ensureInitialized when not in ready state throws', () {
    final gateway = FakeAmapInitializerGateway();
    final container = createMapTestContainer(
      amapKey: 'test-key',
      gateway: gateway,
    );

    expect(
      () => container
          .read(mapConsentControllerProvider.notifier)
          .ensureInitialized(FakeBuildContext()),
      throwsA(isA<StateError>()),
    );
    expect(gateway.initialized, isFalse);
  });
}

class _DelayedGrantMapConsentStore implements MapConsentStore {
  final grantWriteStarted = Completer<void>();
  final allowGrantWriteToFinish = Completer<void>();
  final writes = <bool>[];
  bool granted = false;

  @override
  Future<bool?> readGranted() async => false;

  @override
  Future<void> writeGranted(bool granted) async {
    if (granted) {
      grantWriteStarted.complete();
      await allowGrantWriteToFinish.future;
    }
    writes.add(granted);
    this.granted = granted;
  }
}
