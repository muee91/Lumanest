import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/photography/photography_opportunity.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';

void main() {
  test('creative opportunities become short inspiration notes', () {
    final snapshot = ContextFixtures.lakeSunset();
    final notes = InspirationNotes.build(
      snapshot,
      manifest: ManifestPolicy.build(snapshot, now: snapshot.observedAt),
    );

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

    final notes = InspirationNotes.build(
      snapshot,
      narrative: narrative,
      manifest: ManifestPolicy.build(snapshot, now: snapshot.observedAt),
    );

    expect(notes.take(2).map((note) => note.id), ['reflection', 'blue-hour']);
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
    expect(notes, isNotEmpty);
    expect(notes.every((note) => !note.isFactual), isTrue);
  });

  test('wildlife records never enter the bottle', () {
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

    expect(notes.map((note) => note.id), isNot(contains('regional-wildlife')));
    expect(notes.every((note) => !note.detail.contains('GBIF')), isTrue);
  });

  test('reviewed astronomy note retains its authority action URL', () {
    final authority = Uri.parse('https://science.nasa.gov/eclipse');
    final notes = InspirationNotes.build(
      ContextSnapshot(
        id: 'astronomy',
        observedAt: DateTime.utc(2026, 7, 15),
        expiresAt: DateTime.utc(2026, 7, 15, 1),
        primaryScene: SceneType.city,
        dayPhase: DayPhase.night,
        weather: WeatherType.clear,
        activeRoute: false,
      ),
      manifest: UiManifest(
        layoutMode: LayoutMode.opportunity,
        summary: '有经过审核的天象目录。',
        primary: ManifestItem(
          id: 'astronomy-catalog:eclipse',
          title: '月食目录',
          action: ManifestAction.openAuthority,
          authorityUri: authority,
        ),
        inspirationPreview: '看天象✨',
      ),
    );

    final astronomy = notes.singleWhere(
      (note) => note.id == 'astronomy-catalog:eclipse',
    );
    expect(astronomy.action, ManifestAction.openAuthority);
    expect(astronomy.authorityUri, authority);
  });

  test('V3 opportunities keep evidence and their established action', () {
    final now = DateTime.utc(2026, 7, 17, 11);
    final notes = InspirationNotes.build(
      ContextSnapshot(
        id: 'v3',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 30)),
        primaryScene: SceneType.city,
        dayPhase: DayPhase.sunset,
        weather: WeatherType.clear,
        activeRoute: false,
        photographyOpportunities: [
          PhotographyOpportunity(
            id: 'sunset-glow',
            title: '晚霞窗口',
            startsAt: now,
            peaksAt: now.add(const Duration(minutes: 10)),
            expiresAt: now.add(const Duration(minutes: 20)),
            confidence: .8,
            primaryAction: ContextAction.openExplore,
            evidence: const [
              PhotographyEvidence(
                id: 'cloud',
                kind: PhotographyEvidenceKind.weather,
                statement: '云层条件已由预报确认。',
                confidence: .8,
              ),
            ],
          ),
        ],
      ),
    );

    final factual = notes.first;
    expect(factual.isFactual, isTrue);
    expect(factual.opportunityId, 'sunset-glow');
    expect(factual.action, ManifestAction.openExplore);
    expect(factual.evidence.single.statement, contains('预报确认'));
    expect(notes.any((note) => !note.isFactual), isTrue);
  });
}
