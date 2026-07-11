import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';

void main() {
  test('environment consent is off until the user explicitly grants it', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(environmentConsentProvider), isFalse);

    container.read(environmentConsentProvider.notifier).grant();

    expect(container.read(environmentConsentProvider), isTrue);
  });
}
