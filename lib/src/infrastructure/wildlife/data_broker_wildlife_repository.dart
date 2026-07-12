import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_observation.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_repository.dart';

abstract interface class WildlifeDataTransport {
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  });
}

class DioWildlifeDataTransport implements WildlifeDataTransport {
  DioWildlifeDataTransport(this._dio);

  final Dio _dio;

  @override
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  }) async {
    try {
      final response = await _dio.get<Object?>(
        url,
        queryParameters: query,
        options: Options(headers: headers),
      );
      if (response.data case final Map body) {
        return Map<String, Object?>.from(body);
      }
      throw const WildlifeFailure(WildlifeFailureKind.response);
    } on WildlifeFailure {
      rethrow;
    } on DioException {
      throw const WildlifeFailure(WildlifeFailureKind.network);
    }
  }
}

class DataBrokerWildlifeRepository implements WildlifeRepository {
  const DataBrokerWildlifeRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final WildlifeDataTransport transport;

  @override
  Future<RegionalWildlifeActivity> fetchRegionalWildlifeActivity(
    GeoPoint location,
  ) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const WildlifeFailure(WildlifeFailureKind.configuration);
    }
    location.validate();
    final body = await transport.get(
      '$brokerBaseUrl/v1/wildlife/nearby',
      query: {
        'location': '${location.longitude},${location.latitude}',
        'radiusKm': '20',
      },
      headers: {'Authorization': 'Bearer $serviceToken'},
    );
    if (body['source'] != 'GBIF' || body['taxa'] is! List) {
      throw const WildlifeFailure(WildlifeFailureKind.response);
    }
    final taxa = (body['taxa'] as List)
        .whereType<Map>()
        .map((raw) => Map<String, Object?>.from(raw))
        .map(_parseTaxon)
        .whereType<WildlifeTaxon>()
        .toList(growable: false);
    return RegionalWildlifeActivity(
      radiusKilometers: int.tryParse('${body['radiusKm'] ?? ''}') ?? 20,
      occurrenceSampleSize:
          int.tryParse('${body['occurrenceSampleSize'] ?? ''}') ?? 0,
      taxa: taxa,
    );
  }

  WildlifeTaxon? _parseTaxon(Map<String, Object?> raw) {
    final scientificName = raw['scientificName'];
    if (scientificName is! String || scientificName.isEmpty) return null;
    return WildlifeTaxon(
      scientificName: scientificName,
      group: _parseGroup(raw['animalClass']),
      commonName: raw['commonName'] is String
          ? raw['commonName'] as String
          : null,
      records: int.tryParse('${raw['records'] ?? ''}') ?? 0,
    );
  }

  WildlifeGroup _parseGroup(Object? raw) {
    return switch (raw) {
      'bird' => WildlifeGroup.bird,
      'mammal' => WildlifeGroup.mammal,
      'reptile' => WildlifeGroup.reptile,
      'amphibian' => WildlifeGroup.amphibian,
      'insect' => WildlifeGroup.insect,
      _ => WildlifeGroup.other,
    };
  }
}
