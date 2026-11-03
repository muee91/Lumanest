import 'package:dio/dio.dart';

enum MissionRemoteStage { planning, enRoute, field, completed, cancelled }

class MissionDraft {
  const MissionDraft({
    required this.destinationName,
    required this.latitude,
    required this.longitude,
    required this.intent,
    required this.locale,
    required this.watchEnabled,
  });

  final String destinationName;
  final double latitude;
  final double longitude;
  final String intent;
  final String locale;
  final bool watchEnabled;

  Map<String, Object?> toJson() => {
    'destination': {
      'name': destinationName,
      'latitude': latitude,
      'longitude': longitude,
      'system': 'wgs84',
    },
    'intent': intent,
    'locale': locale,
    'startsAt': null,
    'endsAt': null,
    'watchEnabled': watchEnabled,
  };
}

class MissionRemoteSnapshot {
  const MissionRemoteSnapshot({
    required this.id,
    required this.stage,
    required this.version,
    required this.watchEnabled,
  });

  final String id;
  final MissionRemoteStage stage;
  final int version;
  final bool watchEnabled;

  static MissionRemoteSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final state = raw['state'];
    final version = raw['version'];
    final watchEnabled = raw['watchEnabled'];
    if (id is! String ||
        state is! String ||
        version is! int ||
        watchEnabled is! bool ||
        !id.startsWith('mis_')) {
      return null;
    }
    final stage = _stage(state);
    if (stage == null || version < 1) return null;
    return MissionRemoteSnapshot(
      id: id,
      stage: stage,
      version: version,
      watchEnabled: watchEnabled,
    );
  }

  static MissionRemoteStage? _stage(String value) {
    for (final stage in MissionRemoteStage.values) {
      if (stage.name == value) return stage;
    }
    return null;
  }
}

abstract interface class MissionRemoteRepository {
  Future<MissionRemoteSnapshot?> create(
    MissionDraft draft, {
    required String operationId,
  });

  Future<MissionRemoteSnapshot?> patch(
    String missionId, {
    required int expectedVersion,
    required String operation,
    required String operationId,
    bool? watchEnabled,
  });
}

class DioMissionRemoteRepository implements MissionRemoteRepository {
  const DioMissionRemoteRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.dio,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final Dio dio;

  @override
  Future<MissionRemoteSnapshot?> create(
    MissionDraft draft, {
    required String operationId,
  }) async {
    try {
      final response = await dio.post<Object?>(
        Uri.parse(brokerBaseUrl).resolve('/v1/missions').toString(),
        data: draft.toJson(),
        options: Options(
          headers: {
            'Authorization': 'Bearer $serviceToken',
            'Idempotency-Key': operationId,
          },
        ),
      );
      return MissionRemoteSnapshot.fromJson(response.data);
    } on DioException {
      return null;
    }
  }

  @override
  Future<MissionRemoteSnapshot?> patch(
    String missionId, {
    required int expectedVersion,
    required String operation,
    required String operationId,
    bool? watchEnabled,
  }) async {
    try {
      final response = await dio.patch<Object?>(
        Uri.parse(brokerBaseUrl).resolve('/v1/missions/$missionId').toString(),
        data: {
          'expectedVersion': expectedVersion,
          'operation': operation,
          'watchEnabled': watchEnabled,
          'destination': null,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $serviceToken',
            'Idempotency-Key': operationId,
          },
        ),
      );
      return MissionRemoteSnapshot.fromJson(response.data);
    } on DioException {
      return null;
    }
  }
}
