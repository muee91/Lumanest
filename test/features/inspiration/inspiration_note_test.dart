import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative.dart';

void main() {
  test('creative opportunities become short inspiration notes', () {
    final notes = InspirationNotes.build(ContextFixtures.lakeSunset());

    expect(notes.first.id, 'reflection');
    expect(notes.first.displayLabel, '找倒影🪞');
  });

  test('validated narrative can refine wording but not create notes', () {
    final snapshot = ContextFixtures.lakeSunset();
    final narrative = ManifestNarrative(
      summary: '湖面正在安静下来。',
      noteLabels: const {'reflection': '等倒影'},
      source: ManifestNarrativeSource.model,
      generatedAt: DateTime.utc(2026, 7, 11, 10),
      expiresAt: DateTime.utc(2026, 7, 11, 10, 10),
    );

    final notes = InspirationNotes.build(snapshot, narrative: narrative);

    expect(notes.map((note) => note.id), ['reflection', 'blue-hour']);
    expect(notes.first.displayLabel, '等倒影🪞');
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
    expect(notes, isEmpty);
  });

  test('regional wildlife becomes a creative note, never a safety alert', () {
    final notes = InspirationNotes.build(
      ContextSnapshot(
        id: 'wildlife',
        observedAt: DateTime.utc(2026, 7, 12),
        expiresAt: DateTime.utc(2026, 7, 12, 0, 10),
        primaryScene: SceneType.hiking,
        dayPhase: DayPhase.day,
        weather: WeatherType.clear,
        activeRoute: false,
        wildlifeEventIds: const ['regional-wildlife'],
      ),
    );

    expect(notes.map((note) => note.id), contains('regional-wildlife'));
    expect(
      notes.singleWhere((note) => note.id == 'regional-wildlife').detail,
      contains('GBIF'),
    );
  });
}
