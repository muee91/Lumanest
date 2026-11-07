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
    this.watchIntentRevision = 0,
    this.endsAt,
    this.destinationName,
    this.destinationLatitude,
    this.destinationLongitude,
    this.destinationSystem,
    this.intent,
  });

  final String id;
  final MissionRemoteStage stage;
  final int version;
  final bool watchEnabled;
  final int watchIntentRevision;
  final DateTime? endsAt;
  final String? destinationName;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final String? destinationSystem;
  final String? intent;

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
    final destination = raw['destination'];
    final endsAt = raw['endsAt'] is String
        ? DateTime.tryParse(raw['endsAt'] as String)?.toUtc()
        : null;
    return MissionRemoteSnapshot(
      id: id,
      stage: stage,
      version: version,
      watchEnabled: watchEnabled,
      watchIntentRevision:
          raw['watchIntentRevision'] is int &&
              (raw['watchIntentRevision'] as int) >= 0
          ? raw['watchIntentRevision'] as int
          : 0,
      endsAt: endsAt,
      destinationName: destination is Map && destination['name'] is String
          ? destination['name'] as String
          : null,
      destinationLatitude: destination is Map && destination['latitude'] is num
          ? (destination['latitude'] as num).toDouble()
          : null,
      destinationLongitude:
          destination is Map && destination['longitude'] is num
          ? (destination['longitude'] as num).toDouble()
          : null,
      destinationSystem: destination is Map && destination['system'] is String
          ? destination['system'] as String
          : null,
      intent: raw['intent'] is String ? raw['intent'] as String : null,
    );
  }

  static MissionRemoteStage? _stage(String value) {
    for (final stage in MissionRemoteStage.values) {
      if (stage.name == value) return stage;
    }
    return null;
  }
}

/// The server rejected this operation before applying it because the Mission
/// version has advanced. An idempotency mismatch does not carry this proof.
class MissionVersionConflict implements Exception {
  const MissionVersionConflict(this.current);
  final MissionRemoteSnapshot current;
}

class MissionStaleWatchIntent implements Exception {
  const MissionStaleWatchIntent(this.current);
  final MissionRemoteSnapshot current;
}

class MissionLegacyOperationUnverifiable implements Exception {
  const MissionLegacyOperationUnverifiable();
}

class MissionOperationRecord {
  const MissionOperationRecord({
    required this.missionId,
    required this.verifiable,
    required this.status,
  });
  final String? missionId;
  final bool verifiable;
  final int status;
}

abstract interface class MissionRemoteRepository {
  Future<MissionRemoteSnapshot?> get(String missionId);

  Future<MissionOperationRecord?> getOperation(String operationId);

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
    int? intentRevision,
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
  Future<MissionOperationRecord?> getOperation(String operationId) async {
    try {
      final response = await dio.get<Object?>(
        Uri.parse(brokerBaseUrl).resolve('/v1/mission-operations').toString(),
        options: Options(
          headers: {
            'Authorization': 'Bearer $serviceToken',
            'Idempotency-Key': operationId,
          },
        ),
      );
      final data = response.data;
      if (data is! Map ||
          data['verifiable'] is! bool ||
          data['status'] is! int ||
          (data['missionId'] != null && data['missionId'] is! String)) {
        return null;
      }
      return MissionOperationRecord(
        missionId: data['missionId'] as String?,
        verifiable: data['verifiable'] as bool,
        status: data['status'] as int,
      );
    } on DioException {
      return null;
    }
  }

  @override
  Future<MissionRemoteSnapshot?> get(String missionId) async {
    try {
      final response = await dio.get<Object?>(
        Uri.parse(brokerBaseUrl).resolve('/v1/missions/$missionId').toString(),
        options: Options(headers: {'Authorization': 'Bearer $serviceToken'}),
      );
      return MissionRemoteSnapshot.fromJson(response.data);
    } on DioException {
      return null;
    }
  }

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
    } on DioException catch (error) {
      if (error.response?.statusCode == 409 &&
          error.response?.data is Map &&
          (error.response!.data as Map)['error'] ==
              'legacy_operation_unverifiable') {
        throw const MissionLegacyOperationUnverifiable();
      }
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
    int? intentRevision,
  }) async {
    try {
      final response = await dio.patch<Object?>(
        Uri.parse(brokerBaseUrl).resolve('/v1/missions/$missionId').toString(),
        data: {
          'expectedVersion': expectedVersion,
          'operation': operation,
          'watchEnabled': watchEnabled,
          'intentRevision': intentRevision,
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
    } on DioException catch (error) {
      final data = error.response?.data;
      if (error.response?.statusCode == 409 &&
          data is Map &&
          data['error'] == 'legacy_operation_unverifiable') {
        throw const MissionLegacyOperationUnverifiable();
      }
      if (error.response?.statusCode == 409 && data is Map) {
        final current = MissionRemoteSnapshot.fromJson(data['current']);
        if (data['error'] == 'stale_watch_intent' && current != null) {
          throw MissionStaleWatchIntent(current);
        }
        if (current != null &&
            current.id == missionId &&
            current.version > expectedVersion) {
          throw MissionVersionConflict(current);
        }
      }
      return null;
    }
  }
}
