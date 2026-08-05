from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}: {old[:100]!r}')
    target.write_text(text.replace(old, new), encoding='utf-8')


plan = 'lib/src/features/route/domain/route_scout_plan.dart'
replace_once(
    plan,
    "    if (criticalCount > 0) return '沿途有需要优先确认的天气风险';",
    "    if (criticalCount > 0) {\n"
    "      if (nodes.any((node) => node.id.startsWith('restriction-'))) {\n"
    "        return '沿途有需要优先确认的官方管制';\n"
    "      }\n"
    "      return '沿途有需要优先确认的天气风险';\n"
    "    }",
)
replace_once(
    plan,
    "    if (weather != null) {\n      _appendWeather(nodes, weather);\n    }",
    "    if (weather != null) {\n"
    "      _appendCorridorRestrictions(nodes, weather);\n"
    "      _appendWeather(nodes, weather);\n"
    "    }",
)
replace_once(
    plan,
    "    final coverage = weather == null\n"
    "        ? RouteScoutCoverage.localOnly\n"
    "        : weather.coverage == RouteWeatherCoverage.full &&\n"
    "              !weather.hasStaleSamples\n"
    "        ? RouteScoutCoverage.full\n"
    "        : RouteScoutCoverage.partial;",
    "    final corridorComplete =\n"
    "        weather?.corridor == null ||\n"
    "        weather!.corridor!.coverage == RouteCorridorCoverage.full;\n"
    "    final coverage = weather == null\n"
    "        ? RouteScoutCoverage.localOnly\n"
    "        : weather.coverage == RouteWeatherCoverage.full &&\n"
    "              !weather.hasStaleSamples &&\n"
    "              corridorComplete\n"
    "        ? RouteScoutCoverage.full\n"
    "        : RouteScoutCoverage.partial;",
)
replace_once(
    plan,
    "  static void _appendWeather(\n",
    "  static void _appendCorridorRestrictions(\n"
    "    List<RouteScoutNode> nodes,\n"
    "    RouteWeatherReport weather,\n"
    "  ) {\n"
    "    final corridor = weather.corridor;\n"
    "    if (corridor == null) return;\n"
    "    for (var index = 0; index < corridor.segments.length; index += 1) {\n"
    "      final segment = corridor.segments[index];\n"
    "      final restrictions = segment.restrictions;\n"
    "      if (restrictions.status != RouteRestrictionStatus.present ||\n"
    "          !restrictions.authoritative ||\n"
    "          restrictions.kinds.isEmpty) {\n"
    "        continue;\n"
    "      }\n"
    "      final kind = restrictions.kinds.first;\n"
    "      final critical = const {\n"
    "        'closure',\n"
    "        'roadClosure',\n"
    "        'fireRestriction',\n"
    "      }.contains(kind);\n"
    "      final label = _segmentLabel(segment.progress);\n"
    "      nodes.add(\n"
    "        RouteScoutNode(\n"
    "          id: 'restriction-$index-$kind',\n"
    "          kind: RouteScoutNodeKind.safety,\n"
    "          priority: critical\n"
    "              ? RouteScoutPriority.critical\n"
    "              : RouteScoutPriority.high,\n"
    "          title: _restrictionTitle(label, kind),\n"
    "          detail:\n"
    "              '服务端在该路线采样段检出仍有效的官方关闭、管制或限制证据；'\n"
    "              '这里只显示证据状态，不替代官方原文和地图导航。',\n"
    "          routeProgress: segment.progress,\n"
    "          expectedAt: segment.expectedAt,\n"
    "          source: corridor.officialSourceLabel,\n"
    "        ),\n"
    "      );\n"
    "    }\n"
    "  }\n\n"
    "  static String _restrictionTitle(String label, String kind) => switch (kind) {\n"
    "    'closure' || 'roadClosure' => '$label存在官方道路关闭信息',\n"
    "    'fireRestriction' => '$label存在官方防火限制',\n"
    "    'eventChange' => '$label存在官方活动变更',\n"
    "    _ => '$label存在官方通行限制',\n"
    "  };\n\n"
    "  static void _appendWeather(\n",
)

Path('test/features/route/route_corridor_repository_test.dart').write_text(r'''import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/route_corridor_context.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/domain/route_weather.dart';
import 'package:luma_nest/src/features/route/infrastructure/data_broker_route_weather_repository.dart';

void main() {
  test('parses bounded corridor references and authoritative restrictions', () async {
    final repository = DataBrokerRouteWeatherRepository(
      brokerBaseUrl: 'https://broker.example.com',
      serviceToken: 'token',
      transport: _Transport(_response()),
    );

    final report = await repository.fetch(_corridor());

    expect(report.corridor, isNotNull);
    expect(report.corridor!.coverage, RouteCorridorCoverage.full);
    expect(report.corridor!.segments.first.facilities.parking, 2);
    expect(
      report.corridor!.segments.first.restrictions.status,
      RouteRestrictionStatus.present,
    );
    expect(report.corridor!.hasAuthoritativeRestrictions, isTrue);
    expect(report.corridor!.segments.last.restrictions.status,
        RouteRestrictionStatus.noneObserved);
  });

  test('rejects corridor schema expansion with precise coordinates', () async {
    final response = _response();
    final corridor = response['corridor']! as Map<String, Object?>;
    final segments = corridor['segments']! as List<Object?>;
    final first = Map<String, Object?>.from(segments.first! as Map);
    first['latitude'] = 30.25;
    segments[0] = first;
    final repository = DataBrokerRouteWeatherRepository(
      brokerBaseUrl: 'https://broker.example.com',
      serviceToken: 'token',
      transport: _Transport(response),
    );

    expect(() => repository.fetch(_corridor()), throwsFormatException);
  });
}

RouteCorridorContext _corridor() => RouteCorridorContext(
  routeId: 'r1234abcd',
  samples: [
    RouteCorridorSample(
      point: const GeoPoint(latitude: 30.25, longitude: 120.15),
      expectedAt: DateTime.parse('2026-08-05T06:10:00Z'),
      progress: 0,
    ),
    RouteCorridorSample(
      point: const GeoPoint(latitude: 30.5, longitude: 120.5),
      expectedAt: DateTime.parse('2026-08-05T07:10:00Z'),
      progress: 1,
    ),
  ],
);

Map<String, Object?> _response() => {
  'routeId': 'r1234abcd',
  'generatedAt': '2026-08-05T06:00:00Z',
  'source': 'QWeather',
  'coverage': 'full',
  'requestedSamples': 2,
  'availableSamples': 2,
  'samples': [
    {
      'progress': 0,
      'expectedAt': '2026-08-05T06:10:00Z',
      'forecastAt': '2026-08-05T06:00:00Z',
      'condition': 'clear',
      'cloudCoverPercent': 20,
      'windSpeedMps': 2,
      'precipitationMm': 0,
      'visibilityKm': 25,
      'thunder': false,
      'stale': false,
    },
    {
      'progress': 1,
      'expectedAt': '2026-08-05T07:10:00Z',
      'forecastAt': '2026-08-05T07:00:00Z',
      'condition': 'cloudy',
      'cloudCoverPercent': 70,
      'windSpeedMps': 4,
      'precipitationMm': 0,
      'visibilityKm': 18,
      'thunder': false,
      'stale': false,
    },
  ],
  'corridor': <String, Object?>{
    'contractVersion': 1,
    'generatedAt': '2026-08-05T06:00:00Z',
    'coverage': 'full',
    'requestedSegments': 2,
    'availableSegments': 2,
    'sources': [
      {
        'id': 'openstreetmap-overpass',
        'title': 'OpenStreetMap Overpass API',
        'publisher': 'OpenStreetMap contributors',
        'url': 'https://www.openstreetmap.org/copyright',
        'license': 'ODbL-1.0',
        'version': 'Overpass QL',
      },
      {
        'id': 'official-notices',
        'title': 'Official notices',
        'publisher': 'Road authority',
        'url': 'https://example.gov/notices',
        'license': null,
        'version': null,
      },
    ],
    'segments': <Object?>[
      {
        'progress': 0,
        'expectedAt': '2026-08-05T06:10:00Z',
        'facilities': {
          'status': 'reference',
          'parking': 2,
          'fuel': 1,
          'food': 0,
          'water': 1,
          'toilets': 0,
          'shelter': 0,
          'restArea': 0,
        },
        'photography': {
          'status': 'reference',
          'viewpointCount': 1,
          'heritageCount': 0,
        },
        'restrictions': {
          'status': 'present',
          'kinds': ['roadClosure'],
          'authoritative': true,
          'factIds': ['notice-1'],
        },
        'evidence': {
          'status': 'verified',
          'factIds': ['map-1', 'notice-1'],
        },
      },
      {
        'progress': 1,
        'expectedAt': '2026-08-05T07:10:00Z',
        'facilities': {
          'status': 'empty',
          'parking': 0,
          'fuel': 0,
          'food': 0,
          'water': 0,
          'toilets': 0,
          'shelter': 0,
          'restArea': 0,
        },
        'photography': {
          'status': 'noReference',
          'viewpointCount': 0,
          'heritageCount': 0,
        },
        'restrictions': {
          'status': 'noneObserved',
          'kinds': <String>[],
          'authoritative': false,
          'factIds': <String>[],
        },
        'evidence': {
          'status': 'unavailable',
          'factIds': <String>[],
        },
      },
    ],
    'limitations': [
      'public_map_inventory_is_reference_only',
      'absence_of_official_notice_is_not_safety_confirmation',
      'precise_route_geometry_excluded',
    ],
  },
};

class _Transport implements RouteWeatherTransport {
  _Transport(this.response);

  final Map<String, Object?> response;

  @override
  Future<Map<String, Object?>> post(
    String url, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
  }) async => response;
}
''', encoding='utf-8')

plan_test = Path('test/features/route/route_scout_plan_test.dart')
text = plan_test.read_text(encoding='utf-8')
anchor = "\n  test('journey progress is time based and bounded', () {"
if text.count(anchor) != 1:
    raise SystemExit('route scout plan test anchor mismatch')
tests = r'''

  test('authoritative route closure becomes a critical safety node', () {
    final now = DateTime.utc(2026, 8, 5, 6);
    final report = _routeReport(
      now,
      restrictionStatus: RouteRestrictionStatus.present,
      kinds: const ['roadClosure'],
      authoritative: true,
      factIds: const ['notice-1'],
      evidenceStatus: RouteEvidenceStatus.verified,
      evidenceFactIds: const ['notice-1'],
    );
    final plan = RouteScoutPlanBuilder.build(
      routeId: 'r1',
      route: _route(),
      snapshot: _snapshot(now),
      now: now,
      weather: report,
    );

    final node = plan.nodes.singleWhere(
      (item) => item.id.startsWith('restriction-'),
    );
    expect(node.kind, RouteScoutNodeKind.safety);
    expect(node.priority, RouteScoutPriority.critical);
    expect(node.title, contains('官方道路关闭'));
    expect(node.detail, contains('不替代官方原文和地图导航'));
    expect(node.source, 'Road authority');
    expect(plan.headline, contains('官方管制'));
  });

  test('noneObserved restriction state never becomes a safety claim', () {
    final now = DateTime.utc(2026, 8, 5, 6);
    final report = _routeReport(
      now,
      restrictionStatus: RouteRestrictionStatus.noneObserved,
      kinds: const [],
      authoritative: false,
      factIds: const [],
      evidenceStatus: RouteEvidenceStatus.unavailable,
      evidenceFactIds: const [],
    );
    final plan = RouteScoutPlanBuilder.build(
      routeId: 'r1',
      route: _route(),
      snapshot: _snapshot(now),
      now: now,
      weather: report,
    );

    expect(
      plan.nodes.where((item) => item.id.startsWith('restriction-')),
      isEmpty,
    );
    expect(plan.nodes.where((item) => item.kind == RouteScoutNodeKind.safety),
        isEmpty);
  });
'''
plan_test.write_text(text.replace(anchor, tests + anchor) + r'''

DrivingRoute _route() => const DrivingRoute(
  destinationName: '目的地',
  distanceMeters: 50000,
  durationSeconds: 3600,
  tollsYuan: 0,
  polyline: [
    GeoPoint(latitude: 30, longitude: 120),
    GeoPoint(latitude: 30.5, longitude: 120.5),
  ],
);

ContextSnapshot _snapshot(DateTime now) => ContextSnapshot(
  id: 'ctx-route-restriction',
  observedAt: now,
  expiresAt: now.add(const Duration(minutes: 15)),
  primaryScene: SceneType.road,
  dayPhase: DayPhase.day,
  weather: WeatherType.clear,
  activeRoute: true,
);

RouteWeatherReport _routeReport(
  DateTime now, {
  required RouteRestrictionStatus restrictionStatus,
  required List<String> kinds,
  required bool authoritative,
  required List<String> factIds,
  required RouteEvidenceStatus evidenceStatus,
  required List<String> evidenceFactIds,
}) => RouteWeatherReport(
  routeId: 'r1',
  generatedAt: now,
  source: 'QWeather',
  coverage: RouteWeatherCoverage.full,
  requestedSamples: 2,
  availableSamples: 2,
  samples: [
    RouteWeatherSample(
      progress: 0,
      expectedAt: now,
      forecastAt: now,
      condition: RouteWeatherCondition.clear,
      cloudCoverPercent: 10,
      windSpeedMps: 2,
      precipitationMm: 0,
      visibilityKm: 30,
      thunder: false,
      stale: false,
    ),
    RouteWeatherSample(
      progress: 1,
      expectedAt: now.add(const Duration(hours: 1)),
      forecastAt: now.add(const Duration(hours: 1)),
      condition: RouteWeatherCondition.clear,
      cloudCoverPercent: 10,
      windSpeedMps: 2,
      precipitationMm: 0,
      visibilityKm: 30,
      thunder: false,
      stale: false,
    ),
  ],
  corridor: RouteCorridorIntelligence(
    contractVersion: 1,
    generatedAt: now,
    coverage: RouteCorridorCoverage.full,
    requestedSegments: 2,
    availableSegments: 2,
    sources: const [
      RouteCorridorSource(
        id: 'official-notices',
        title: 'Official notices',
        publisher: 'Road authority',
        url: 'https://example.gov/notices',
      ),
    ],
    segments: [
      RouteCorridorSegment(
        progress: .5,
        expectedAt: now.add(const Duration(minutes: 30)),
        facilities: const RouteCorridorFacilities(
          status: RouteCorridorReferenceStatus.empty,
          parking: 0,
          fuel: 0,
          food: 0,
          water: 0,
          toilets: 0,
          shelter: 0,
          restArea: 0,
        ),
        photography: const RouteCorridorPhotography(
          status: RouteCorridorReferenceStatus.noReference,
          viewpointCount: 0,
          heritageCount: 0,
        ),
        restrictions: RouteCorridorRestrictions(
          status: restrictionStatus,
          kinds: kinds,
          authoritative: authoritative,
          factIds: factIds,
        ),
        evidence: RouteCorridorEvidence(
          status: evidenceStatus,
          factIds: evidenceFactIds,
        ),
      ),
      RouteCorridorSegment(
        progress: 1,
        expectedAt: now.add(const Duration(hours: 1)),
        facilities: const RouteCorridorFacilities(
          status: RouteCorridorReferenceStatus.unavailable,
          parking: 0,
          fuel: 0,
          food: 0,
          water: 0,
          toilets: 0,
          shelter: 0,
          restArea: 0,
        ),
        photography: const RouteCorridorPhotography(
          status: RouteCorridorReferenceStatus.unavailable,
          viewpointCount: 0,
          heritageCount: 0,
        ),
        restrictions: RouteCorridorRestrictions(
          status: RouteRestrictionStatus.unavailable,
          kinds: const [],
          authoritative: false,
          factIds: const [],
        ),
        evidence: RouteCorridorEvidence(
          status: RouteEvidenceStatus.unavailable,
          factIds: const [],
        ),
      ),
    ],
    limitations: const [
      'absence_of_official_notice_is_not_safety_confirmation',
    ],
  ),
);
''', encoding='utf-8')
