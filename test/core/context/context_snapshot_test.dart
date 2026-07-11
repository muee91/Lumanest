import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';

void main() {
  test('quiet city fixture describes an inactive urban context', () {
    final snapshot = ContextFixtures.quietCity();

    expect(snapshot.primaryScene, SceneType.city);
    expect(snapshot.activeRoute, isFalse);
    expect(snapshot.opportunityIds, isEmpty);
  });

  test('lake sunset fixture exposes a reflection opportunity', () {
    final snapshot = ContextFixtures.lakeSunset();

    expect(snapshot.primaryScene, SceneType.lake);
    expect(snapshot.dayPhase, DayPhase.sunset);
    expect(snapshot.opportunityIds, contains('reflection'));
  });

  test('mountain dawn fixture exposes an alpenglow opportunity', () {
    final snapshot = ContextFixtures.mountainDawn();

    expect(snapshot.primaryScene, SceneType.mountain);
    expect(snapshot.dayPhase, DayPhase.dawn);
    expect(snapshot.opportunityIds, contains('alpenglow'));
  });

  test('snapshot event collections cannot be mutated', () {
    final snapshot = ContextFixtures.lakeSunset();

    expect(
      () => snapshot.opportunityIds.add('fake-opportunity'),
      throwsUnsupportedError,
    );
  });
}
