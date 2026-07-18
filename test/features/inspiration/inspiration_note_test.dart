import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative.dart';
import 'package:luma_nest/src/core/photography/equipment_capability.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';
import 'package:luma_nest/src/features/sky_opportunity/domain/sky_opportunity.dart';

void main() {
  test('current shooting sessions become factual inspiration notes', () {
    final snapshot = ContextFixtures.lakeSunset();
    final notes = InspirationNotes.build(snapshot);
    final factual = notes.where((note) => note.isFactual).single;

    expect(factual.id, snapshot.shootingSessions.single.id);
    expect(factual.displayLabel, '湖岸晚光🌇');
    expect(factual.evidence, contains('风速 2.1m/s'));
    expect(factual.opportunityId, snapshot.shootingSessions.single.id);
  });

  test('validated narrative can refine wording but cannot create facts', () {
    final snapshot = ContextFixtures.lakeSunset();
    final sessionId = snapshot.shootingSessions.single.id;
    final narrative = ManifestNarrative(
      summary: '湖面正在安静下来。',
      noteLabels: {sessionId: '等湖面安静'},
      source: ManifestNarrativeSource.model,
      generatedAt: DateTime.utc(2026, 7, 11, 10),
      expiresAt: DateTime.utc(2026, 7, 11, 10, 10),
    );

    final notes = InspirationNotes.build(snapshot, narrative: narrative);

    expect(notes.first.displayLabel, '等湖面安静🌇');
    expect(notes.where((note) => note.isFactual), hasLength(1));
  });

  test('safety and wildlife events never enter the inspiration bottle', () {
    final notes = InspirationNotes.build(
      ContextSnapshot(
        id: 'safety-only',
        observedAt: DateTime.utc(2026, 7, 12),
        expiresAt: DateTime.utc(2026, 7, 12, 0, 10),
        primaryScene: SceneType.mountain,
        dayPhase: DayPhase.day,
        weather: WeatherType.rain,
        activeRoute: true,
        safetyEventIds: const ['thunderstorm'],
        wildlifeEventIds: const ['regional-wildlife'],
      ),
    );

    expect(notes.where((note) => note.isFactual), isEmpty);
    expect(notes.map((note) => note.id), isNot(contains('thunderstorm')));
    expect(notes.map((note) => note.id), isNot(contains('regional-wildlife')));
  });

  test('generated creative catalog keeps inventory at target size 36', () {
    final notes = InspirationNotes.build(ContextFixtures.quietCity());

    expect(notes, hasLength(36));
    expect(notes.every((note) => !note.isFactual), isTrue);
    expect(notes.every((note) => note.id.startsWith('creative.')), isTrue);
    expect(notes.map((note) => note.id).toSet(), hasLength(36));
  });

  test('equipment-matched generated prompts rank ahead of unmet prompts', () {
    final notes = InspirationNotes.build(
      ContextFixtures.quietCity(),
      availableEquipment: const {
        EquipmentCapability.tripod,
        EquipmentCapability.telephoto,
      },
    );

    expect(notes, hasLength(36));
    expect(
      notes.take(12).any((note) => note.id == 'creative.composition.compress'),
      isTrue,
    );
  });

  test(
    'eligible structured sky result creates one factual routeable paper note',
    () {
      final forecast = _skyForecast();
      final notes = InspirationNotes.build(
        ContextFixtures.quietCity(),
        skyOpportunities: [forecast],
      );
      final note = notes.where((item) => item.id == forecast.id).single;

      expect(note.isFactual, isTrue);
      expect(note.label, '今晚有戏');
      expect(note.routeLocation, '/sky-opportunity/sunset/0');
      expect(note.detail, contains('双模型判断较一致'));
      expect(notes, hasLength(36));
    },
  );
}

SkyOpportunityForecast _skyForecast() {
  final now = DateTime.utc(2026, 7, 18, 10);
  return SkyOpportunityForecast(
    id: 'skyopp-hangzhou',
    requestedCity: '杭州',
    resolvedCity: '杭州',
    eventType: SkyOpportunityEventType.sunset,
    dayOffset: 0,
    eventTime: now.add(const Duration(hours: 2)),
    providerLocalTimeZone: 'Asia/Shanghai',
    level: 'strong',
    label: '较大概率出片',
    confidence: SkyOpportunityConfidence.high,
    agreement: SkyOpportunityAgreement.strong,
    primaryReason: '双模型判断较一致',
    clarityLevel: 'good',
    clarityLabel: '大气较通透',
    models: const [],
    fetchedAt: now,
    expiresAt: now.add(const Duration(minutes: 90)),
    cacheStatus: 'hit',
    isStale: false,
    providerStatus: 'healthy',
    attribution: '晚霞预测数据来源：SunsetBot',
    presentation: const SkyOpportunityPresentation(
      proactiveEligible: true,
      paperEligible: true,
      notificationEligible: false,
      ambientStrength: .19,
    ),
  );
}
