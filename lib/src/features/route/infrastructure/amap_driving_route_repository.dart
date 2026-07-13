import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';

abstract interface class AmapRouteTransport {
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  });
}

class DioAmapRouteTransport implements AmapRouteTransport {
  DioAmapRouteTransport(this._dio);

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
      throw const DrivingRouteFailure(DrivingRouteFailureKind.response);
    } on DrivingRouteFailure {
      rethrow;
    } on DioException {
      throw const DrivingRouteFailure(DrivingRouteFailureKind.network);
    }
  }
}

class AmapDrivingRouteRepository implements DrivingRouteRepository {
  const AmapDrivingRouteRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final AmapRouteTransport transport;

  @override
  Future<DrivingRoute> plan(DrivingRouteRequest request) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const DrivingRouteFailure(DrivingRouteFailureKind.configuration);
    }
    final origin = ChinaCoordinateConverter.wgs84ToGcj02(request.origin);
    final destination =
        request.destination.coordinateSystem == CoordinateSystem.wgs84
        ? ChinaCoordinateConverter.wgs84ToGcj02(request.destination)
        : request.destination;
    final body = await transport.get(
      '$brokerBaseUrl/v1/amap/${request.travelMode.name}',
      query: {
        'origin': '${origin.longitude},${origin.latitude}',
        'destination': '${destination.longitude},${destination.latitude}',
      },
      headers: {'Authorization': 'Bearer $serviceToken'},
    );
    final route = body['route'];
    if (body['status'] != '1' || route is! Map) {
      throw const DrivingRouteFailure(DrivingRouteFailureKind.response);
    }
    final paths = route['paths'];
    if (paths is! List || paths.isEmpty || paths.first is! Map) {
      throw const DrivingRouteFailure(DrivingRouteFailureKind.response);
    }
    final path = Map<String, Object?>.from(paths.first as Map);
    final steps = path['steps'] is List
        ? (path['steps'] as List).whereType<Map>().toList(growable: false)
        : const <Map>[];
    final points = <GeoPoint>[];
    final instructions = <String>[];
    for (final rawStep in steps) {
      final step = Map<String, Object?>.from(rawStep);
      if (step['instruction'] case final String instruction
          when instruction.isNotEmpty) {
        instructions.add(instruction);
      }
      if (step['polyline'] case final String polyline) {
        points.addAll(_parsePolyline(polyline));
      }
    }
    return DrivingRoute(
      destinationName: request.destinationName,
      distanceMeters: int.tryParse('${path['distance'] ?? ''}') ?? 0,
      durationSeconds: int.tryParse('${path['duration'] ?? ''}') ?? 0,
      tollsYuan: double.tryParse('${path['tolls'] ?? ''}') ?? 0,
      polyline: List.unmodifiable(points),
      instructions: instructions,
      travelMode: request.travelMode,
    );
  }

  Iterable<GeoPoint> _parsePolyline(String value) sync* {
    for (final pair in value.split(';')) {
      final parts = pair.split(',');
      if (parts.length != 2) continue;
      final longitude = double.tryParse(parts[0]);
      final latitude = double.tryParse(parts[1]);
      if (longitude == null || latitude == null) continue;
      yield GeoPoint(
        latitude: latitude,
        longitude: longitude,
        coordinateSystem: CoordinateSystem.gcj02,
      ).validate();
    }
  }
}
