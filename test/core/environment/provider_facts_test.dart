import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/environment/provider_facts.dart';

void main() {
  final instant = DateTime.utc(2026, 8, 3, 8);

  test('parses bounded provider facts and orders stronger evidence first', () {
    final bundle = ProviderFactsBundle.fromJson(_fixture());

    expect(bundle.providers, hasLength(3));
    expect(bundle.status, ProviderBundleStatus.partial);
    expect(bundle.providers[1].status, ProviderStatus.unconfigured);
    final signals = bundle.displayableSignalsAt(instant);
    expect(signals.map((item) => item.title), ['官方关闭公告', '近期光学观测']);
    expect(bundle.requestedCoordinate.latitude, 30.25);
  });

  test('expired signals do not become visible', () {
    final body = _fixture();
    final providers = body['providers']! as List<Object?>;
    final first = Map<String, Object?>.from(providers.first! as Map);
    final signals = List<Object?>.from(first['signals']! as List);
    final signal = Map<String, Object?>.from(signals.first! as Map);
    signal['expiresAt'] = '2026-08-03T07:00:00Z';
    signal['observedAt'] = '2026-08-03T06:00:00Z';
    first['signals'] = [signal];
    providers[0] = first;
    body['providers'] = providers;

    final bundle = ProviderFactsBundle.fromJson(body);
    expect(bundle.displayableSignalsAt(instant).map((item) => item.title), [
      '官方关闭公告',
    ]);
  });

  test('rejects ready provider without traceable evidence', () {
    final body = _fixture();
    final providers = body['providers']! as List<Object?>;
    final first = Map<String, Object?>.from(providers.first! as Map);
    first['source'] = null;
    providers[0] = first;
    body['providers'] = providers;

    expect(() => ProviderFactsBundle.fromJson(body), throwsFormatException);
  });
}

Map<String, Object?> _fixture() => {
  'contractVersion': 1,
  'requestedCoordinate': {
    'latitude': 30.25,
    'longitude': 120.15,
    'system': 'wgs84',
  },
  'radiusKm': 25,
  'generatedAt': '2026-08-03T08:00:00Z',
  'expiresAt': '2026-08-03T08:30:00Z',
  'status': 'partial',
  'cacheStatus': 'miss',
  'providers': [
    {
      'id': 'sentinel2',
      'category': 'surface',
      'status': 'ready',
      'observedAt': '2026-08-03T08:00:00Z',
      'expiresAt': '2026-08-03T20:00:00Z',
      'source': {
        'id': 'copernicus-sentinel2',
        'title': 'Sentinel-2 catalogue',
        'publisher': 'Copernicus',
        'url': 'https://dataspace.copernicus.eu/',
        'license': 'Copernicus licence',
        'version': 'STAC 1.1',
      },
      'signals': [
        {
          'id': 'signal_111111111111111111111111',
          'kind': 'opticalAcquisition',
          'category': 'surface',
          'title': '近期光学观测',
          'summary': '最近卫星目录存在可用影像，地表结论仍需栅格分析。',
          'verification': 'observed',
          'observedAt': '2026-08-03T07:00:00Z',
          'expiresAt': '2026-08-04T07:00:00Z',
          'sourceUrl': 'https://dataspace.copernicus.eu/',
        },
      ],
      'message': null,
    },
    {
      'id': 'cams',
      'category': 'atmosphere',
      'status': 'unconfigured',
      'observedAt': '2026-08-03T08:00:00Z',
      'expiresAt': '2026-08-03T08:30:00Z',
      'source': null,
      'signals': <Object?>[],
      'message': '需要服务端配置',
    },
    {
      'id': 'officialNotices',
      'category': 'operations',
      'status': 'ready',
      'observedAt': '2026-08-03T08:00:00Z',
      'expiresAt': '2026-08-03T08:30:00Z',
      'source': {
        'id': 'official-notice-gateway',
        'title': 'Reviewed notices',
        'publisher': '地方政府',
        'url': 'https://www.gov.cn/',
        'license': 'Source-specific',
        'version': 'v1',
      },
      'signals': [
        {
          'id': 'signal_222222222222222222222222',
          'kind': 'closure',
          'category': 'operations',
          'title': '官方关闭公告',
          'summary': '景区发布临时关闭通知，以原始公告有效期为准。',
          'verification': 'authoritative',
          'observedAt': '2026-08-03T07:30:00Z',
          'expiresAt': '2026-08-03T18:00:00Z',
          'sourceUrl': 'https://www.gov.cn/',
        },
      ],
      'message': null,
    },
  ],
};
