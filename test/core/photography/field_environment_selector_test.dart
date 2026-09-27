import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/photography/field_environment_selector.dart';

void main() {
  test('selects the water priorities without fabricating factors', () {
    final session = ContextFixtures.waterEveningSession(
      observedAt: DateTime.utc(2026, 7, 17, 10),
    );

    final selected = FieldEnvironmentSelector.select(session);

    expect(selected, hasLength(3));
    expect(selected.map((factor) => factor.id), [
      'wind',
      'precipitation',
      'cloud',
    ]);
  });

  test('empty evidence remains empty', () {
    final session = ContextFixtures.waterMorningSession(
      observedAt: DateTime.utc(2026, 7, 17, 10),
    );

    final selected = FieldEnvironmentSelector.select(session, maxFacts: 3);

    expect(selected, hasLength(2));
    expect(selected.every((factor) => factor.value.isNotEmpty), isTrue);
  });
}
