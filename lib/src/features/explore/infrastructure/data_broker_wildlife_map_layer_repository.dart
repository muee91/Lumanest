import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer_repository.dart';

abstract interface class WildlifeMapLayerTransport {
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  });
}

class DioWildlifeMapLayerTransport implements WildlifeMapLayerTransport {
  DioWildlifeMapLayerTransport(this._dio);

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
      throw const WildlifeMapLayerFailure(WildlifeMapLayerFailureKind.response);
    } on WildlifeMapLayerFailure {
      rethrow;
    } on DioException {
      throw const WildlifeMapLayerFailure(WildlifeMapLayerFailureKind.network);
    }
  }
}

class DataBrokerWildlifeMapLayerRepository
    implements WildlifeMapLayerRepository {
  const DataBrokerWildlifeMapLayerRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final WildlifeMapLayerTransport transport;

  @override
  Future<WildlifeMapLayer> fetch({
    required GeoPoint center,
    int radiusKilometers = 20,
  }) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const WildlifeMapLayerFailure(
        WildlifeMapLayerFailureKind.configuration,
      );
    }
    center.validate();
    if (center.coordinateSystem != CoordinateSystem.wgs84 ||
        radiusKilometers < 5 ||
        radiusKilometers > 50) {
      throw const WildlifeMapLayerFailure(WildlifeMapLayerFailureKind.response);
    }
    final body = await transport.get(
      '$brokerBaseUrl/v1/wildlife/layers',
      query: {
        'location': '${center.longitude},${center.latitude}',
        'radiusKm': '$radiusKilometers',
      },
      headers: {'Authorization': 'Bearer $serviceToken'},
    );
    return _parse(body, expectedRadius: radiusKilometers);
  }

  WildlifeMapLayer _parse(
    Map<String, Object?> body, {
    required int expectedRadius,
  }) {
    if (!_hasExactKeys(body, const {
          'contractVersion',
          'generatedAt',
          'radiusKm',
          'areas',
        }) ||
        body['contractVersion'] != 1 ||
        body['radiusKm'] != expectedRadius ||
        body['areas'] is! List ||
        (body['areas']! as List).length > 50) {
      throw const WildlifeMapLayerFailure(WildlifeMapLayerFailureKind.response);
    }
    final generatedAt = DateTime.tryParse('${body['generatedAt'] ?? ''}');
    if (generatedAt == null) {
      throw const WildlifeMapLayerFailure(WildlifeMapLayerFailureKind.response);
    }
    var pointCount = 0;
    final areas = <WildlifeMapArea>[];
    for (final raw in body['areas']! as List) {
      if (raw is! Map) {
        throw const WildlifeMapLayerFailure(
          WildlifeMapLayerFailureKind.response,
        );
      }
      final value = Map<String, Object?>.from(raw);
      if (!_hasExactKeys(value, const {'id', 'name', 'geometry', 'source'}) ||
          value['id'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['id']! as String) ||
          value['name'] is! String ||
          (value['name']! as String).trim().isEmpty ||
          (value['name']! as String).runes.length > 200 ||
          value['geometry'] is! Map ||
          value['source'] is! Map) {
        throw const WildlifeMapLayerFailure(
          WildlifeMapLayerFailureKind.response,
        );
      }
      final polygons = _parseGeometry(
        Map<String, Object?>.from(value['geometry']! as Map),
      );
      pointCount += polygons.fold(0, (total, ring) => total + ring.length);
      if (pointCount > 5000) {
        throw const WildlifeMapLayerFailure(
          WildlifeMapLayerFailureKind.response,
        );
      }
      final source = Map<String, Object?>.from(value['source']! as Map);
      if (!_hasExactKeys(source, const {
            'attribution',
            'version',
            'updatedAt',
          }) ||
          source['attribution'] is! String ||
          (source['attribution']! as String).trim().isEmpty ||
          source['version'] is! String ||
          (source['version']! as String).trim().isEmpty) {
        throw const WildlifeMapLayerFailure(
          WildlifeMapLayerFailureKind.response,
        );
      }
      final updatedAt = source['updatedAt'] == null
          ? null
          : DateTime.tryParse('${source['updatedAt']}');
      if (source['updatedAt'] != null && updatedAt == null) {
        throw const WildlifeMapLayerFailure(
          WildlifeMapLayerFailureKind.response,
        );
      }
      areas.add(
        WildlifeMapArea(
          id: value['id']! as String,
          name: (value['name']! as String).trim(),
          polygons: polygons,
          source: WildlifeMapAreaSource(
            attribution: (source['attribution']! as String).trim(),
            version: (source['version']! as String).trim(),
            updatedAt: updatedAt?.toUtc(),
          ),
        ),
      );
    }
    return WildlifeMapLayer(
      generatedAt: generatedAt.toUtc(),
      radiusKilometers: expectedRadius,
      areas: areas,
    );
  }

  List<List<GeoPoint>> _parseGeometry(Map<String, Object?> geometry) {
    if (!_hasExactKeys(geometry, const {'type', 'coordinates'}) ||
        geometry['coordinates'] is! List) {
      throw const WildlifeMapLayerFailure(WildlifeMapLayerFailureKind.response);
    }
    final coordinates = geometry['coordinates']! as List;
    final polygons = switch (geometry['type']) {
      'Polygon' => [_parsePolygon(coordinates)],
      'MultiPolygon' =>
        coordinates
            .map((polygon) {
              if (polygon is! List) {
                throw const WildlifeMapLayerFailure(
                  WildlifeMapLayerFailureKind.response,
                );
              }
              return _parsePolygon(polygon);
            })
            .toList(growable: false),
      _ => throw const WildlifeMapLayerFailure(
        WildlifeMapLayerFailureKind.response,
      ),
    };
    return polygons;
  }

  List<GeoPoint> _parsePolygon(List<Object?> rings) {
    if (rings.isEmpty || rings.first is! List) {
      throw const WildlifeMapLayerFailure(WildlifeMapLayerFailureKind.response);
    }
    for (final ring in rings) {
      if (ring is! List) {
        throw const WildlifeMapLayerFailure(
          WildlifeMapLayerFailureKind.response,
        );
      }
      _validateRing(ring);
    }
    return _validateRing(rings.first! as List);
  }

  List<GeoPoint> _validateRing(List<Object?> positions) {
    if (positions.length < 4) {
      throw const WildlifeMapLayerFailure(WildlifeMapLayerFailureKind.response);
    }
    final points = positions
        .map((raw) {
          if (raw is! List ||
              raw.length < 2 ||
              raw[0] is! num ||
              raw[1] is! num) {
            throw const WildlifeMapLayerFailure(
              WildlifeMapLayerFailureKind.response,
            );
          }
          final longitude = (raw[0]! as num).toDouble();
          final latitude = (raw[1]! as num).toDouble();
          if (!longitude.isFinite ||
              !latitude.isFinite ||
              longitude < -180 ||
              longitude > 180 ||
              latitude < -90 ||
              latitude > 90) {
            throw const WildlifeMapLayerFailure(
              WildlifeMapLayerFailureKind.response,
            );
          }
          return GeoPoint(latitude: latitude, longitude: longitude);
        })
        .toList(growable: false);
    final first = points.first;
    final last = points.last;
    if (first.latitude != last.latitude || first.longitude != last.longitude) {
      throw const WildlifeMapLayerFailure(WildlifeMapLayerFailureKind.response);
    }
    return points;
  }

  bool _hasExactKeys(Map<String, Object?> value, Set<String> keys) =>
      value.length == keys.length && value.keys.every(keys.contains);
}
