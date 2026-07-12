import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';

void main() {
  test('creative opportunities become short inspiration notes', () {
    final notes = InspirationNotes.build(ContextFixtures.lakeSunset());

    expect(notes.first.id, 'reflection');
    expect(notes.first.displayLabel, '找倒影🪞');
  });

  test('safety events never enter the inspiration bottle', () {
    final notes = InspirationNotes.build(
      ContextSnapshot(
        id: 'storm',
        observedAt: DateTime.utc(2026, 7, 12),
        expiresAt: DateTime.utc(2026, 7, 12, 0, 10),
        primaryScene: SceneType.hiking,
        dayPhase: DayPhase.day,
        weather: WeatherType.rain,
        activeRoute: true,
        safetyEventIds: const ['thunderstorm'],
      ),
    );

    expect(notes.map((note) => note.id), isNot(contains('thunderstorm')));
    expect(
      notes.map((note) => note.displayLabel).join(),
      isNot(contains('雷暴')),
    );
  });
}
