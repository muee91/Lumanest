import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_distance.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';

abstract interface class LocationSearchTransport {
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  });
}

class DioLocationSearchTransport implements LocationSearchTransport {
  DioLocationSearchTransport(this._dio);

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
      throw const LocationSearchFailure(LocationSearchFailureKind.response);
    } on LocationSearchFailure {
      rethrow;
    } on DioException {
      throw const LocationSearchFailure(LocationSearchFailureKind.network);
    }
  }
}

class AmapLocationSearchRepository implements LocationSearchRepository {
  const AmapLocationSearchRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final LocationSearchTransport transport;

  @override
  Future<List<LocationSearchResult>> search(
    String keywords, {
    GeoPoint? center,
  }) async {
    final query = keywords.trim();
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const LocationSearchFailure(
        LocationSearchFailureKind.configuration,
      );
    }
    if (query.isEmpty) return const [];
    final headers = {'Authorization': 'Bearer $serviceToken'};
    if (center == null) {
      final attempt = await _attempt('/v1/amap/search', {
        'keywords': query,
        'offset': '10',
      }, headers);
      if (attempt.failure case final failure?) throw failure;
      return attempt.results;
    }

    final mapCenter = center.coordinateSystem == CoordinateSystem.wgs84
        ? ChinaCoordinateConverter.wgs84ToGcj02(center)
        : center;
    final attempts = await Future.wait([
      _attempt(
        '/v1/amap/nearby',
        {
          'location': '${mapCenter.longitude},${mapCenter.latitude}',
          'keywords': query,
          'radius': '50000',
          'offset': '25',
        },
        headers,
        center: mapCenter,
      ),
      _attempt(
        '/v1/amap/search',
        {'keywords': query, 'offset': '10'},
        headers,
        center: mapCenter,
      ),
    ]);
    if (attempts.every((attempt) => attempt.failure != null)) {
      throw attempts.first.failure!;
    }

    final ranked = <_RankedLocation>[];
    final seen = <String>{};
    var ordinal = 0;
    for (final result in attempts.first.results.take(8)) {
      if (seen.add(_deduplicationKey(result))) {
        ranked.add(_RankedLocation(result, ordinal++));
      }
    }
    for (final result in attempts.last.results) {
      if (seen.add(_deduplicationKey(result))) {
        ranked.add(_RankedLocation(result, ordinal++));
      }
    }
    ranked.sort((first, second) {
      final tierOrder = first.distanceTier.compareTo(second.distanceTier);
      return tierOrder != 0
          ? tierOrder
          : first.ordinal.compareTo(second.ordinal);
    });
    return ranked.take(18).map((item) => item.result).toList(growable: false);
  }

  Future<_SearchAttempt> _attempt(
    String path,
    Map<String, String> query,
    Map<String, String> headers, {
    GeoPoint? center,
  }) async {
    try {
      final body = await transport.get(
        '$brokerBaseUrl$path',
        query: query,
        headers: headers,
      );
      if (body['status'] != '1' || body['pois'] is! List) {
        return const _SearchAttempt.failure(
          LocationSearchFailure(LocationSearchFailureKind.response),
        );
      }
      final results = (body['pois'] as List)
          .whereType<Map>()
          .map((raw) => _parse(Map<String, Object?>.from(raw), center: center))
          .whereType<LocationSearchResult>()
          .toList(growable: false);
      return _SearchAttempt.success(results);
    } on LocationSearchFailure catch (failure) {
      return _SearchAttempt.failure(failure);
    }
  }

  LocationSearchResult? _parse(Map<String, Object?> raw, {GeoPoint? center}) {
    final name = raw['name'];
    final location = raw['location'];
    if (name is! String || name.isEmpty || location is! String) return null;
    final values = location.split(',');
    if (values.length != 2) return null;
    final longitude = double.tryParse(values[0]);
    final latitude = double.tryParse(values[1]);
    if (longitude == null || latitude == null) return null;
    final point = GeoPoint(
      latitude: latitude,
      longitude: longitude,
      coordinateSystem: CoordinateSystem.gcj02,
    ).validate();
    return LocationSearchResult(
      id: raw['id'] is String && (raw['id'] as String).isNotEmpty
          ? raw['id'] as String
          : '$name@$location',
      name: name,
      point: point,
      address: raw['address'] is String && (raw['address'] as String).isNotEmpty
          ? raw['address'] as String
          : null,
      distanceMeters: center == null
          ? null
          : GeoDistance.metersBetween(center, point).round(),
    );
  }

  static String _deduplicationKey(LocationSearchResult result) =>
      '${result.name.trim().toLowerCase()}@${result.point.latitude.toStringAsFixed(5)},${result.point.longitude.toStringAsFixed(5)}';
}

class _SearchAttempt {
  const _SearchAttempt.success(this.results) : failure = null;

  const _SearchAttempt.failure(this.failure) : results = const [];

  final List<LocationSearchResult> results;
  final LocationSearchFailure? failure;
}

class _RankedLocation {
  const _RankedLocation(this.result, this.ordinal);

  final LocationSearchResult result;
  final int ordinal;

  int get distanceTier {
    final distance = result.distanceMeters;
    if (distance == null) return 3;
    if (distance <= 50000) return 0;
    if (distance <= 300000) return 1;
    return 2;
  }
}
