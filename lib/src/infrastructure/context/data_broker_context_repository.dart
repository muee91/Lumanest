import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/remote_context_repository.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';

abstract interface class ContextDataTransport {
  Future<Map<String, Object?>> post(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  });
}

class DioContextDataTransport implements ContextDataTransport {
  DioContextDataTransport(this._dio);

  final Dio _dio;

  @override
  Future<Map<String, Object?>> post(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    final response = await _dio.postUri<Object?>(
      uri,
      data: body,
      options: Options(headers: headers),
    );
    final data = response.data;
    if (data is! Map) throw const FormatException('Invalid context response');
    return Map<String, Object?>.from(data);
  }
}

class DataBrokerContextRepository implements RemoteContextRepository {
  const DataBrokerContextRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final ContextDataTransport transport;

  @override
  Future<ContextSnapshot> enrich({
    required ContextSnapshot base,
    required WeatherObservation weather,
    required SolarState solar,
  }) async {
    final location = base.location;
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty || location == null) {
      throw const RemoteContextFailure(RemoteContextFailureKind.configuration);
    }
    final uri = Uri.parse(brokerBaseUrl).resolve('/v1/context/snapshot');
    try {
      final body = await transport.post(
        uri,
        headers: {'Authorization': 'Bearer $serviceToken'},
        body: _request(base, weather, solar),
      );
      return _parse(body, base);
    } on RemoteContextFailure {
      rethrow;
    } on DioException {
      throw const RemoteContextFailure(RemoteContextFailureKind.network);
    } catch (_) {
      throw const RemoteContextFailure(RemoteContextFailureKind.response);
    }
  }

  Map<String, Object?> _request(
    ContextSnapshot base,
    WeatherObservation weather,
    SolarState solar,
  ) {
    final scene = base.primaryScene;
    return {
      'contractVersion': 2,
      'coordinate': {
        'latitude': base.location!.latitude,
        'longitude': base.location!.longitude,
        'system': 'wgs84',
      },
      'observedAt': base.observedAt.toUtc().toIso8601String(),
      'locale': 'zh-CN',
      'intent': 'photography',
      'route': {
        'mode': scene == SceneType.hiking
            ? 'hiking'
            : scene == SceneType.driving
            ? 'driving'
            : 'none',
        'stage': base.activeRoute ? 'active' : 'none',
      },
      'evidence': {
        'urban': scene == SceneType.city,
        'waterBody': scene == SceneType.lake,
        'mountainous': scene == SceneType.mountain,
        'aridLand': scene == SceneType.desert,
        'settlement': scene == SceneType.village,
      },
      'weather': {
        'observedAt': weather.observedAt.toUtc().toIso8601String(),
        'condition': switch (weather.condition) {
          WeatherCondition.thunder => 'rain',
          _ => weather.condition.name,
        },
        'windSpeedMps': weather.windSpeedMetersPerSecond,
        'precipitationMm': weather.precipitationMillimeters,
        'visibilityKm': weather.visibilityKilometers,
        'thunder': weather.hasThunder,
        'stale': base.isStale,
      },
      'solar': {'dayPhase': solar.dayPhase.name},
    };
  }

  ContextSnapshot _parse(Map<String, Object?> body, ContextSnapshot base) {
    if (body['contractVersion'] != 2 ||
        body['contextId'] is! String ||
        body['scene'] is! String ||
        body['events'] is! List) {
      throw const RemoteContextFailure(RemoteContextFailureKind.response);
    }
    final scene = SceneType.values
        .where((value) => value.name == body['scene'])
        .firstOrNull;
    final events = (body['events'] as List).map(_event).toList(growable: false);
    final generatedAt = DateTime.tryParse('${body['generatedAt'] ?? ''}');
    final expiresAt = DateTime.tryParse('${body['expiresAt'] ?? ''}');
    if (scene == null || generatedAt == null || expiresAt == null) {
      throw const RemoteContextFailure(RemoteContextFailureKind.response);
    }
    return base.withRemoteContext(
      id: body['contextId']! as String,
      expiresAt: expiresAt.toUtc(),
      primaryScene: scene,
      events: events,
    );
  }

  ContextEvent _event(Object? raw) {
    if (raw is! Map) throw const FormatException('Invalid context event');
    final value = Map<String, Object?>.from(raw);
    final channel = ContextEventChannel.values
        .where((item) => item.name == value['channel'])
        .firstOrNull;
    final source = ContextEventSource.values
        .where((item) => item.name == value['source'])
        .firstOrNull;
    final observedAt = DateTime.tryParse('${value['observedAt'] ?? ''}');
    final expiresAt = DateTime.tryParse('${value['expiresAt'] ?? ''}');
    final confidence = value['confidence'];
    if (value['id'] is! String ||
        channel == null ||
        source == null ||
        observedAt == null ||
        expiresAt == null ||
        confidence is! num ||
        confidence < 0 ||
        confidence > 1) {
      throw const FormatException('Invalid context event');
    }
    return ContextEvent(
      id: value['id']! as String,
      channel: channel,
      source: source,
      observedAt: observedAt.toUtc(),
      expiresAt: expiresAt.toUtc(),
      confidence: confidence.toDouble(),
    );
  }
}
