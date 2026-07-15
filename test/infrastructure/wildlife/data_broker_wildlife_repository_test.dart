import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_observation.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_repository.dart';
import 'package:luma_nest/src/infrastructure/wildlife/data_broker_wildlife_repository.dart';

void main() {
  test('parses regional wildlife groups from the NAS broker', () async {
    final transport = _FakeTransport({
      'contractVersion': 2,
      'source': 'GBIF',
      'scope': 'regional_wildlife_observations',
      'radiusKm': 20,
      'scannedOccurrenceSampleSize': 5,
      'eligibleOccurrenceSampleSize': 3,
      'occurrenceSampleSize': 3,
      'datasetReferencesTruncated': false,
      'qualityPolicy': {
        'acceptedLicenses': ['CC0-1.0', 'CC-BY-4.0'],
        'acceptedBasisOfRecord': ['HUMAN_OBSERVATION'],
        'maximumCoordinateUncertaintyMeters': 10000,
        'maximumDatasetReferences': 8,
        'excludesSevereGeospatialIssues': true,
      },
      'historicalRecordConcentration': {
        'recordsWithMonth': 3,
        'recordsWithTime': 2,
        'months': [
          {'month': 5, 'records': 2},
        ],
        'timePeriods': [
          {'period': 'dawn', 'records': 2},
        ],
      },
      'datasets': [
        {
          'datasetKey': '11111111-1111-4111-8111-111111111111',
          'title': 'Regional observations',
          'publisher': 'Open Nature Lab',
          'licenses': ['CC-BY-4.0'],
          'records': 3,
          'citation': 'Open Nature Lab (2026). Regional observations.',
          'url':
              'https://www.gbif.org/dataset/11111111-1111-4111-8111-111111111111',
        },
      ],
      'taxa': [
        {
          'scientificName': 'Passer montanus',
          'animalClass': 'bird',
          'records': 2,
        },
        {
          'scientificName': 'Lutra lutra',
          'animalClass': 'mammal',
          'records': 1,
        },
      ],
    });
    final repository = DataBrokerWildlifeRepository(
      brokerBaseUrl: 'https://broker.example.com',
      serviceToken: 'service-token',
      transport: transport,
    );

    final activity = await repository.fetchRegionalWildlifeActivity(
      const GeoPoint(latitude: 31.2304, longitude: 121.4737),
    );

    expect(transport.url, 'https://broker.example.com/v1/wildlife/nearby');
    expect(transport.headers['Authorization'], 'Bearer service-token');
    expect(activity.taxa.map((taxon) => taxon.group), [
      WildlifeGroup.bird,
      WildlifeGroup.mammal,
    ]);
    expect(activity.contractVersion, 2);
    expect(activity.scannedOccurrenceSampleSize, 5);
    expect(activity.eligibleOccurrenceSampleSize, 3);
    expect(activity.datasetReferencesTruncated, isFalse);
    expect(activity.qualityPolicy?.acceptedLicenses, ['CC0-1.0', 'CC-BY-4.0']);
    expect(activity.historicalRecordConcentration?.summary, '5月 · 晨间');
    expect(activity.datasets.single.publisher, 'Open Nature Lab');
    expect(activity.datasets.single.url.host, 'www.gbif.org');
  });

  test('rejects incomplete v2 production metadata', () async {
    final repository = DataBrokerWildlifeRepository(
      brokerBaseUrl: 'https://broker.example.com',
      serviceToken: 'service-token',
      transport: _FakeTransport({
        'contractVersion': 2,
        'source': 'GBIF',
        'taxa': const [],
      }),
    );

    await expectLater(
      repository.fetchRegionalWildlifeActivity(
        const GeoPoint(latitude: 31.2304, longitude: 121.4737),
      ),
      throwsA(
        isA<WildlifeFailure>().having(
          (failure) => failure.kind,
          'kind',
          WildlifeFailureKind.response,
        ),
      ),
    );
  });
}

class _FakeTransport implements WildlifeDataTransport {
  _FakeTransport(this.response);

  final Map<String, Object?> response;
  late String url;
  late Map<String, String> headers;

  @override
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  }) async {
    this.url = url;
    this.headers = headers;
    return response;
  }
}
