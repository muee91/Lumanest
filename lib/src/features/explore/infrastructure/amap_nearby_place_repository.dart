import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_distance.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place_repository.dart';

abstract interface class AmapDataTransport {
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  });
}

class DioAmapDataTransport implements AmapDataTransport {
  DioAmapDataTransport(this._dio);

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
      throw const NearbyPlaceFailure(NearbyPlaceFailureKind.response);
    } on NearbyPlaceFailure {
      rethrow;
    } on DioException {
      throw const NearbyPlaceFailure(NearbyPlaceFailureKind.network);
    }
  }
}

class AmapNearbyPlaceRepository implements NearbyPlaceRepository {
  const AmapNearbyPlaceRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final AmapDataTransport transport;

  @override
  Future<List<NearbyPlace>> fetchNearby({
    required GeoPoint center,
    required NearbyPlaceCategory category,
    int radiusMeters = 5000,
  }) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const NearbyPlaceFailure(NearbyPlaceFailureKind.configuration);
    }
    final mapCenter = center.coordinateSystem == CoordinateSystem.wgs84
        ? ChinaCoordinateConverter.wgs84ToGcj02(center)
        : center;
    final boundedRadius = radiusMeters.clamp(100, 50000);
    final candidateMode =
        category == NearbyPlaceCategory.sunriseCandidate ||
        category == NearbyPlaceCategory.nightSkyCandidate;
    final administration = candidateMode
        ? await _originAdministration(mapCenter)
        : null;
    final attempts =
        <({String keyword, Map<String, Object?>? body, Object? error})>[];
    for (var index = 0; index < category.searchKeywords.length; index += 2) {
      final batch = category.searchKeywords.skip(index).take(2);
      attempts.addAll(
        await Future.wait(
          batch.map((keyword) async {
            try {
              final body = await transport.get(
                '$brokerBaseUrl/v1/amap/nearby',
                query: {
                  'location': '${mapCenter.longitude},${mapCenter.latitude}',
                  'keywords': keyword,
                  'radius': boundedRadius.toString(),
                  'offset': category.searchKeywords.length == 1 ? '25' : '12',
                },
                headers: {'Authorization': 'Bearer $serviceToken'},
              );
              return (keyword: keyword, body: body, error: null as Object?);
            } on Object catch (error) {
              return (
                keyword: keyword,
                body: null as Map<String, Object?>?,
                error: error,
              );
            }
          }),
        ),
      );
      if (index + 2 < category.searchKeywords.length) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    final responses = attempts
        .map((attempt) => attempt.body)
        .whereType<Map<String, Object?>>()
        .where((body) => body['status'] == '1' && body['pois'] is List)
        .toList(growable: false);
    final lastError = attempts
        .map((attempt) => attempt.error)
        .whereType<Object>()
        .lastOrNull;
    if (responses.isEmpty) {
      if (lastError case final NearbyPlaceFailure failure) throw failure;
      throw const NearbyPlaceFailure(NearbyPlaceFailureKind.response);
    }

    final byId = <String, NearbyPlace>{};
    for (final attempt in attempts) {
      final body = attempt.body;
      if (body == null || body['status'] != '1' || body['pois'] is! List) {
        continue;
      }
      for (final raw in (body['pois'] as List).whereType<Map>()) {
        final place = _parsePlace(
          Map<String, Object?>.from(raw),
          category,
          center: mapCenter,
          radiusMeters: boundedRadius,
          matchedKeyword: attempt.keyword,
          originAdministration: administration,
        );
        if (place != null) byId.putIfAbsent(place.id, () => place);
      }
    }
    final places = byId.values.toList();
    places.sort(
      (first, second) => first.distanceMeters.compareTo(second.distanceMeters),
    );
    return List.unmodifiable(places);
  }

  NearbyPlace? _parsePlace(
    Map<String, Object?> raw,
    NearbyPlaceCategory category, {
    required GeoPoint center,
    required int radiusMeters,
    String? matchedKeyword,
    _Administration? originAdministration,
  }) {
    final name = raw['name'];
    final location = raw['location'];
    if (name is! String || name.isEmpty || location is! String) return null;
    final parts = location.split(',');
    if (parts.length != 2) return null;
    final longitude = double.tryParse(parts[0]);
    final latitude = double.tryParse(parts[1]);
    if (longitude == null || latitude == null) return null;
    final point = GeoPoint(
      latitude: latitude,
      longitude: longitude,
      coordinateSystem: CoordinateSystem.gcj02,
    ).validate();
    final distance = GeoDistance.metersBetween(center, point).round();
    if (distance > radiusMeters + 250) return null;
    if (!_supportsCreativeCandidate(raw, category)) return null;
    final id = raw['id'] is String && (raw['id'] as String).isNotEmpty
        ? raw['id'] as String
        : '$name@$location';
    final address = raw['address'];
    final provinceName = _text(raw['pname']);
    final cityName = _text(raw['cityname']);
    final districtName = _text(raw['adname']);
    final media = raw['media'] is List
        ? (raw['media'] as List)
              .whereType<Map>()
              .map((item) => _parseMedia(Map<String, Object?>.from(item)))
              .whereType<NearbyPlaceMedia>()
              .take(3)
              .toList(growable: false)
        : const <NearbyPlaceMedia>[];
    return NearbyPlace(
      id: id,
      name: name,
      category: category,
      point: point,
      distanceMeters: distance,
      address: address is String && address.isNotEmpty ? address : null,
      providerType: _text(raw['type']),
      provinceName: provinceName,
      cityName: cityName,
      districtName: districtName,
      matchedKeyword: matchedKeyword,
      media: List.unmodifiable(media),
      administrativeRelation: _relation(
        originAdministration,
        cityName: cityName,
        districtName: districtName,
      ),
    );
  }

  NearbyPlaceMedia? _parseMedia(Map<String, Object?> raw) {
    final id = raw['id'];
    final proxyPath = raw['proxyPath'];
    final attribution = _text(raw['attribution']);
    if (id is! String ||
        !RegExp(r'^[a-f0-9]{24}$').hasMatch(id) ||
        proxyPath is! String ||
        !RegExp(
          r'^/v1/amap/media/[A-Za-z0-9_-]{16,1800}$',
        ).hasMatch(proxyPath) ||
        attribution == null) {
      return null;
    }
    final base = Uri.tryParse(brokerBaseUrl);
    if (base == null || !base.hasScheme || base.host.isEmpty) return null;
    final url = base.resolve(proxyPath);
    if (url.scheme != 'https' && url.scheme != 'http') return null;
    return NearbyPlaceMedia(
      id: id,
      url: url.toString(),
      attribution: attribution,
      title: _text(raw['title']),
    );
  }

  Future<_Administration?> _originAdministration(GeoPoint center) async {
    try {
      final body = await transport.get(
        '$brokerBaseUrl/v1/amap/scene-evidence',
        query: {'location': '${center.longitude},${center.latitude}'},
        headers: {'Authorization': 'Bearer $serviceToken'},
      );
      final regeocode = body['regeocode'];
      if (body['status'] != '1' || regeocode is! Map) return null;
      final address = regeocode['addressComponent'];
      if (address is! Map) return null;
      return _Administration(
        cityName: _text(address['city']) ?? _text(address['province']),
        districtName: _text(address['district']),
      );
    } on Object {
      return null;
    }
  }

  static bool _supportsCreativeCandidate(
    Map<String, Object?> raw,
    NearbyPlaceCategory category,
  ) {
    final name = _text(raw['name']) ?? '';
    final type = _text(raw['type']);
    if (category == NearbyPlaceCategory.humanity) {
      return NearbyPlace.hasHumanityEvidenceFor(name: name, providerType: type);
    }
    if (category != NearbyPlaceCategory.sunriseCandidate &&
        category != NearbyPlaceCategory.nightSkyCandidate) {
      return true;
    }
    if (RegExp(
      r'公交站|停车场|酒店|公寓|足道|派出所|售票处|游客中心|不对外开放|暂停营业|停止开放|临时关闭',
    ).hasMatch(name)) {
      return false;
    }
    if (type == null) return true;
    return RegExp(r'风景名胜|公园广场|体育休闲服务|自然地物|水系').hasMatch(type);
  }

  static NearbyAdministrativeRelation _relation(
    _Administration? origin, {
    required String? cityName,
    required String? districtName,
  }) {
    if (origin == null) return NearbyAdministrativeRelation.unknown;
    if (origin.districtName != null &&
        districtName != null &&
        origin.districtName == districtName) {
      return NearbyAdministrativeRelation.sameDistrict;
    }
    if (origin.cityName != null &&
        cityName != null &&
        origin.cityName == cityName) {
      return NearbyAdministrativeRelation.sameCity;
    }
    if (cityName != null || districtName != null) {
      return NearbyAdministrativeRelation.nearbyRegion;
    }
    return NearbyAdministrativeRelation.unknown;
  }

  static String? _text(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is List && value.length == 1 && value.single is String) {
      return _text(value.single);
    }
    return null;
  }
}

class _Administration {
  const _Administration({required this.cityName, required this.districtName});

  final String? cityName;
  final String? districtName;
}
