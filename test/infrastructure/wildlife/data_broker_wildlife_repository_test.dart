import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_observation.dart';
import 'package:luma_nest/src/infrastructure/wildlife/data_broker_wildlife_repository.dart';

void main() {
  test('parses regional wildlife groups from the NAS broker', () async {
    final transport = _FakeTransport({
      'source': 'GBIF',
      'scope': 'regional_wildlife_observations',
      'radiusKm': 20,
      'occurrenceSampleSize': 3,
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
