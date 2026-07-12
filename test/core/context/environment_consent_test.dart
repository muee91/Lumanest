import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';

void main() {
  test(
    'environment consent is off until the user explicitly grants it',
    () async {
      final container = ProviderContainer(
        overrides: [
          environmentConsentStoreProvider.overrideWithValue(
            _FakeEnvironmentConsentStore(),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(environmentConsentProvider), isFalse);

      container.read(environmentConsentProvider.notifier).grant();

      expect(container.read(environmentConsentProvider), isTrue);
    },
  );

  test('restores a previously granted consent', () async {
    final store = _FakeEnvironmentConsentStore(granted: true);
    final container = ProviderContainer(
      overrides: [environmentConsentStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    expect(container.read(environmentConsentProvider), isFalse);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(environmentConsentProvider), isTrue);
  });
}

class _FakeEnvironmentConsentStore implements EnvironmentConsentStore {
  _FakeEnvironmentConsentStore({this.granted = false});

  bool granted;

  @override
  Future<bool?> readGranted() async => granted;

  @override
  Future<void> saveGranted() async {
    granted = true;
  }
}
