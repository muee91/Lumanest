import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/environment/provider_facts.dart';
import 'package:luma_nest/src/core/environment/provider_signal_relevance.dart';

void main() {
  final now = DateTime.parse('2026-08-03T08:00:00Z');

  test('mountain context promotes operations, surface and atmosphere', () {
    final selected = selectProviderSignalsForContext(
      _bundle(now),
      _snapshot(SceneType.mountain, now),
      now: now,
    );

    expect(selected, hasLength(4));
    expect(selected.first.category, ProviderCategory.operations);
    expect(
      selected.map((item) => item.category),
      containsAll(<ProviderCategory>[
        ProviderCategory.surface,
        ProviderCategory.atmosphere,
        ProviderCategory.outdoor,
      ]),
    );
  });

  test('authoritative notice remains first even outside its normal scene', () {
    final selected = selectProviderSignalsForContext(
      _bundle(now),
      _snapshot(SceneType.city, now),
      now: now,
      maximum: 2,
    );

    expect(selected.first.verification, ProviderVerification.authoritative);
    expect(selected.first.kind, 'closure');
    expect(selected, hasLength(2));
  });

  test('active routes prioritize operational and outdoor evidence', () {
    final selected = selectProviderSignalsForContext(
      _bundle(now),
      _snapshot(
        SceneType.unknown,
        now,
        routeMode: ContextRouteMode.hiking,
        routeStage: ContextRouteStage.active,
      ),
      now: now,
      maximum: 3,
    );

    expect(selected[0].category, ProviderCategory.operations);
    expect(selected[1].category, ProviderCategory.outdoor);
    expect(selected, hasLength(3));
  });

  test('expired signals never enter contextual selection', () {
    final selected = selectProviderSignalsForContext(
      _bundle(now),
      _snapshot(SceneType.desert, now),
      now: now.add(const Duration(days: 2)),
    );

    expect(selected, isEmpty);
  });
}

ContextSnapshot _snapshot(
  SceneType scene,
  DateTime now, {
  ContextRouteMode routeMode = ContextRouteMode.none,
  ContextRouteStage routeStage = ContextRouteStage.none,
}) =>
    ContextSnapshot(
      id: 'ctx_${'a' * 24}',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 10)),
      primaryScene: scene,
      dayPhase: DayPhase.day,
      weather: WeatherType.clear,
      activeRoute: routeStage == ContextRouteStage.active,
      routeMode: routeMode,
      routeStage: routeStage,
    );

ProviderFactsBundle _bundle(DateTime now) {
  final expiresAt = now.add(const Duration(days: 1)).toIso8601String();
  final observedAt = now.subtract(const Duration(hours: 1)).toIso8601String();
  final entries = <Map<String, Object?>>[
    _provider('officialNotices', 'operations', 'closure', 'authoritative', observedAt, expiresAt),
    _provider('sentinel2', 'surface', 'vegetationIndexChange', 'observed', observedAt, expiresAt),
    _provider('cams', 'atmosphere', 'dustLoad', 'model', observedAt, expiresAt),
    _provider('osm', 'outdoor', 'outdoorMapInventory', 'reference', observedAt, expiresAt),
    _provider('wikidata', 'culture', 'culturalEntities', 'reference', observedAt, expiresAt),
    _provider('firms', 'fire', 'thermalAnomaly', 'candidate', observedAt, expiresAt),
  ];
  return ProviderFactsBundle.fromJson({
    'contractVersion': 1,
    'requestedCoordinate': {
      'latitude': 30.25,
      'longitude': 120.15,
      'system': 'wgs84',
    },
    'radiusKm': 25,
    'generatedAt': now.toIso8601String(),
    'expiresAt': expiresAt,
    'status': 'ready',
    'cacheStatus': 'miss',
    'providers': entries,
  });
}

Map<String, Object?> _provider(
  String id,
  String category,
  String kind,
  String verification,
  String observedAt,
  String expiresAt,
) =>
    {
      'id': id,
      'category': category,
      'status': 'ready',
      'observedAt': observedAt,
      'expiresAt': expiresAt,
      'source': {
        'id': 'source-$id',
        'title': id,
        'publisher': id,
        'url': 'https://example.com/$id',
        'license': 'test',
        'version': '1',
      },
      'signals': [
        {
          'id': 'signal-$id',
          'kind': kind,
          'category': category,
          'title': kind,
          'summary': '$kind summary',
          'verification': verification,
          'observedAt': observedAt,
          'expiresAt': expiresAt,
          'sourceUrl': 'https://example.com/$id/item',
        },
      ],
      'message': null,
    };
